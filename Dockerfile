FROM alpine:3.20 AS builder

WORKDIR /build

# 安装构建依赖
RUN apk add --no-cache \
    build-base \
    curl \
    wget \
    bash \
    git \
    tar \
    sed \
    grep \
    perl \
    make \
    autoconf \
    automake \
    libtool \
    pkgconfig \
    linux-headers \
    gcc \
    g++ \
    musl-dev \
    libc-dev \
    openssl-dev \
    zlib-dev \
    yajl-dev \
    lmdb-dev \
    lua-dev \
    libxml2-dev \
    libxslt-dev \
    geoip-dev \
    pcre-dev \
    pcre2-dev \
    brotli-dev

# 自动获取各依赖的版本号（可自行指定默认版本）
RUN set -ex && \
  NGINX_VERSION=$(wget -q -O - https://nginx.org/en/download.html | grep -oE 'nginx-[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | cut -d'-' -f2) && \
  OPENSSL_VERSION=$(wget -q -O - https://www.openssl.org/source/ | grep -oE 'openssl-[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | cut -d'-' -f2) && \
  ZLIB_VERSION=$(wget -q -O - https://zlib.net/ | grep -oE 'zlib-[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | cut -d'-' -f2) && \
  NGINX_VERSION="${NGINX_VERSION:-1.29.0}" && \
  OPENSSL_VERSION="${OPENSSL_VERSION:-3.3.0}" && \
  ZLIB_VERSION="${ZLIB_VERSION:-1.3.1}" && \
  echo "Using: nginx-${NGINX_VERSION}, openssl-${OPENSSL_VERSION}, zlib-${ZLIB_VERSION}" && \
\
# 下载并构建 ModSecurity 库
  git clone --depth 1 https://github.com/owasp-modsecurity/ModSecurity && \
  cd ModSecurity && \
  git submodule update --init --recursive && \
  ./build.sh && \
  ./configure --prefix=/opt/modsecurity --enable-static --disable-shared && \
  make -j$(nproc) && make install && \
  cp /opt/modsecurity/lib/pkgconfig/modsecurity.pc /usr/lib/pkgconfig && \
\
# 下载 ModSecurity-nginx connector
  cd /build && \
  git clone --depth 1 https://github.com/owasp-modsecurity/ModSecurity-nginx && \
\
# 下载 NGINX、OpenSSL、Zlib 源码
  curl -fSL https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz -o nginx.tar.gz && \
  tar xzf nginx.tar.gz && \
  curl -fSL https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz -o openssl.tar.gz && \
  tar xzf openssl.tar.gz && \
  curl -fSL https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz -o zlib.tar.gz && \
  tar xzf zlib.tar.gz && \
\
# 构建 NGINX + ModSecurity
  cd nginx-${NGINX_VERSION} && \
  PKG_CONFIG_PATH="/usr/lib/pkgconfig:/opt/modsecurity/lib/pkgconfig" ./configure \
    --prefix=/etc/nginx \
    --user=root \
    --group=root \
    --with-cc-opt="-static -I/opt/modsecurity/include" \
    --with-ld-opt="-static -L/opt/modsecurity/lib -lmodsecurity" \
    --with-openssl=../openssl-${OPENSSL_VERSION} \
    --with-zlib=../zlib-${ZLIB_VERSION} \
    --add-module=../ModSecurity-nginx \
    --with-compat \
    --with-pcre \
    --with-pcre-jit \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_gzip_static_module \
    --with-http_sub_module \
    --with-http_stub_status_module \
    --with-http_realip_module \
    --with-http_geoip_module \
    --with-stream \
    --with-threads && \
  make -j$(nproc) && \
  make install && \
  strip /etc/nginx/sbin/nginx

# 最小运行时镜像
FROM busybox:1.35-uclibc

# 拷贝构建产物
COPY --from=builder /etc/nginx /etc/nginx

# 暴露端口
EXPOSE 80 443

WORKDIR /etc/nginx

# 启动 nginx
CMD ["./sbin/nginx", "-g", "daemon off;"]
