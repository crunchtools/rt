#!/bin/bash
# Skip if RT database already exists
if mysql -e "USE rt4" 2>/dev/null; then
    exit 0
fi
# Initialize RT database
/opt/rt4/sbin/rt-setup-database --action init --dba root --dba-password ''
