#!/bin/sh
# enable-waf.sh — Enable the AppSec (WAF) component with the hybrid remediation strategy.
#
# - installs appsec-virtual-patching + appsec-generic-rules
# - adds the AppSec acquisition and publishes 127.0.0.1:7422
# - installs the hybrid appsec config into the engine container
# - points the bouncer at AppSec
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
DEST=/opt/crowdsec

echo "==> Installing AppSec collections"
docker exec crowdsec cscli collections install \
  crowdsecurity/appsec-virtual-patching \
  crowdsecurity/appsec-generic-rules

echo "==> Adding the AppSec acquisition"
cp "$REPO_ROOT/configs/acquis.d/appsec.yaml" "$DEST/acquis.d/appsec.yaml"

echo "==> Ensuring 127.0.0.1:7422 is published"
if ! grep -q '7422:7422' "$DEST/docker-compose.yml"; then
  sed -i 's|\(- "127.0.0.1:8080:8080"\)|\1\n      - "127.0.0.1:7422:7422"|' "$DEST/docker-compose.yml"
fi

echo "==> Applying and restarting the engine"
cd "$DEST"
docker compose up -d
sleep 12

echo "==> Installing the hybrid AppSec config"
docker cp "$REPO_ROOT/configs/appsec/appsec-hybrid.yaml" \
  crowdsec:/etc/crowdsec/appsec-configs/appsec-hybrid.yaml
docker restart crowdsec
sleep 12

echo "==> Pointing the bouncer at AppSec"
CONF=/etc/crowdsec/bouncers/crowdsec-nginx-bouncer.conf
sed -i 's|^APPSEC_URL=.*|APPSEC_URL=http://127.0.0.1:7422|' "$CONF"
rc-service openresty restart

echo "==> Verifying"
sleep 2
printf 'GET /     -> '; curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/
printf 'GET /.env -> '; curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/.env
docker exec crowdsec cscli metrics show appsec 2>/dev/null | tail -12 || true
