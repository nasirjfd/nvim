#!/bin/sh
# clone digiexpress_1 / digiexpress_log_1 (structure + the 2 seed rows) into thread databases N
for n in "$@"; do
  for base in digiexpress digiexpress_log; do
    mysql -uroot -p"${MYSQL_ROOT_PASSWORD:-root}" -e "CREATE DATABASE IF NOT EXISTS ${base}_$n" 2>/dev/null
    mysqldump -uroot -p"${MYSQL_ROOT_PASSWORD:-root}" ${base}_1 2>/dev/null | mysql -uroot -p"${MYSQL_ROOT_PASSWORD:-root}" ${base}_$n 2>/dev/null
  done
done
mysql -uroot -p"${MYSQL_ROOT_PASSWORD:-root}" -N -e "select table_schema, count(*) from information_schema.tables where table_schema regexp '^digiexpress(_log)?_[0-9]+$' group by table_schema order by table_schema" 2>/dev/null
