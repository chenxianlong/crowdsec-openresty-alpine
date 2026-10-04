# Installation

Everything below assumes **Alpine Linux** and **root** (or `doas`/`sudo`). Adapt paths if you use another distro with OpenResty.

> The `scripts/*.sh` in this repo automate every step. The commands are shown here so you can run them by hand or understand what the scripts do.

---

## 1. Docker + registry mirror

```sh
apk add --no-cache docker docker-cli-compose
rc-update add docker default
rc-service docker start
```

Mainland-China hosts usually cannot reach Docker Hub directly. Configure a mirror:

```sh
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": ["https://docker.m.daocloud.io", "https://docker.1ms.run"],
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
rc-service docker restart
docker info | grep -A3 'Registry Mirrors'
```

## 2. CrowdSec engine (Docker)

Create `/opt/crowdsec`:

```sh
mkdir -p /opt/crowdsec/acquis.d
cd /opt/crowdsec
cp ~/crowdsec-openresty-alpine/configs/docker/docker-compose.yml .
cp ~/crowdsec-openresty-alpine/configs/acquis.d/nginx.yaml acquis.d/
```

Generate the bouncer API key that the engine will register at first boot:

```sh
KEY=$(openssl rand -hex 16)
umask 077
printf 'CROWDSEC_NGINX_BOUNCER_KEY=%s\n' "$KEY" > .env
chmod 600 .env
```

Start it:

```sh
docker compose up -d
docker compose logs -f --tail=50      # wait for "Local API is ready"
docker exec crowdsec cscli bouncers list
```

The compose file publishes `127.0.0.1:8080` (LAPI) and `127.0.0.1:7422` (AppSec, added later) — **never** `0.0.0.0`.

Install a collection for the log source:

```sh
docker exec crowdsec cscli collections install crowdsecurity/nginx
```

## 3. OpenResty

> Alpine's `openresty` conflicts with `nginx`; remove nginx and its modules first if present.

```sh
# if migrating from nginx:
rc-service nginx stop || true
rc-update del nginx default || true
apk del nginx nginx-openrc nginx-mod-* 2>/dev/null || true

apk add --no-cache openresty openresty-openrc lua-resty-http
rc-update add openresty default
```

OpenResty's compiled **prefix is `/usr/lib/nginx/nginx`**, so the usual relative `load_module "modules/x.so"` does **not** resolve — see [06-alpine-gotchas.md](06-alpine-gotchas.md).

Create the runtime temp dirs OpenResty expects:

```sh
mkdir -p /var/tmp/nginx/{client_body,proxy,fastcgi,uwsgi,scgi}
chown -R nginx:nginx /var/tmp/nginx
```

### Deploy the nginx configs

From this repo:

```sh
cp configs/openresty/nginx.conf                 /etc/nginx/nginx.conf
mkdir -p /etc/nginx/http.d /etc/nginx/modules
cp configs/openresty/00-dynamic-modules.conf    /etc/nginx/modules/
cp configs/openresty/05-crowdsec-lua.conf       /etc/nginx/http.d/
cp configs/openresty/10-https.conf              /etc/nginx/http.d/
cp configs/openresty/20-app.conf                /etc/nginx/http.d/
cp configs/openresty/default.conf               /etc/nginx/http.d/
```

Notes:

- `nginx.conf` includes `/etc/nginx/modules/*.conf` (main context) and `/etc/nginx/http.d/*.conf` (http context). On Alpine, `conf.d/` is included in the **main** context, so Lua directives (which need http context) must live in `http.d/`.
- `10-https.conf` expects a self-signed certificate — generate one:

```sh
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
  -keyout /etc/nginx/ssl/selfsigned.key \
  -out    /etc/nginx/ssl/selfsigned.crt \
  -subj '/C=CN/O=CrowdSec/CN=localhost' \
  -addext 'subjectAltName=DNS:localhost,IP:127.0.0.1'
chmod 600 /etc/nginx/ssl/selfsigned.key
```

Adjust `server_name` in `10-https.conf` / `20-app.conf` to your IP or domain.

## 4. The Lua bouncer

```sh
apk add --no-cache lua-resty-http
# OpenResty bundles resty.string / cjson in its lualib, so no manual Lua files are needed.
```

Fetch the bouncer release and lay out its files:

```sh
V=v1.2.3
cd /tmp
curl -fsSLO "https://github.com/crowdsecurity/cs-nginx-bouncer/releases/download/$V/crowdsec-nginx-bouncer.tgz"
tar xzf crowdsec-nginx-bouncer.tgz
D=crowdsec-nginx-bouncer-$V

mkdir -p /usr/local/lua/crowdsec /var/lib/crowdsec/lua/templates /etc/crowdsec/bouncers
cp -r "$D"/lua-mod/lib/.       /usr/local/lua/crowdsec/
cp -r "$D"/lua-mod/templates/. /var/lib/crowdsec/lua/templates/
```

Configure the bouncer (adapt from the example, insert the API key from `/opt/crowdsec/.env`):

```sh
KEY=$(grep '^CROWDSEC_NGINX_BOUNCER_KEY=' /opt/crowdsec/.env | cut -d= -f2)
cp configs/bouncers/crowdsec-nginx-bouncer.conf.example \
   /etc/crowdsec/bouncers/crowdsec-nginx-bouncer.conf
sed -i "s|<BOUNCER_API_KEY>|$KEY|" /etc/crowdsec/bouncers/crowdsec-nginx-bouncer.conf
chmod 600 /etc/crowdsec/bouncers/crowdsec-nginx-bouncer.conf
```

Validate and start:

```sh
nginx -t
rc-service openresty start        # or: rc-service openresty restart
```

`05-crowdsec-lua.conf` sets the Lua search path and calls `cs.init(...)`. A successful start logs:

```
[Crowdsec] Initialisation done
```

## 5. Done — verify

```sh
sh scripts/verify.sh
```

Continue with [03-waf-and-captcha.md](03-waf-and-captcha.md) to enable the WAF.
