#!/bin/bash
# =============================================================================
# RT 4.4.4 → 6.0.2 Migration Script for sven.dc3.crunchtools.com
# Run as root on sven. This script:
#   1. Backs up config and database
#   2. Updates config files (RT_SiteConfig.pm, Apache vhost, systemd unit)
#   3. Renames data directories
#   4. Does NOT start the new container or run the DB upgrade
# =============================================================================
set -euo pipefail

CONFIG_DIR="/srv/rt.fatherlinux.com/config"
DATA_DIR="/srv/rt.fatherlinux.com/data"

echo "=== RT 4.4.4 → 6.0.2 Migration ==="
echo ""

# --- Pre-flight checks ---
if [ ! -d "$CONFIG_DIR" ]; then
    echo "ERROR: Config directory $CONFIG_DIR not found. Are you on sven?"
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Run as root"
    exit 1
fi

# --- Step 1: Backups ---
echo "--- Step 1: Creating backups ---"

echo "  Backing up config..."
cp -a "$CONFIG_DIR" "$CONFIG_DIR.pre-rt6-backup"
echo "  Done: $CONFIG_DIR.pre-rt6-backup"

echo "  Backing up MariaDB data..."
cp -a "$DATA_DIR/mariadb" "$DATA_DIR/mariadb.pre-rt6-backup"
echo "  Done: $DATA_DIR/mariadb.pre-rt6-backup"

# --- Step 2: Update RT_SiteConfig.pm ---
echo ""
echo "--- Step 2: Updating RT_SiteConfig.pm ---"

sed -i "s/Set( \$DatabaseType, 'mysql' );/Set( \$DatabaseType, 'MariaDB' );/" \
    "$CONFIG_DIR/RT_SiteConfig.pm"
echo "  DatabaseType: mysql → MariaDB"

# --- Step 3: Update Apache vhost ---
echo ""
echo "--- Step 3: Updating rt.fatherlinux.com.conf ---"

sed -i 's|/opt/rt4/sbin/rt-server.fcgi/|/opt/rt6/sbin/rt-server.fcgi/|' \
    "$CONFIG_DIR/rt.fatherlinux.com.conf"
echo "  ScriptAlias: /opt/rt4 → /opt/rt6"

sed -i 's|DocumentRoot "/opt/rt4/share/html"|DocumentRoot "/opt/rt6/share/html"|' \
    "$CONFIG_DIR/rt.fatherlinux.com.conf"
echo "  DocumentRoot: /opt/rt4 → /opt/rt6"

# --- Step 4: Update systemd service unit ---
echo ""
echo "--- Step 4: Updating rt.fatherlinux.com.service ---"

sed -i 's|:/opt/rt4/etc/RT_SiteConfig.pm|:/opt/rt6/etc/RT_SiteConfig.pm|' \
    "$CONFIG_DIR/rt.fatherlinux.com.service"
echo "  RT_SiteConfig mount: /opt/rt4 → /opt/rt6"

sed -i 's|data/logs/rt4:/opt/rt4/var|data/logs/rt6:/opt/rt6/var|' \
    "$CONFIG_DIR/rt.fatherlinux.com.service"
echo "  Logs mount: rt4 → rt6"

# --- Step 5: Rename data directory ---
echo ""
echo "--- Step 5: Renaming data directory ---"

if [ -d "$DATA_DIR/logs/rt4" ]; then
    mv "$DATA_DIR/logs/rt4" "$DATA_DIR/logs/rt6"
    echo "  Renamed: logs/rt4 → logs/rt6"
elif [ -d "$DATA_DIR/logs/rt6" ]; then
    echo "  Already renamed: logs/rt6 exists"
else
    mkdir -p "$DATA_DIR/logs/rt6"
    echo "  Created: logs/rt6 (rt4 dir did not exist)"
fi

echo ""
echo "=== Migration complete ==="
echo ""
echo "Next steps (manual):"
echo "  1. Stop the old container:  systemctl stop rt.fatherlinux.com"
echo "  2. Start the new container: systemctl start rt.fatherlinux.com"
echo "  3. Run the database upgrade:"
echo "     podman exec -it rt.fatherlinux.com \\"
echo "       /opt/rt6/sbin/rt-setup-database --action upgrade --dba root --dba-password ''"
echo "  4. Verify RT loads: curl -sI https://rt.fatherlinux.com/"
