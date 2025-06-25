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
    zstd-dev \
    brotli-dev

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
    curl -s https://github.com/google/brotli/releases | \
    grep -oP 'href="/google/brotli/releases/tag/v[0-9]+\.[0-9]+\.[0-9]+"' | \
    head -n1 | \
    sed 's/href="\/google\/brotli\/releases\/tag\/v\(.*\)"/\1/' \
  )}" && \
  ZSTD_VERSION="${ZSTD_VERSION:-$( \
    curl -s https://github.com/facebook/zstd/releases | \
    grep -oP 'href="/facebook/zstd/releases/tag/v[0-9]+\.[0-9]+\.[0-9]+"' | \
    head -n1 | \
    sed 's/href="\/facebook\/zstd\/releases\/tag\/v\(.*\)"/\1/' \
  )}" && \
  echo "================检查一下版本号=========" && \
  echo "NGINX_VERSION=${NGINX_VERSION}" && \
  echo "OPENSSL_VERSION=${OPENSSL_VERSION}" && \
  echo "ZLIB_VERSION=${ZLIB_VERSION}" && \
  echo "BROTLI_VERSION=${BROTLI_VERSION}" && \
  echo "ZSTD_VERSION=${ZSTD_VERSION}" && \
  # fallback 以防 curl/grep 失败
  NGINX_VERSION="${NGINX_VERSION:-1.29.0}" && \
  OPENSSL_VERSION="${OPENSSL_VERSION:-3.3.0}" && \
  ZLIB_VERSION="${ZLIB_VERSION:-1.3.1}" && \
  BROTLI_VERSION="${BROTLI_VERSION:-1.0.9}" && \
  ZSTD_VERSION="${ZSTD_VERSION:-1.5.2}" && \
  \
  echo "==> Using versions: nginx-${NGINX_VERSION}, openssl-${OPENSSL_VERSION}, zlib-${ZLIB_VERSION}, brotli-${BROTLI_VERSION}, zstd-${ZSTD_VERSION}" && \
  \
  # 下载并解压 Nginx、OpenSSL 和 Zlib
  curl -fSL https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz -o nginx.tar.gz && \
  tar xzf nginx.tar.gz && \
  \
  curl -fSL https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz -o openssl.tar.gz && \
  tar xzf openssl.tar.gz && \
  \
  curl -fSL https://fossies.org/linux/misc/zlib-${ZLIB_VERSION}.tar.gz -o zlib.tar.gz && \
  tar xzf zlib.tar.gz && \
  \
  # 下载并解压 Brotli 和 Zstd
  curl -fSL https://github.com/google/brotli/archive/refs/tags/v${BROTLI_VERSION}.tar.gz -o brotli.tar.gz && \
  tar xzf brotli.tar.gz && \
  \
  curl -fSL https://github.com/facebook/zstd/archive/refs/tags/v${ZSTD_VERSION}.tar.gz -o zstd.tar.gz && \
  tar xzf zstd.tar.gz && \
  \
  # 编译 Nginx，添加 Brotli 和 Zstd 支持
  cd nginx-${NGINX_VERSION} && \
  ./configure \
    --user=root \
    --group=root \
    --with-cc-opt="-static -static-libgcc" \
    --with-ld-opt="-static" \
    --with-openssl=../openssl-${OPENSSL_VERSION} \
    --with-zlib=../zlib-${ZLIB_VERSION} \
    --with-pcre \
    --with-pcre-jit \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_gzip_static_module \
    --with-http_stub_status_module \
    --with-http_brotli_module=../brotli-${BROTLI_VERSION}/src \
    --with-http_zstd_module=../zstd-${ZSTD_VERSION}/lib \
    --without-http_rewrite_module \
    --without-http_auth_basic_module \
    --with-threads && \
  make -j$(nproc) && \
  make install && \
  strip /usr/local/nginx/sbin/nginx


# 最小运行时镜像
FROM busybox:1.35-uclibc
# FROM gcr.io/distroless/static

# 拷贝构建产物
COPY --from=builder /usr/local/nginx /usr/local/nginx

# 暴露端口
EXPOSE 80 443

WORKDIR /usr/local/nginx

# 启动 nginx
CMD ["./sbin/nginx", "-g", "daemon off;"]
