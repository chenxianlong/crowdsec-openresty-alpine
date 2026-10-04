#!/usr/bin/env bash
# ci-validate-nginx.sh — Syntax-validate the nginx/OpenResty configuration on a
# Debian/Ubuntu machine (used by CI). This is NOT part of the Alpine deployment.
#
# It stubs the CrowdSec Lua module so that `nginx -t` can load the config without
# the real bouncer / LAPI. It validates nginx syntax, not bouncer behaviour.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)

echo "==> Installing nginx + lua module"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq nginx libnginx-mod-http-lua ca-certificates >/dev/null
apt-get install -y -qq lua-resty-core lua-cjson >/dev/null 2>&1 || true

echo "==> Creating the nginx user"
id nginx >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin nginx

echo "==> Stubbing the CrowdSec Lua module"
mkdir -p /usr/local/lua/crowdsec
cat > /usr/local/lua/crowdsec/crowdsec.lua <<'LUA'
-- CI stub: lets `nginx -t` load access_by_lua_block without the real bouncer.
local M = {}
function M.init() return true end
function M.Allow() end
function M.get_mode() return "live" end
function M.SetupStream() end
function M.SetupMetrics() end
return M
LUA

echo "==> Preparing dirs, bouncer config and a throwaway certificate"
mkdir -p /etc/crowdsec/bouncers /etc/nginx/ssl /etc/nginx/http.d /etc/nginx/modules /var/log/nginx
cp "$REPO_ROOT/configs/bouncers/crowdsec-nginx-bouncer.conf.example" \
   /etc/crowdsec/bouncers/crowdsec-nginx-bouncer.conf
openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
  -keyout /etc/nginx/ssl/selfsigned.key -out /etc/nginx/ssl/selfsigned.crt \
  -subj '/CN=ci' >/dev/null 2>&1

# The distro-specific dynamic-module loader is skipped; load only the lua module.
echo 'load_module /usr/lib/nginx/modules/ngx_http_lua_module.so;' > /etc/nginx/modules/00-lua.conf

echo "==> Deploying configs"
cp "$REPO_ROOT/configs/openresty/nginx.conf"            /etc/nginx/nginx.conf
cp "$REPO_ROOT/configs/openresty/05-crowdsec-lua.conf"  /etc/nginx/http.d/
cp "$REPO_ROOT/configs/openresty/10-https.conf"         /etc/nginx/http.d/
cp "$REPO_ROOT/configs/openresty/20-app.conf"           /etc/nginx/http.d/
cp "$REPO_ROOT/configs/openresty/default.conf"          /etc/nginx/http.d/

echo "==> nginx -t"
nginx -t
echo "nginx config OK"
