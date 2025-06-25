# syntax=docker/dockerfile:1

FROM alpine:3.20 AS builder

# 可选手动传参，否则自动抓最新版
ARG NGINX_VERSION
ARG OPENSSL_VERSION
ARG ZLIB_VERSION
ARG BROTLI_VERSION
ARG ZSTD_VERSION

WORKDIR /build

# 安装构建依赖
RUN apk add --no-cache \
    build-base \
    curl \
    pcre-dev \
    zlib-dev \
    linux-headers \
    perl \
    sed \
    grep \
    tar \
    bash \
    git

# 自动抓取最新版本
RUN \
  NGINX_VERSION="${NGINX_VERSION:-$( \
    curl -s https://nginx.org/en/download.html | \
    grep -oP 'nginx-\K[0-9]+\.[0-9]+\.[0-9]+(?=\.tar\.gz)' | \
    head -n1 \
  )}" && \
  OPENSSL_VERSION="${OPENSSL_VERSION:-$( \
    curl -s https://www.openssl.org/source/ | \
    grep -oP 'openssl-\K[0-9]+\.[0-9]+\.[0-9]+[a-z]?(?=\.tar\.gz)' | \
    grep -vE 'fips|alpha|beta' | \
    head -n1 \
  )}" && \
  ZLIB_VERSION="${ZLIB_VERSION:-$( \
    curl -s https://zlib.net/ | \
    grep -oP 'zlib-\K[0-9]+\.[0-9]+\.[0-9]+(?=\.tar\.gz)' | \
    head -n1 \
  )}" && \
  BROTLI_VERSION="${BROTLI_VERSION:-$( \
    curl -s https://api.github.com/repos/google/ngx_brotli/releases/latest | \
    grep -oP '"tag_name": "\Kv?[0-9]+\.[0-9]+\.[0-9]+(?=")' | \
    head -n1 \
  )}" && \
  ZSTD_VERSION="${ZSTD_VERSION:-$( \
    curl -s https://api.github.com/repos/facebook/zstd/releases/latest | \
    grep -oP '"tag_name": "\Kv?[0-9]+\.[0-9]+\.[0-9]+(?=")' | \
    head -n1 \
  )}" && \
  \
  # fallback 以防 curl/grep 失败
  NGINX_VERSION="${NGINX_VERSION:-1.29.0}" && \
  OPENSSL_VERSION="${OPENSSL_VERSION:-3.3.0}" && \
  ZLIB_VERSION="${ZLIB_VERSION:-1.3.1}" && \
  BROTLI_VERSION="${BROTLI_VERSION:-1.0.0}" && \
  ZSTD_VERSION="${ZSTD_VERSION:-1.6.5}" && \
  \
  echo "==> Using versions: nginx-${NGINX_VERSION}, openssl-${OPENSSL_VERSION}, zlib-${ZLIB_VERSION}, brotli-${BROTLI_VERSION}, zstd-${ZSTD_VERSION}" && \
  \
  curl -fSL https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz -o nginx.tar.gz && \
  tar xzf nginx.tar.gz && \
  \
  curl -fSL https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz -o openssl.tar.gz && \
  tar xzf openssl.tar.gz && \
  \
  curl -fSL https://fossies.org/linux/misc/zlib-${ZLIB_VERSION}.tar.gz -o zlib.tar.gz && \
  tar xzf zlib.tar.gz && \
  \
  # 获取 Brotli 模块
  git clone --depth=1 https://github.com/google/ngx_brotli.git ngx_brotli && \
  cd ngx_brotli && \
  git submodule update --init && \
  cd .. && \
  \
  # 获取 ZSTD 库
  curl -fSL https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz -o zstd.tar.gz && \
  tar xzf zstd.tar.gz && \
  cd zstd-${ZSTD_VERSION} && \
  make -j$(nproc) libs && \
  make install PREFIX=/usr/local/zstd && \
  cd .. && \
  \
  cd nginx-${NGINX_VERSION} && \
  ./configure \
    --user=root \
    --group=root \
    --with-cc-opt="-static -static-libgcc -I/usr/local/zstd/include" \
    --with-ld-opt="-static -L/usr/local/zstd/lib" \
    --with-openssl=../openssl-${OPENSSL_VERSION} \
    --with-zlib=../zlib-${ZLIB_VERSION} \
    --with-pcre \
    --with-pcre-jit \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_gzip_static_module \
    --with-http_stub_status_module \
    --with-http_compression_level=9 \
    --add-module=../ngx_brotli \
    --with-threads \
    --without-http_rewrite_module \
    --without-http_auth_basic_module && \
  make -j$(nproc) && \
  make install && \
  strip /usr/local/nginx/sbin/nginx


# 最小运行时镜像
FROM busybox:1.35-uclibc
# FROM gcr.io/distroless/static

# 拷贝构建产物
COPY --from=builder /usr/local/nginx /usr/local/nginx
COPY --from=builder /usr/local/zstd/lib/libzstd.a /usr/local/zstd/lib/libzstd.a

# 暴露端口
EXPOSE 80 443

WORKDIR /usr/local/nginx

# 启动 nginx
CMD ["./sbin/nginx", "-g", "daemon off;"]
