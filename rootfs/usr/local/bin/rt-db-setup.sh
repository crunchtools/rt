#!/bin/bash
# Allow password-less root access via TCP (needed for RT's DBI/MariaDB connection)
# MariaDB defaults to unix_socket auth, but Apache/FCGI runs as 'apache' user
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING '' OR unix_socket" 2>/dev/null
mysql -e "FLUSH PRIVILEGES" 2>/dev/null

# Skip if RT database already has data (already initialized)
if mysql -N -e "SELECT COUNT(*) FROM rt4.Users" 2>/dev/null | grep -qv '^0$'; then
    exit 0
fi
# Create the database if it doesn't exist
mysql -e "CREATE DATABASE IF NOT EXISTS rt4 CHARACTER SET utf8mb4"
# Initialize RT: schema → acl → coredata (root user) → initial data
/opt/rt6/sbin/rt-setup-database --action schema --dba root --dba-password ''
/opt/rt6/sbin/rt-setup-database --action acl --dba root --dba-password ''
/opt/rt6/sbin/rt-setup-database --action coredata --dba root --dba-password ''
/opt/rt6/sbin/rt-setup-database --action insert --datafile /opt/rt6/etc/initialdata --dba root --dba-password ''
