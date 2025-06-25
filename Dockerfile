# syntax=docker/dockerfile:1

FROM alpine:3.20 AS builder

# 可选手动传参，否则使用固定版本
ARG NGINX_VERSION=1.25.1
ARG OPENSSL_VERSION=3.1.5
ARG ZLIB_VERSION=1.2.13
ARG BROTLI_VERSION=1.0.9
ARG ZSTD_VERSION=1.5.5

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
    git \
    ca-certificates

# 明确使用固定版本（避免网络请求失败）
RUN \
  NGINX_VERSION="${NGINX_VERSION}" && \
  OPENSSL_VERSION="${OPENSSL_VERSION}" && \
  ZLIB_VERSION="${ZLIB_VERSION}" && \
  BROTLI_VERSION="${BROTLI_VERSION}" && \
  ZSTD_VERSION="${ZSTD_VERSION}" && \
  \
  echo "==> Using fixed versions: nginx-${NGINX_VERSION}, openssl-${OPENSSL_VERSION}, zlib-${ZLIB_VERSION}, brotli-${BROTLI_VERSION}, zstd-${ZSTD_VERSION}" && \
  \
  # 下载Nginx源码（使用固定URL避免版本解析问题）
  curl -fSL https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz -o nginx.tar.gz && \
  tar xzf nginx.tar.gz && \
  \
  # 下载OpenSSL源码
  curl -fSL https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz -o openssl.tar.gz && \
  tar xzf openssl.tar.gz && \
  \
  # 下载zlib源码
  curl -fSL https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz -o zlib.tar.gz && \
  tar xzf zlib.tar.gz && \
  \
  # 获取Brotli模块（使用固定版本URL）
  git clone --depth=1 -b v${BROTLI_VERSION} https://github.com/google/ngx_brotli.git ngx_brotli && \
  cd ngx_brotli && \
  git submodule update --init && \
  cd .. && \
  \
  # 下载并编译ZSTD库
  curl -fSL https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz -o zstd.tar.gz && \
  tar xzf zstd.tar.gz && \
  cd zstd-${ZSTD_VERSION} && \
  make -j$(nproc) libzstd.a && \
  mkdir -p /usr/local/zstd/lib /usr/local/zstd/include && \
  cp lib/libzstd.a /usr/local/zstd/lib/ && \
  cp -r lib/zstd.h lib/zstd_errors.h /usr/local/zstd/include/ && \
  cd .. && \
  \
  # 编译Nginx
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

# 拷贝构建产物
COPY --from=builder /usr/local/nginx /usr/local/nginx
COPY --from=builder /usr/local/zstd/lib/libzstd.a /usr/local/zstd/lib/libzstd.a

# 暴露端口
EXPOSE 80 443

WORKDIR /usr/local/nginx

# 启动nginx
CMD ["./sbin/nginx", "-g", "daemon off;"]
