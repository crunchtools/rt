#!/bin/bash
# Initialize MariaDB data directory if needed
if [ ! -d /var/lib/mysql/mysql ]; then
    mysql_install_db --user=mysql
fi
