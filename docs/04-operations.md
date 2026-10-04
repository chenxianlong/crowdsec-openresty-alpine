# Operations

## Service management

```sh
rc-service openresty status|start|stop|restart|reload
nginx -t && nginx -s reload          # validate + graceful reload

rc-service docker status
docker compose -f /opt/crowdsec/docker-compose.yml ps
docker compose -f /opt/crowdsec/docker-compose.yml logs -f --tail=100
```

Both `docker` and `openresty` are in the `default` runlevel (auto-start on boot).

## CrowdSec CLI (via the container)

```sh
docker exec crowdsec cscli version
docker exec crowdsec cscli decisions list           # active bans/captchas
docker exec crowdsec cscli alerts list              # triggered alerts
docker exec crowdsec cscli metrics                  # parsers/scenarios
docker exec crowdsec cscli metrics show appsec      # WAF metrics
docker exec crowdsec cscli bouncers list            # registered bouncers
docker exec crowdsec cscli collections list
docker exec crowdsec cscli appsec-configs list
docker exec crowdsec cscli appsec-rules list
```

Helper wrapper you can drop in your shell:

```sh
cs() { docker exec crowdsec cscli "$@"; }
cs decisions list
```

## Manual decisions

```sh
docker exec crowdsec cscli decisions add --ip 1.2.3.4 --type ban     --duration 24h
docker exec crowdsec cscli decisions add --ip 1.2.3.4 --type captcha --duration 1h
docker exec crowdsec cscli decisions delete --ip 1.2.3.4
docker exec crowdsec cscli decisions list -o json
```

## Add another protected vhost

1. Copy `configs/openresty/20-app.conf` to `/etc/nginx/http.d/30-other.conf`.
2. Change `server_name` and the `upstream`/`proxy_pass` port.
3. `nginx -t && nginx -s reload`.

The bouncer (`access_by_lua_block`) and the WAF apply **globally** (they are declared in the `http` context), so a new vhost is protected automatically.

## Add another log source

Add a file under `/opt/crowdsec/acquis.d/` (mounted read-only into the container) and restart the engine:

```yaml
filenames:
  - /var/log/other/access.log
labels:
  type: nginx
```

```sh
docker restart crowdsec
```

Make sure the corresponding collection is installed: `cscli collections install crowdsecurity/<name>`.

## Whitelists (reduce false positives)

`/etc/crowdsec/parsers/s02-enrich/mywhitelists.yaml` (create it in the container, or mount one):

```yaml
name: my/whitelists
description: "My whitelist"
whitelist:
  reason: "my internal network"
  ip:
    - "10.0.0.0/8"
    - "172.16.0.0/12"
    - "192.168.0.0/16"
```

## Upgrade

```sh
# Engine
cd /opt/crowdsec && docker compose pull && docker compose up -d

# Rule collections
docker exec crowdsec cscli hub update
docker exec crowdsec cscli collections upgrade

# OpenResty
apk upgrade openresty
rc-service openresty restart
```

> After an OpenResty upgrade, re-check `configs/openresty/00-dynamic-modules.conf` (absolute module paths) and that `lua-resty-http` is still installed.

## Backup

```sh
# Config + decisions database live in named volumes
docker run --rm -v crowdsec_crowdsec-config:/c -v "$PWD":/b alpine \
  tar czf /b/crowdsec-config.tgz -C /c .
docker run --rm -v crowdsec_crowdsec-db:/d -v "$PWD":/b alpine \
  tar czf /b/crowdsec-db.tgz -C /d .
tar czf nginx-conf.tgz /etc/nginx /etc/crowdsec/bouncers
```

## Monitoring

- CrowdSec exposes Prometheus metrics: `GET http://127.0.0.1:6060/metrics`.
- `cscli metrics show appsec` for WAF processed/blocked counts.
- nginx logs: `/var/log/nginx/{access,error}.log` (also parsed by the engine).

## Tuning

| Knob | File | Effect |
|---|---|---|
| `MODE=live|stream` | bouncer conf | `live` queries LAPI per request; `stream` caches decisions and syncs periodically (better for high traffic). |
| `CACHE_EXPIRATION` | bouncer conf | seconds a decision is cached. |
| `CAPTCHA_EXPIRATION` | bouncer conf | seconds a solved CAPTCHA is trusted. |
| `UPDATE_FREQUENCY` | bouncer conf | stream-mode sync interval. |
| huge request bodies | `nginx.conf` | `client_max_body_size` + AppSec `request_body_in_memory_limit`. |
| AppSec on HTTP/2 bodies | bouncer conf | set `APPSEC_DROP_UNREADABLE_BODY=true` to avoid WAF bypass via chunked/H2 bodies. |
