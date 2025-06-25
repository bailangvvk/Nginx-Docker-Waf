# 安装构建工具
RUN apk add --no-cache \
    build-base \
    curl \
    git \
    zlib-dev \
    pcre-dev \
    linux-headers \
    perl \
    bash

# 下载并编译 Zstandard
RUN wget https://github.com/facebook/zstd/releases/download/v${ZSTD_VERSION}/zstd-${ZSTD_VERSION}.tar.gz \
    && tar -xzf zstd-${ZSTD_VERSION}.tar.gz \
    && cd zstd-${ZSTD_VERSION} \
    && make clean \
    && CFLAGS="-fPIC" make && make install \
    && cd ..

# 克隆 Zstandard NGINX 模块
RUN git clone --depth=10 https://github.com/cloudflare/nginx-zstd.git

# 克隆 Brotli 模块
RUN git clone --recurse-submodules -j8 https://github.com/google/ngx_brotli

# 设置工作目录
WORKDIR /build

# 下载并编译 NGINX
RUN curl -fSL https://nginx.org/download/nginx-${NGINX_VERSION}.tar.gz -o nginx.tar.gz && \
    tar xzf nginx.tar.gz && \
    cd nginx-${NGINX_VERSION} && \
    ./configure \
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
      --with-threads \
      --add-dynamic-module=../nginx-zstd \
      --add-dynamic-module=../ngx_brotli && \
    make -j$(nproc) && \
    make install && \
    strip /usr/local/nginx/sbin/nginx

# 最小运行时镜像
FROM busybox:1.35-uclibc

# 拷贝构建产物
COPY --from=builder /usr/local/nginx /usr/local/nginx

# 暴露端口
EXPOSE 80 443

WORKDIR /usr/local/nginx

# 启动 nginx
CMD ["./sbin/nginx", "-g", "daemon off;"]
