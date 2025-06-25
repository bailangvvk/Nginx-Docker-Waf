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
    pcre-dev \
    zlib-dev \
    linux-headers \
    perl \
    sed \
    grep \
    tar \
    bash \
    jq \
    git \
    && \
  NGINX_VERSION=$(wget -q -O - https://nginx.org/en/download.html | grep -oE 'nginx-[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | cut -d'-' -f2) \
  && \
  OPENSSL_VERSION=$(wget -q -O - https://www.openssl.org/source/ | grep -oE 'openssl-[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | cut -d'-' -f2) \
  && \
  ZLIB_VERSION=$(wget -q -O - https://zlib.net/ | grep -oE 'zlib-[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | cut -d'-' -f2) \
  && \
  ZSTD_VERSION=$(curl -Ls https://github.com/facebook/zstd/releases/latest | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | cut -c2-) \
  && \
  CORERULESET_VERSION=$(curl -s https://api.github.com/repos/coreruleset/coreruleset/releases/latest | grep -oE '"tag_name": "[^"]+' | cut -d'"' -f4 | sed 's/v//') \
  && \
  git clone --recurse-submodules -j8 https://github.com/google/ngx_brotli \
  && \
  \
  echo "=============版本号=============" && \
  echo "NGINX_VERSION=${NGINX_VERSION}" && \
  echo "OPENSSL_VERSION=${OPENSSL_VERSION}" && \
  echo "ZLIB_VERSION=${ZLIB_VERSION}" && \
  echo "ZSTD_VERSION=${ZSTD_VERSION}" && \
  echo "CORERULESET_VERSION=${CORERULESET_VERSION}" && \
  \
  # fallback 以防 curl/grep 失败
  NGINX_VERSION="${NGINX_VERSION:-1.29.0}" && \
  OPENSSL_VERSION="${OPENSSL_VERSION:-3.3.0}" && \
  ZLIB_VERSION="${ZLIB_VERSION:-1.3.1}" && \
  ZSTD_VERSION="${ZSTD_VERSION:-1.5.7}" && \
  CORERULESET_VERSION="${CORERULESET_VERSION}" && \
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
  cd nginx-${NGINX_VERSION} && \
  # ./configure \
  #   --prefix=/etc/nginx \
  #   --user=root \
  #   --group=root \
  #   --with-cc-opt="-static -static-libgcc" \
  #   --with-ld-opt="-static" \
  #   --with-openssl=../openssl-${OPENSSL_VERSION} \
  #   --with-zlib=../zlib-${ZLIB_VERSION} \
  #   --with-pcre \
  #   --with-pcre-jit \
  #   --with-http_ssl_module \
  #   --with-http_v2_module \
  #   --with-http_gzip_static_module \
  #   --with-http_stub_status_module \
  #   --without-http_rewrite_module \
  #   --without-http_auth_basic_module \
  #   --with-threads && \
./configure \
    --prefix=/etc/nginx \
    --user=root \
    --group=root \
    --with-cc-opt="-static -static-libgcc" \
    --with-ld-opt="-static" \
    --with-openssl=../openssl-* \
    --with-zlib=../zlib-* \
    --with-compat \
    --with-ngx_brotli=../ngx_brotli \
    --with-pcre \
    --with-pcre-jit \
    --with-threads \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_gzip_static_module \
    --with-http_stub_status_module \
    --with-stream \
    --with-stream_ssl_module \
    --with-mail \
    --with-mail_ssl_module && \
  make -j$(nproc) && \
  make install \
  && \
  strip /etc/nginx/sbin/nginx


# 最小运行时镜像
FROM busybox:1.35-uclibc
# FROM gcr.io/distroless/static

# 拷贝构建产物
COPY --from=builder /etc/nginx /etc/nginx

# 复制压缩模块和 ModSecurity
# COPY --from=builder /etc/nginx/objs/*.so /etc/nginx/modules/

# 暴露端口
EXPOSE 80 443

WORKDIR /etc/nginx

# 启动 nginx
CMD ["./sbin/nginx", "-g", "daemon off;"]
