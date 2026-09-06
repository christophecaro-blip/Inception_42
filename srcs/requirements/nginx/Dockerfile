FROM alpine:3.23

COPY conf/nginx.conf /etc/nginx/http.d/default.conf

RUN apk update && apk upgrade && apk add --no-cache \
    vim \
    nginx \
    openssl \
    curl && \
    mkdir -p /etc/nginx/ssl && \
    openssl req -x509 -nodes -out /etc/nginx/ssl/inception.crt -keyout /etc/nginx/ssl/inception.key -subj "/C=FR/ST=IDF/L=Marseille/O=42/OU=42/CN=ccaro.42.fr/UID=ccaro" && \
    mkdir -p /var/run/nginx && \
    mkdir -p /var/www/html && \
    chmod +rwx /var/www/html && \
    chown -R nginx:nginx /var/www/html

EXPOSE 443

ENTRYPOINT ["nginx", "-g", "daemon off;"]