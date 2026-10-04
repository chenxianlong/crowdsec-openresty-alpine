#!/bin/sh
# install-bouncer.sh — Install OpenResty and the CrowdSec nginx bouncer (native Lua module).
#
# Env:
#   SERVER_NAME   value to use for nginx server_name (default: localhost)
#   BOUNCER_VER   cs-nginx-bouncer version (default: v1.2.3)
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

SERVER_NAME=${SERVER_NAME:-localhost}
BOUNCER_VER=${BOUNCER_VER:-v1.2.3}
DEST=/opt/crowdsec

echo "==> Removing stock nginx if present (OpenResty conflicts with it)"
if apk info -e nginx >/dev/null 2>&1; then
  rc-service nginx stop 2>/dev/null || true
  rc-update del nginx default 2>/dev/null || true
  # shellcheck disable=SC2046
  apk del $(apk list -I 2>/dev/null | grep -oE '^nginx[a-z0-9-]*-[0-9][^ ]*' | sed 's/-[0-9].*//' | sort -u) 2>/dev/null || true
fi

echo "==> Installing OpenResty"
apk add --no-cache openresty openresty-openrc lua-resty-http
rc-update add openresty default

echo "==> OpenResty runtime temp dirs"
mkdir -p /var/tmp/nginx/client_body /var/tmp/nginx/proxy /var/tmp/nginx/fastcgi /var/tmp/nginx/uwsgi /var/tmp/nginx/scgi
chown -R nginx:nginx /var/tmp/nginx

echo "==> Deploying nginx configuration (server_name=$SERVER_NAME)"
mkdir -p /etc/nginx/http.d /etc/nginx/modules /etc/nginx/ssl
install -m 644 "$REPO_ROOT/configs/openresty/nginx.conf"              /etc/nginx/nginx.conf
install -m 644 "$REPO_ROOT/configs/openresty/00-dynamic-modules.conf" /etc/nginx/modules/00-dynamic-modules.conf
install -m 644 "$REPO_ROOT/configs/openresty/05-crowdsec-lua.conf"    /etc/nginx/http.d/05-crowdsec-lua.conf
install -m 644 "$REPO_ROOT/configs/openresty/10-https.conf"           /etc/nginx/http.d/10-https.conf
install -m 644 "$REPO_ROOT/configs/openresty/20-app.conf"             /etc/nginx/http.d/20-app.conf
install -m 644 "$REPO_ROOT/configs/openresty/default.conf"            /etc/nginx/http.d/default.conf

if [ "$SERVER_NAME" != "10.20.207.6" ]; then
  sed -i "s/10\.20\.207\.6/$SERVER_NAME/g" /etc/nginx/http.d/10-https.conf /etc/nginx/http.d/20-app.conf
fi

if [ ! -f /etc/nginx/ssl/selfsigned.crt ]; then
  echo "==> Generating a self-signed certificate"
  openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
    -keyout /etc/nginx/ssl/selfsigned.key \
    -out    /etc/nginx/ssl/selfsigned.crt \
    -subj "/C=CN/O=CrowdSec/CN=$SERVER_NAME" \
    -addext "subjectAltName=DNS:$SERVER_NAME,IP:127.0.0.1"
  chmod 600 /etc/nginx/ssl/selfsigned.key
fi

echo "==> Fetching cs-nginx-bouncer $BOUNCER_VER"
TMP=$(mktemp -d)
curl -fsSL -o "$TMP/b.tgz" \
  "https://github.com/crowdsecurity/cs-nginx-bouncer/releases/download/$BOUNCER_VER/crowdsec-nginx-bouncer.tgz"
tar xzf "$TMP/b.tgz" -C "$TMP"
SRC="$TMP/crowdsec-nginx-bouncer-$BOUNCER_VER"

mkdir -p /usr/local/lua/crowdsec /var/lib/crowdsec/lua/templates /etc/crowdsec/bouncers
cp -r "$SRC/lua-mod/lib/."       /usr/local/lua/crowdsec/
cp -r "$SRC/lua-mod/templates/." /var/lib/crowdsec/lua/templates/
rm -rf "$TMP"

echo "==> Writing the bouncer configuration"
KEY=$(grep '^CROWDSEC_NGINX_BOUNCER_KEY=' "$DEST/.env" 2>/dev/null | cut -d= -f2 || true)
if [ -z "${KEY:-}" ]; then
  echo "!! $DEST/.env missing — run scripts/deploy-crowdsec.sh first, or set API_KEY manually." >&2
  KEY="<BOUNCER_API_KEY>"
fi
install -m 600 "$REPO_ROOT/configs/bouncers/crowdsec-nginx-bouncer.conf.example" \
  /etc/crowdsec/bouncers/crowdsec-nginx-bouncer.conf
sed -i "s|<BOUNCER_API_KEY>|$KEY|" /etc/crowdsec/bouncers/crowdsec-nginx-bouncer.conf

echo "==> Validating and starting OpenResty"
nginx -t
rc-service openresty restart

echo "==> Done. Check: grep Crowdsec /var/log/nginx/error.log"
