# syntax=docker/dockerfile:1
FROM alpine:3.20 AS builder

WORKDIR /build

RUN apk add --no-cache \
    build-base \
    curl \
    git \
    bash \
    linux-headers \
    pcre-dev \
    zlib-dev \
    openssl-dev \
    libxml2-dev \
    libxslt-dev \
    yajl-dev \
    lmdb-dev \
    lua-dev \
    geoip-dev \
    brotli-dev \
    libtool \
    autoconf \
    automake \
    pkgconfig \
    perl \
    sed \
    grep \
    make \
    g++ \
    wget

# 设置版本号（可改）
ARG NGINX_VERSION=1.29.0
ARG OPENSSL_VERSION=3.3.0
ARG ZLIB_VERSION=1.3.1

RUN set -ex && \
    echo "Using: nginx-${NGINX_VERSION}, openssl-${OPENSSL_VERSION}, zlib-${ZLIB_VERSION}" && \

    # 构建 ModSecurity（动态）
    git clone --depth 1 https://github.com/owasp-modsecurity/ModSecurity && \
    cd ModSecurity && \
    git submodule update --init --recursive && \
    ./build.sh && \
    ./configure --prefix=/usr/local/modsecurity --enable-shared --disable-static && \
    make -j$(nproc) && \
    make install && \
    cp /usr/local/modsecurity/lib/pkgconfig/modsecurity.pc /usr/lib/pkgconfig && \
    cd .. && \

    # 克隆 ModSecurity-nginx connector
    git clone --depth 1 https://github.com/owasp-modsecurity/ModSecurity-nginx && \

    # 下载并解压 Nginx、OpenSSL、Zlib
    curl -fSL https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz | tar xz && \
    curl -fSL https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz | tar xz && \
    curl -fSL https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz | tar xz && \

    # 构建 Nginx（全静态，加载动态 ModSecurity）
    cd nginx-${NGINX_VERSION} && \
    PKG_CONFIG_PATH="/usr/lib/pkgconfig:/usr/local/modsecurity/lib/pkgconfig" ./configure \
        --prefix=/etc/nginx \
        --user=root \
        --group=root \
        --with-cc-opt="-static -I/usr/local/modsecurity/include" \
        --with-ld-opt="-static -L/usr/local/modsecurity/lib -lmodsecurity" \
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
    make -j$(nproc) && make install && strip /etc/nginx/sbin/nginx

# ---

# ✅ 最小运行镜像：Alpine + libmodsecurity 运行依赖
FROM alpine:3.20 AS runtime

# 安装运行依赖
RUN apk add --no-cache \
    libstdc++ \
    yajl \
    libxml2 \
    lua \
    curl \
    geoip \
    brotli

# 拷贝构建产物
COPY --from=builder /etc/nginx /etc/nginx
COPY --from=builder /usr/local/modsecurity /usr/local/modsecurity

# 环境变量指定动态库搜索路径
ENV LD_LIBRARY_PATH=/usr/local/modsecurity/lib

EXPOSE 80 443
WORKDIR /etc/nginx
CMD ["./sbin/nginx", "-g", "daemon off;"]
