#!/bin/bash
# Test suite for RT 6.0.2 all-in-one container image
# Usage: ./tests/test-image.sh [--static|--runtime|--all] <image:tag>
set -euo pipefail

PASS=0
FAIL=0
MODE="all"
IMAGE=""

# Container runtime: honor env var, otherwise prefer podman
if [ -n "${CONTAINER_RUNTIME:-}" ]; then
    RUNTIME="$CONTAINER_RUNTIME"
elif command -v podman &>/dev/null; then
    RUNTIME="podman"
elif command -v docker &>/dev/null; then
    RUNTIME="docker"
else
    echo "ERROR: Neither podman nor docker found"
    exit 1
fi

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

check() {
    local desc="$1"; shift
    if eval "$@" >/dev/null 2>&1; then
        pass "$desc"
    else
        fail "$desc"
    fi
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --static)  MODE="static";  shift ;;
        --runtime) MODE="runtime"; shift ;;
        --all)     MODE="all";     shift ;;
        *)         IMAGE="$1";     shift ;;
    esac
done

if [[ -z "$IMAGE" ]]; then
    echo "Usage: $0 [--static|--runtime|--all] <image:tag>"
    exit 1
fi

# Helper: run a command inside the image (no systemd, just exec)
run_in() {
    $RUNTIME run --rm --entrypoint /bin/sh "$IMAGE" -c "$*"
}

# =============================================================================
# STATIC TESTS - verify image contents without starting systemd
# =============================================================================
run_static_tests() {
    echo ""
    echo "=== Static Tests ==="

    echo ""
    echo "--- RT Installation ---"
    check "RT base directory exists" \
        run_in test -d /opt/rt6
    check "RT FCGI script exists" \
        run_in test -f /opt/rt6/sbin/rt-server.fcgi
    check "RT setup-database tool exists" \
        run_in test -f /opt/rt6/sbin/rt-setup-database
    check "RT lib directory exists" \
        run_in test -d /opt/rt6/lib
    check "RT web assets exist" \
        run_in test -d /opt/rt6/share/html

    echo ""
    echo "--- Package Installation ---"
    check "httpd is installed" \
        run_in rpm -q httpd
    check "mod_fcgid is installed" \
        run_in rpm -q mod_fcgid
    check "mariadb-server is installed" \
        run_in rpm -q mariadb-server
    check "postfix is installed" \
        run_in rpm -q postfix
    check "perl is installed" \
        run_in rpm -q perl

    echo ""
    echo "--- Configuration Files ---"
    check "RT_SiteConfig.pm exists" \
        run_in test -f /opt/rt6/etc/RT_SiteConfig.pm
    check "RT Apache config exists" \
        run_in test -f /etc/httpd/conf.d/rt.conf
    check "RT_SiteConfig sets database type to mysql" \
        'run_in grep -q "mysql" /opt/rt6/etc/RT_SiteConfig.pm'

    echo ""
    echo "--- Init Scripts ---"
    check "rt-db-prep.sh exists" \
        run_in test -f /usr/local/bin/rt-db-prep.sh
    check "rt-db-prep.sh is executable" \
        run_in test -x /usr/local/bin/rt-db-prep.sh
    check "rt-db-setup.sh exists" \
        run_in test -f /usr/local/bin/rt-db-setup.sh
    check "rt-db-setup.sh is executable" \
        run_in test -x /usr/local/bin/rt-db-setup.sh

    echo ""
    echo "--- Systemd Units ---"
    check "rt-db-prep.service exists" \
        run_in test -f /etc/systemd/system/rt-db-prep.service
    check "rt-db-setup.service exists" \
        run_in test -f /etc/systemd/system/rt-db-setup.service
    check "httpd.service is enabled" \
        'run_in systemctl is-enabled httpd.service'
    check "mariadb.service is enabled" \
        'run_in systemctl is-enabled mariadb.service'
    check "postfix.service is enabled" \
        'run_in systemctl is-enabled postfix.service'
    check "rt-db-prep.service is enabled" \
        'run_in systemctl is-enabled rt-db-prep.service'
    check "rt-db-setup.service is enabled" \
        'run_in systemctl is-enabled rt-db-setup.service'

    echo ""
    echo "--- Systemd Unit Ordering ---"
    check "rt-db-prep runs before mariadb" \
        'run_in grep -q "Before=mariadb.service" /etc/systemd/system/rt-db-prep.service'
    check "rt-db-setup runs after mariadb" \
        'run_in grep -q "After=mariadb.service" /etc/systemd/system/rt-db-setup.service'
    check "rt-db-setup runs before httpd" \
        'run_in grep -q "Before=httpd.service" /etc/systemd/system/rt-db-setup.service'

    echo ""
    echo "--- Apache Config ---"
    check "RT VirtualHost uses port 80" \
        'run_in grep -q "VirtualHost \*:80" /etc/httpd/conf.d/rt.conf'
    check "ScriptAlias points to RT FCGI" \
        'run_in grep -q "rt-server.fcgi" /etc/httpd/conf.d/rt.conf'

    echo ""
    echo "--- Entrypoint ---"
    check "Entrypoint is /sbin/init" \
        '$RUNTIME inspect --format="{{json .Config.Entrypoint}}" "$IMAGE" | grep -q "/sbin/init"'
}

