#!/bin/sh
# deploy-crowdsec.sh — Deploy the CrowdSec Security Engine (Docker) + log acquisition.
#
# Layout created under /opt/crowdsec:
#   docker-compose.yml
#   .env                      (bouncer API key, chmod 600)
#   acquis.d/nginx.yaml
#   acquis.d/appsec.yaml      (WAF listener; used by enable-waf.sh)
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
DEST=/opt/crowdsec

echo "==> Creating $DEST"
mkdir -p "$DEST/acquis.d"

cp "$REPO_ROOT/configs/docker/docker-compose.yml" "$DEST/docker-compose.yml"
cp "$REPO_ROOT/configs/acquis.d/nginx.yaml"       "$DEST/acquis.d/nginx.yaml"

if [ ! -f "$DEST/.env" ]; then
  echo "==> Generating bouncer API key"
  KEY=$(openssl rand -hex 16)
  umask 077
  printf 'CROWDSEC_NGINX_BOUNCER_KEY=%s\n' "$KEY" > "$DEST/.env"
  chmod 600 "$DEST/.env"
else
  echo "==> $DEST/.env already exists, keeping it"
fi

echo "==> Starting the engine"
cd "$DEST" || exit 1
docker compose up -d

echo "==> Waiting for the Local API (up to ~60s)"
i=0
while [ "$i" -lt 30 ]; do
  if curl -fsS -o /dev/null "http://127.0.0.1:8080/health" 2>/dev/null; then
    echo "    LAPI is up"
    break
  fi
  i=$((i + 1))
  sleep 2
done

echo "==> Installing the nginx collection"
docker exec crowdsec cscli collections install crowdsecurity/nginx || true

echo "==> Bouncers"
docker exec crowdsec cscli bouncers list

cat <<EOF

Engine deployed. Next:
  - Point your app behind OpenResty (configs/openresty/20-app.conf)
  - Run scripts/install-bouncer.sh
EOF
