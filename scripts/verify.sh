#!/bin/sh
# verify.sh — Health-check the whole stack.
set -eu

pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; }

echo "== OpenResty =="
nginx -t 2>/dev/null && pass "nginx -t" || fail "nginx -t"
nginx -v 2>&1 | sed 's/^/  /'
rc-service openresty status 2>&1 | sed 's/^/  /' || true
grep -i '\[Crowdsec\] Initialisation done' /var/log/nginx/error.log >/dev/null 2>&1 \
  && pass "bouncer initialised" || fail "bouncer init line not found in error.log"

echo "== Ports =="
netstat -ltn 2>/dev/null | grep -E ':80 |:443 |:8080 |:7422 ' | sed 's/^/  /' || true

echo "== Docker / Engine =="
docker ps --format '  {{.Names}}  {{.Status}}  {{.Ports}}'
curl -fsS -o /dev/null http://127.0.0.1:8080/health && pass "LAPI /health" || fail "LAPI /health"
docker exec crowdsec cscli bouncers list 2>/dev/null | sed 's/^/  /' || true

echo "== HTTP =="
printf '  GET /          -> '; curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/
printf '  GET / (https)  -> '; curl -sk -o /dev/null -w '%{http_code}\n' https://127.0.0.1/

if [ -n "${APPSEC_URL:-x}" ]; then
  echo "== WAF =="
  printf '  GET /.env (vpatch -> ban)     -> '; curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/.env
  printf '  GET generic SSTI (-> captcha) -> '; \
    curl -s -o /dev/null -w '%{http_code}\n' 'http://127.0.0.1/?x=freemarker.template.utility.execute'
  docker exec crowdsec cscli metrics show appsec 2>/dev/null | tail -12 | sed 's/^/  /' || true
fi

echo "== Ban test =="
docker exec crowdsec cscli decisions add --ip 127.0.0.1 --duration 1m --reason verify >/dev/null 2>&1 || true
sleep 1
printf '  banned GET / -> '; curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/
docker exec crowdsec cscli decisions delete --ip 127.0.0.1 >/dev/null 2>&1 || true
sleep 1
printf '  unban  GET / -> '; curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/

echo "Done."
