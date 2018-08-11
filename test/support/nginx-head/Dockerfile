FROM ubuntu:latest
LABEL maintainer="Kenichi Nakamura <kenichi.nakamura@gmail.com>"

RUN apt update && \
    apt install -y build-essential libpcre3 libpcre3-dev zlib1g-dev curl git
    
WORKDIR /usr/local/src
RUN curl -O https://www.openssl.org/source/openssl-1.0.2o.tar.gz && \
    git clone https://github.com/nginx/nginx.git && \
    tar xf openssl-1.0.2o.tar.gz

RUN cd nginx && \
    auto/configure --with-http_v2_module \
                --with-http_ssl_module \
                --with-openssl=../openssl-1.0.2o && \
    make install

COPY nginx.conf /usr/local/nginx/conf/nginx.conf

RUN touch /usr/local/nginx/logs/access.log && \
    ln -sf /dev/stdout /usr/local/nginx/logs/access.log && \
    touch /usr/local/nginx/logs/error.log && \
    ln -sf /dev/stderr /usr/local/nginx/logs/error.log

WORKDIR /usr/local/nginx
EXPOSE 443
CMD ["/usr/local/nginx/sbin/nginx", "-g", "daemon off;"]
