FROM alpine:latest AS builder

WORKDIR /usr/src

# 安装构建依赖
RUN apk add --no-cache \
    pcre-dev \
    zlib-dev \
    openssl-dev \
    wget \
    git \
    build-base \
    brotli-dev \
    libxml2-dev \
    libxslt-dev \
    curl-dev \
    yajl-dev \
    lmdb-dev \
    geoip-dev \
    lua-dev \
    automake \
    autoconf \
    libtool \
    pkgconfig \
    linux-headers \
    pcre2-dev \
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
    git clone --depth 1 https://github.com/owasp-modsecurity/ModSecurity \
    && cd ModSecurity \
    && git submodule update --init --depth 1 \
    && ./build.sh \
    && ./configure \
    && make -j$(nproc) \
    && make install && \
    git clone https://github.com/owasp-modsecurity/ModSecurity-nginx \
        && cd ModSecurity-nginx \
        && cd .. && \
    \
    echo "=============版本号=============" && \
    echo "NGINX_VERSION=${NGINX_VERSION}" && \
    echo "OPENSSL_VERSION=${OPENSSL_VERSION}" && \
    echo "ZLIB_VERSION=${ZLIB_VERSION}" && \
    echo "ZSTD_VERSION=${ZSTD_VERSION}" && \
    echo "CORERULESET_VERSION=${CORERULESET_VERSION}" && \
    # \
    # # fallback 以防 curl/grep 失败
    # NGINX_VERSION="${NGINX_VERSION:-1.29.0}" && \
    # OPENSSL_VERSION="${OPENSSL_VERSION:-3.3.0}" && \
    # ZLIB_VERSION="${ZLIB_VERSION:-1.3.1}" && \
    # ZSTD_VERSION="${ZSTD_VERSION:-1.5.7}" && \
    # CORERULESET_VERSION="${CORERULESET_VERSION}" && \
    \
    # echo "==> Using versions: nginx-${NGINX_VERSION}, openssl-${OPENSSL_VERSION}, zlib-${ZLIB_VERSION}" && \
    # \
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
    # make -j$(nproc) && \
    # make install && \
    # strip /etc/nginx/sbin/nginx
    ./configure \
    --with-compat \
    --with-cc-opt="-static -static-libgcc" \
    --with-ld-opt="-static" \
    # --add-dynamic-module=../ngx_brotli \
    --add-dynamic-module=../ModSecurity-nginx \
    # --add-dynamic-module=../zstd-nginx-module \
    && \
    make modules

# ✅ 最小运行镜像：Alpine + libmodsecurity 运行依赖
FROM alpine:3.20 AS runtime

# 安装运行依赖
RUN apk add --no-cache \
    lua5.1 \
    lua5.1-dev \
    pcre \
    pcre-dev \
    yajl \
    yajl-dev

# 拷贝构建产物
# COPY --from=builder /usr/src/nginx-${NGINX_VERSION}/objs/*.so /etc/nginx/modules/
# COPY --from=builder /usr/src/nginx-1.29.0/objs/*.so /etc/nginx/modules/
COPY --from=builder /usr/local/modsecurity/lib/* /usr/lib/

# 环境变量指定动态库搜索路径
ENV LD_LIBRARY_PATH=/usr/local/modsecurity/lib

# 创建配置目录并下载必要文件
# RUN mkdir -p /etc/nginx/modsec/plugins \
#     && wget https://github.com/coreruleset/coreruleset/archive/v${CORERULESET_VERSION}.tar.gz \
#     && tar -xzf v${CORERULESET_VERSION}.tar.gz --strip-components=1 -C /etc/nginx/modsec \
#     && rm -f v${CORERULESET_VERSION}.tar.gz \
#     && wget -P /etc/nginx/modsec/plugins https://raw.githubusercontent.com/coreruleset/wordpress-rule-exclusions-plugin/master/plugins/wordpress-rule-exclusions-before.conf \
#     && wget -P /etc/nginx/modsec/plugins https://raw.githubusercontent.com/coreruleset/wordpress-rule-exclusions-plugin/master/plugins/wordpress-rule-exclusions-config.conf \
#     && wget -P /etc/nginx/modsec/plugins https://raw.githubusercontent.com/kejilion/nginx/main/waf/ldnmp-before.conf \
#     && cp /etc/nginx/modsec/crs-setup.conf.example /etc/nginx/modsec/crs-setup.conf \
#     && echo 'SecAction "id:900110, phase:1, pass, setvar:tx.inbound_anomaly_score_threshold=30, setvar:tx.outbound_anomaly_score_threshold=16"' >> /etc/nginx/modsec/crs-setup.conf \
#     && wget https://raw.githubusercontent.com/owasp-modsecurity/ModSecurity/v3/master/modsecurity.conf-recommended -O /etc/nginx/modsec/modsecurity.conf \
#     && sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /etc/nginx/modsec/modsecurity.conf \
#     && sed -i 's/SecPcreMatchLimit [0-9]\+/SecPcreMatchLimit 20000/' /etc/nginx/modsec/modsecurity.conf \
#     && sed -i 's/SecPcreMatchLimitRecursion [0-9]\+/SecPcreMatchLimitRecursion 20000/' /etc/nginx/modsec/modsecurity.conf \
#     && sed -i 's/^SecRequestBodyLimit\s\+[0-9]\+/SecRequestBodyLimit 52428800/' /etc/nginx/modsec/modsecurity.conf \
#     && sed -i 's/^SecRequestBodyNoFilesLimit\s\+[0-9]\+/SecRequestBodyNoFilesLimit 524288/' /etc/nginx/modsec/modsecurity.conf \
#     && sed -i 's/^SecAuditEngine RelevantOnly/SecAuditEngine Off/' /etc/nginx/modsec/modsecurity.conf \
#     && echo 'Include /etc/nginx/modsec/crs-setup.conf' >> /etc/nginx/modsec/modsecurity.conf \
#     && echo 'Include /etc/nginx/modsec/plugins/*-config.conf' >> /etc/nginx/modsec/modsecurity.conf \
#     && echo 'Include /etc/nginx/modsec/plugins/*-before.conf' >> /etc/nginx/modsec/modsecurity.conf \
#     && echo 'Include /etc/nginx/modsec/rules/*.conf' >> /etc/nginx/modsec/modsecurity.conf \
#     && echo 'Include /etc/nginx/modsec/plugins/*-after.conf' >> /etc/nginx/modsec/modsecurity.conf \
#     && apk add --no-cache lua5.1 lua5.1-dev pcre pcre-dev yajl yajl-dev \
#     && ldconfig /usr/lib \
#     && wget https://raw.githubusercontent.com/owasp-modsecurity/ModSecurity/v3/master/unicode.mapping -O /etc/nginx/modsec/unicode.mapping \
#     && rm -rf /var/cache/apk/*

EXPOSE 80 443
WORKDIR /etc/nginx
CMD ["./sbin/nginx", "-g", "daemon off;"]
