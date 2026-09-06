#! /bin/sh

echo "Debut du script"

mkdir -p /run/mariadbd
mkdir -p /var/lib/mariadb

chown -R mysql:mysql /run/mariadbd
chown -R mysql:mysql /var/lib/mariadb

if [ ! -d '/var/lib/mariadb/mysql' ]; then
	mariadb-install-db
	mariadbd --datadir=/var/lib/mariadb &
	until mariadb-admin ping --silent; do
		sleep 1
	done
	MYSQL_PASSWORD=$(cat /run/secrets/db_password)
	MYSQL_ROOT_PASSWORD=$(cat /run/secrets/db_root_password)

	echo "avant bloc sql"
	mariadb <<-EOSQL
		CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE};
		CREATE USER IF NOT EXISTS '${MYSQL_USER}' @'%' IDENTIFIED BY '${MYSQL_PASSWORD}';
		GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'%';
		ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}';
		FLUSH PRIVILEGES;
	EOSQL

	echo "avant shutdown"

	mariadb-admin -u root -p$MYSQL_ROOT_PASSWORD shutdown

	echo "avant exec"
fi
exec mariadbd