# =============================================================================
# RUNTIME TESTS - start container with systemd, verify services come up
# =============================================================================
run_runtime_tests() {
    echo ""
    echo "=== Runtime Tests ==="

    local CONTAINER_NAME="rt-test-$$"

    echo ""
    echo "--- Starting container with systemd ---"

    # Start the container with systemd
    # --cgroupns=host is required for systemd on cgroupv2 (GHA ubuntu-latest)
    $RUNTIME run -d \
        --name "$CONTAINER_NAME" \
        --privileged \
        --cgroupns=host \
        --tmpfs /tmp \
        -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
        "$IMAGE"

    # Cleanup on exit
    trap "$RUNTIME rm -f $CONTAINER_NAME >/dev/null 2>&1 || true" EXIT

    # Wait for systemd to initialize (up to 30s)
    echo "  Waiting for systemd to boot..."
    local ready=false
    for i in $(seq 1 30); do
        if $RUNTIME exec "$CONTAINER_NAME" systemctl is-system-running --wait 2>/dev/null | grep -qE "running|degraded"; then
            ready=true
            break
        fi
        sleep 1
    done

    if ! $ready; then
        echo "  WARNING: systemd did not reach running state within 30s, continuing with tests..."
    fi

    # Give services a moment to fully start (MariaDB init + RT schema import)
    echo "  Waiting for database initialization (up to 120s)..."
    local db_ready=false
    for i in $(seq 1 120); do
        if $RUNTIME exec "$CONTAINER_NAME" mysql -e "USE rt4" >/dev/null 2>&1; then
            db_ready=true
            break
        fi
        sleep 1
    done

    if ! $db_ready; then
        echo "  WARNING: Database did not come up within 120s"
        echo "  --- Debug: systemctl status ---"
        $RUNTIME exec "$CONTAINER_NAME" systemctl status --no-pager 2>&1 || true
        echo "  --- Debug: journal ---"
        $RUNTIME exec "$CONTAINER_NAME" journalctl --no-pager -n 50 2>&1 || true
    fi

    # Helper for runtime checks
    rexec() {
        $RUNTIME exec "$CONTAINER_NAME" "$@"
    }

    echo ""
    echo "--- MariaDB ---"
    check "MariaDB data directory initialized" \
        rexec test -d /var/lib/mysql/mysql
    check "MariaDB is running" \
        'rexec mysqladmin ping 2>&1 | grep -q alive'
    check "RT database rt4 exists" \
        'rexec mysql -e "USE rt4"'

    echo ""
    echo "--- RT Schema ---"
    # Wait a bit more for schema import if needed
    local schema_ready=false
    for i in $(seq 1 60); do
        if rexec mysql -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='rt4'" 2>/dev/null | grep -qv '^0$'; then
            schema_ready=true
            break
        fi
        sleep 2
    done

    check "RT schema imported (tables exist)" \
        '$schema_ready'
    check "Users table exists" \
        'rexec mysql -e "DESCRIBE rt4.Users" 2>/dev/null'
    check "Tickets table exists" \
        'rexec mysql -e "DESCRIBE rt4.Tickets" 2>/dev/null'
    check "Queues table exists" \
        'rexec mysql -e "DESCRIBE rt4.Queues" 2>/dev/null'
    check "Default root user exists in RT" \
        'rexec mysql -N -e "SELECT Name FROM rt4.Users WHERE Name='"'"'root'"'"'" | grep -q root'

    echo ""
    echo "--- Apache / RT Web ---"
    check "httpd process is running" \
        rexec pgrep -x httpd
    check "httpd.service is active" \
        'rexec systemctl is-active httpd.service'

    # Wait for httpd to serve pages (up to 30s)
    local web_ready=false
    for i in $(seq 1 30); do
        if rexec curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:80/ 2>/dev/null | grep -qE "200|302"; then
            web_ready=true
            break
        fi
        sleep 1
    done

    check "RT web UI responds (HTTP 200 or 302)" \
        '$web_ready'
    check "RT login page contains expected content" \
        'rexec curl -sL http://127.0.0.1:80/ | grep -qi "RT"'

    echo ""
    echo "--- Postfix ---"
    check "postfix.service is active" \
        'rexec systemctl is-active postfix.service'

    # Cleanup
    $RUNTIME rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
    trap - EXIT
}

# =============================================================================
# Main
# =============================================================================
echo "============================================"
echo "RT Container Image Tests"
echo "Image: $IMAGE"
echo "Mode:  $MODE"
echo "============================================"

if [[ "$MODE" == "static" || "$MODE" == "all" ]]; then
    run_static_tests
fi

if [[ "$MODE" == "runtime" || "$MODE" == "all" ]]; then
    run_runtime_tests
fi

echo ""
echo "============================================"
echo "Results: $PASS passed, $FAIL failed"
echo "============================================"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
