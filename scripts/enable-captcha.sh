#!/bin/sh
# enable-captcha.sh — Configure CAPTCHA for the bouncer.
#
# Env:
#   CAPTCHA_PROVIDER  recaptcha | hcaptcha | turnstile   (default: turnstile)
#   SITE_KEY          provider site key                   (default: Turnstile TEST key)
#   SECRET_KEY        provider secret key                 (default: Turnstile TEST key)
#
# Turnstile is recommended for mainland-China clients (Google/reCAPTCHA is unreachable).
set -eu

CAPTCHA_PROVIDER=${CAPTCHA_PROVIDER:-turnstile}
SITE_KEY=${SITE_KEY:-1x00000000000000000000AA}
SECRET_KEY=${SECRET_KEY:-1x0000000000000000000000000000000AA}
CONF=/etc/crowdsec/bouncers/crowdsec-nginx-bouncer.conf
NGINX_CONF=/etc/nginx/nginx.conf

if [ "$SITE_KEY" = "1x00000000000000000000AA" ]; then
  echo "!! Using the Cloudflare Turnstile *test* key (always passes)." >&2
  echo "!! Replace SITE_KEY/SECRET_KEY with real keys for production." >&2
fi

echo "==> Ensuring an nginx resolver is configured (needed to reach the provider)"
if ! grep -qE '^[[:space:]]*resolver[[:space:]]' "$NGINX_CONF"; then
  sed -i 's|.*resolver 1\.1\.1\.1.*|\tresolver 223.5.5.5 119.29.29.29 valid=300s ipv6=off;|' "$NGINX_CONF"
  grep -qE '^[[:space:]]*resolver[[:space:]]' "$NGINX_CONF" || \
    sed -i 's|^\(\s*server_tokens off;\)|resolver 223.5.5.5 119.29.29.29 valid=300s ipv6=off;\n\1|' "$NGINX_CONF"
fi
grep -n 'resolver' "$NGINX_CONF" || true

echo "==> Updating the bouncer config"
sed -i \
  -e "s|^CAPTCHA_PROVIDER=.*|CAPTCHA_PROVIDER=$CAPTCHA_PROVIDER|" \
  -e "s|^SITE_KEY=.*|SITE_KEY=$SITE_KEY|" \
  -e "s|^SECRET_KEY=.*|SECRET_KEY=$SECRET_KEY|" \
  -e "s|^CAPTCHA_TEMPLATE_PATH=.*|CAPTCHA_TEMPLATE_PATH=/var/lib/crowdsec/lua/templates/captcha.html|" \
  -e "s|^CAPTCHA_EXPIRATION=.*|CAPTCHA_EXPIRATION=3600|" \
  "$CONF"

echo "==> Validating and restarting OpenResty"
nginx -t
rc-service openresty restart

echo "==> Test (force a captcha decision for the caller)"
docker exec crowdsec cscli decisions add --ip 127.0.0.1 --type captcha --duration 2m
sleep 1
printf 'GET / -> '; curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/
curl -s http://127.0.0.1/ | grep -o 'CrowdSec Captcha' || echo "   (captcha page not detected)"
docker exec crowdsec cscli decisions delete --ip 127.0.0.1
