FROM alpine:3.23

COPY conf/mariadb-server.cnf /etc/my.cnf.d/mariadb-server.cnf
COPY tools/init.sh tools/init.sh

RUN apk update && apk upgrade && apk add --no-cache\
    mariadb \
    mariadb-client \
    vim && \
    chmod +x tools/init.sh
    
EXPOSE 3306

ENTRYPOINT ["tools/init.sh"]