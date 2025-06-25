# syntax=docker/dockerfile:1

FROM alpine:3.20 AS builder

# 可选手动传参，否则自动抓最新版
ARG NGINX_VERSION
ARG OPENSSL_VERSION
ARG ZLIB_VERSION

WORKDIR /build

# 安装构建依赖
RUN apk add --no-cache \
    build-base \
    curl \
    git \
    pcre-dev \
    zlib-dev \
    linux-headers \
    perl \
    sed \
    grep \
    tar \
    bash

# Clone Brotli module
RUN git clone --recurse-submodules -j8 https://github.com/google/ngx_brotli

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
  ZSTD_VERSION="${ZSTD_VERSION:-$( \
    curl -s https://github.com/facebook/zstd/releases/latest | \
    grep -oP 'tag/v\K[0-9]+\.[0-9]+\.[0-9]+' | \
    head -n1 \
  )}" && \
  \
  # fallback 以防 curl/grep 失败
  NGINX_VERSION="${NGINX_VERSION:-1.29.0}" && \
  OPENSSL_VERSION="${OPENSSL_VERSION:-3.3.0}" && \
  ZLIB_VERSION="${ZLIB_VERSION:-1.3.1}" && \
  ZSTD_VERSION="${ZSTD_VERSION:-1.5.0}" && \
  \
  echo "==> Using versions: nginx-${NGINX_VERSION}, openssl-${OPENSSL_VERSION}, zlib-${ZLIB_VERSION}" && \
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
  # 下载并构建 Zstandard
  wget https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz \
    && tar -xzf zstd-${ZSTD_VERSION}.tar.gz \
    && cd zstd-${ZSTD_VERSION} \
    && make clean \
    && CFLAGS="-fPIC" make && make install \
    && cd .. && \
  \
  # 下载并编译 Nginx
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
    --without-http_rewrite_module \
    --without-http_auth_basic_module \
    --with-threads && \
    --add-dynamic-module=../ngx_brotli \
    --add-dynamic-module=../zstd-nginx-module && \
  make -j$(nproc) && \
  make install && \
  strip /usr/local/nginx/sbin/nginx


# 最小运行时镜像
FROM busybox:1.35-uclibc
# FROM gcr.io/distroless/static

# 拷贝构建产物
COPY --from=builder /usr/local/nginx /usr/local/nginx
# 复制压缩模块
COPY --from=builder /usr/src/nginx/objs/*.so /etc/nginx/modules/

# 暴露端口
EXPOSE 80 443

WORKDIR /usr/local/nginx

# 启动 nginx
CMD ["./sbin/nginx", "-g", "daemon off;"]
