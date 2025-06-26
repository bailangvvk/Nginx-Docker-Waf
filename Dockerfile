FROM alpine:3.20 AS builder

WORKDIR /build

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
    geoip-dev \
    brotli-dev \
    wget \
    make \
    gcc \
    g++ \
    musl-dev \
    libxslt-dev \
    libxml2-dev \
    autoconf \
    automake \
    libtool \
    openssl-dev \
    yajl-dev \
    lmdb-dev \
    lua-dev \
    pkgconfig \
    pcre2-dev

RUN set -ex && \
    # 获取版本号
    NGINX_VERSION=$(wget -q -O - https://nginx.org/en/download.html | grep -oE 'nginx-[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | cut -d'-' -f2) && \
    OPENSSL_VERSION=$(wget -q -O - https://www.openssl.org/source/ | grep -oE 'openssl-[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | cut -d'-' -f2) && \
    ZLIB_VERSION=$(wget -q -O - https://zlib.net/ | grep -oE 'zlib-[0-9]+\.[0-9]+\.[0-9]+' | head -n1 | cut -d'-' -f2) && \
    NGINX_VERSION="${NGINX_VERSION:-1.29.0}" && \
    OPENSSL_VERSION="${OPENSSL_VERSION:-3.3.0}" && \
    ZLIB_VERSION="${ZLIB_VERSION:-1.3.1}" && \
    echo "Using: nginx-${NGINX_VERSION}, openssl-${OPENSSL_VERSION}, zlib-${ZLIB_VERSION}" && \
    \
    # 克隆并编译 ModSecurity，安装到 /usr/local/modsecurity
    git clone --depth 1 https://github.com/owasp-modsecurity/ModSecurity && \
    cd ModSecurity && \
    git submodule update --init --recursive && \
    ./build.sh && \
    ./configure --prefix=/usr/local/modsecurity --enable-static --disable-shared && \
    make -j$(nproc) && \
    make install && \
    # 把 pkgconfig 文件复制到标准路径，方便 nginx configure 找到
    cp /usr/local/modsecurity/lib/pkgconfig/modsecurity.pc /usr/lib/pkgconfig/ && \
    cd .. && \
    \
    # 克隆 ModSecurity-nginx connector
    git clone --depth 1 https://github.com/owasp-modsecurity/ModSecurity-nginx && \
    \
    # 下载 nginx, openssl, zlib 源码
    curl -fSL https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz -o nginx.tar.gz && \
    tar xzf nginx.tar.gz && \
    curl -fSL https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz -o openssl.tar.gz && \
    tar xzf openssl.tar.gz && \
    curl -fSL https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz -o zlib.tar.gz && \
    tar xzf zlib.tar.gz && \
    \
    # 编译 nginx，加载 ModSecurity 模块
    cd nginx-${NGINX_VERSION} && \
    PKG_CONFIG_PATH="/usr/lib/pkgconfig:/usr/local/modsecurity/lib/pkgconfig" ./configure \
      --prefix=/etc/nginx \
      --user=root \
      --group=root \
      --with-cc-opt="-I/usr/local/modsecurity/include -static" \
      --with-ld-opt="-L/usr/local/modsecurity/lib -lmodsecurity -static" \
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

# 下面可继续构建最小运行时镜像，比如用 busybox 或 alpine 等
FROM busybox:1.35-uclibc

COPY --from=builder /etc/nginx /etc/nginx

EXPOSE 80 443

WORKDIR /etc/nginx

CMD ["./sbin/nginx", "-g", "daemon off;"]
