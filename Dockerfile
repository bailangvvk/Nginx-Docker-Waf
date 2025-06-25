# syntax=docker/dockerfile:1

FROM alpine:3.20 AS builder

# 可选手动传参，否则自动抓最新版
ARG NGINX_VERSION
ARG OPENSSL_VERSION
ARG ZLIB_VERSION
ARG BROTLI_VERSION
ARG ZSTD_VERSION

WORKDIR /build

# 安装构建依赖（新增git支持）
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
    git \
    ca-certificates \
    && update-ca-certificates

# 自动抓取最新版本（含fallback）
RUN \
  # Nginx版本
  NGINX_VERSION="${NGINX_VERSION:-$( \
    curl -s https://nginx.org/en/download.html | \
    grep -oP 'nginx-\K[0-9]+\.[0-9]+\.[0-9]+(?=\.tar\.gz)' | \
    head -n1 \
  )}" && \
  NGINX_VERSION="${NGINX_VERSION:-1.29.0}" && \
  \
  # OpenSSL版本
  OPENSSL_VERSION="${OPENSSL_VERSION:-$( \
    curl -s https://www.openssl.org/source/ | \
    grep -oP 'openssl-\K[0-9]+\.[0-9]+\.[0-9]+[a-z]?(?=\.tar\.gz)' | \
    grep -vE 'fips|alpha|beta' | \
    head -n1 \
  )}" && \
  OPENSSL_VERSION="${OPENSSL_VERSION:-3.1.5}" && \
  \
  # zlib版本
  ZLIB_VERSION="${ZLIB_VERSION:-$( \
    curl -s https://zlib.net/ | \
    grep -oP 'zlib-\K[0-9]+\.[0-9]+\.[0-9]+(?=\.tar\.gz)' | \
    head -n1 \
  )}" && \
  ZLIB_VERSION="${ZLIB_VERSION:-1.2.13}" && \
  \
  # Brotli模块版本（ngx_brotli）
  BROTLI_VERSION="${BROTLI_VERSION:-$( \
    curl -s https://api.github.com/repos/google/ngx_brotli/releases/latest | \
    grep -oP '"tag_name": "\Kv?[0-9]+\.[0-9]+\.[0-9]+(?=")' | \
    head -n1 \
  )}" && \
  BROTLI_VERSION="${BROTLI_VERSION:-1.0.9}" && \
  \
  # ZSTD版本
  ZSTD_VERSION="${ZSTD_VERSION:-$( \
    curl -s https://api.github.com/repos/facebook/zstd/releases/latest | \
    grep -oP '"tag_name": "\Kv?[0-9]+\.[0-9]+\.[0-9]+(?=")' | \
    head -n1 \
  )}" && \
  ZSTD_VERSION="${ZSTD_VERSION:-1.5.5}" && \
  \
  echo "==> Using versions: nginx-${NGINX_VERSION}, openssl-${OPENSSL_VERSION}, zlib-${ZLIB_VERSION}, brotli-${BROTLI_VERSION}, zstd-${ZSTD_VERSION}" && \
  \
  # 下载Nginx
  curl -fSL https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz -o nginx.tar.gz && \
  tar xzf nginx.tar.gz && \
  \
  # 下载OpenSSL
  curl -fSL https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz -o openssl.tar.gz && \
  tar xzf openssl.tar.gz && \
  \
  # 下载zlib
  curl -fSL https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz -o zlib.tar.gz && \
  tar xzf zlib.tar.gz && \
  \
  # 克隆Brotli模块
  git clone --depth=1 -b $(echo ${BROTLI_VERSION} | sed 's/^v//') https://github.com/google/ngx_brotli.git ngx_brotli && \
  cd ngx_brotli && \
  git submodule update --init && \
  cd .. && \
  \
  # 下载并编译ZSTD
  curl -fSL https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz -o zstd.tar.gz && \
  tar xzf zstd.tar.gz && \
  cd zstd-${ZSTD_VERSION} && \
  make -j$(nproc) libzstd.a && \
  mkdir -p /usr/local/zstd/lib /usr/local/zstd/include && \
  cp lib/libzstd.a /usr/local/zstd/lib/ && \
  cp -r lib/zstd.h lib/zstd_errors.h /usr/local/zstd/include/ && \
  cd .. && \
  \
  # 编译Nginx（添加Brotli和ZSTD支持）
  cd nginx-${NGINX_VERSION} && \
  ./configure \
    --user=root \
    --group=root \
    --with-cc-opt="-static -static-libgcc -I/usr/local/zstd/include" \
    --with-ld-opt="-static -L/usr/local/zstd/lib -lzstd" \
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

# 拷贝构建产物和ZSTD库
COPY --from=builder /usr/local/nginx /usr/local/nginx
COPY --from=builder /usr/local/zstd/lib/libzstd.a /usr/local/zstd/lib/libzstd.a

# 暴露端口
EXPOSE 80 443

WORKDIR /usr/local/nginx

# 启动nginx（设置库路径）
ENV LD_LIBRARY_PATH=/usr/local/zstd/lib
CMD ["./sbin/nginx", "-g", "daemon off;"]
