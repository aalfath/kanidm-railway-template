#!/bin/sh
# Railway start script for Kanidm. See README.md.
set -eu

DATA_DIR=/data
TLS_DIR=/tmp/kanidm-tls
CONFIG="$DATA_DIR/server.toml"

DOMAIN="${KANIDM_DOMAIN:-${RAILWAY_PUBLIC_DOMAIN:-}}"
if [ -z "$DOMAIN" ]; then
  echo "[kanidm] ERROR: KANIDM_DOMAIN is empty. Attach a public domain to this service (Settings > Networking) or set KANIDM_DOMAIN." >&2
  exit 1
fi
ORIGIN="${KANIDM_ORIGIN:-https://$DOMAIN}"
# kanidmd also reads KANIDM_* variables; keep them identical to the file.
export KANIDM_DOMAIN="$DOMAIN" KANIDM_ORIGIN="$ORIGIN"
export PORT="${PORT:-8080}"

mkdir -p "$DATA_DIR" "$DATA_DIR/backups" "$TLS_DIR"

cat > "$CONFIG" <<TOML
# Written by start.sh on every boot. Change settings through Railway variables.
version = "2"
bindaddress = "127.0.0.1:8443"
db_path = "$DATA_DIR/kanidm.db"
tls_chain = "$TLS_DIR/chain.pem"
tls_key = "$TLS_DIR/key.pem"
domain = "$DOMAIN"
origin = "$ORIGIN"
log_level = "${KANIDM_LOG_LEVEL:-info}"

[http_client_address_info]
x-forward-for = ["127.0.0.1"]

[online_backup]
path = "$DATA_DIR/backups/"
schedule = "${KANIDM_BACKUP_SCHEDULE:-00 22 * * *}"
versions = ${KANIDM_BACKUP_VERSIONS:-7}
TOML
chmod 0600 "$CONFIG"

# Self-signed certificate for the loopback hop only (Railway's edge serves
# the public certificate). Regenerated each boot so it never expires.
rm -f "$TLS_DIR"/*.pem
/sbin/kanidmd cert-generate -c "$CONFIG" >/dev/null

echo "[kanidm] domain=$DOMAIN origin=$ORIGIN port=$PORT"

/sbin/kanidmd server -c "$CONFIG" &
KANIDM_PID=$!
caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
CADDY_PID=$!

stop() {
  kill -TERM "$CADDY_PID" "$KANIDM_PID" 2>/dev/null || true
  wait "$KANIDM_PID" 2>/dev/null || true
  exit 0
}
trap stop TERM INT

# First boot: give the two built-in admin accounts random passwords and show
# them once in the deploy logs. Reset them later with
#   railway ssh -- kanidmd recover-account idm_admin
MARKER="$DATA_DIR/.admin-accounts-initialised"
if [ ! -f "$MARKER" ]; then
  i=0
  until wget -q -O /dev/null "http://127.0.0.1:$PORT/status" 2>/dev/null; do
    i=$((i + 1))
    if [ "$i" -gt 120 ] || ! kill -0 "$KANIDM_PID" 2>/dev/null; then
      echo "[kanidm] server did not become ready; skipping admin setup" >&2
      break
    fi
    sleep 1
  done
  if ADMIN_OUT=$(/sbin/kanidmd recover-account admin -c "$CONFIG" 2>&1) &&
     IDM_OUT=$(/sbin/kanidmd recover-account idm_admin -c "$CONFIG" 2>&1); then
    ADMIN_PW=$(printf '%s\n' "$ADMIN_OUT" | sed -n 's/.*new_password: *"\{0,1\}\([^"]*\)"\{0,1\}.*/\1/p' | tail -n 1)
    IDM_PW=$(printf '%s\n' "$IDM_OUT" | sed -n 's/.*new_password: *"\{0,1\}\([^"]*\)"\{0,1\}.*/\1/p' | tail -n 1)
    if [ -n "$ADMIN_PW" ] && [ -n "$IDM_PW" ]; then
      echo "=================================================================="
      echo " Kanidm first boot: initial admin passwords (shown only once)"
      echo "   admin      (server configuration): $ADMIN_PW"
      echo "   idm_admin  (people and groups):    $IDM_PW"
      echo " Log in with the kanidm CLI: kanidm login -H https://$DOMAIN -D idm_admin"
      echo " Reset any time: railway ssh -- kanidmd recover-account idm_admin"
      echo "=================================================================="
      touch "$MARKER"
    else
      echo "[kanidm] could not read the recovered passwords:" >&2
      printf '%s\n%s\n' "$ADMIN_OUT" "$IDM_OUT" | sed 's/new_password.*/new_password: (hidden)/' >&2
    fi
  else
    echo "[kanidm] recover-account failed; run it later with railway ssh" >&2
  fi
fi

# Exit (and let Railway restart us) if either process stops.
while kill -0 "$KANIDM_PID" 2>/dev/null && kill -0 "$CADDY_PID" 2>/dev/null; do
  sleep 5
done
echo "[kanidm] a process exited; stopping" >&2
kill -TERM "$CADDY_PID" "$KANIDM_PID" 2>/dev/null || true
wait "$KANIDM_PID" 2>/dev/null || true
exit 1
