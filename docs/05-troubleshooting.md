# Troubleshooting

## OpenResty / nginx won't start

Always validate first — the **error message is at the top** of the output:

```sh
nginx -t
```

Common causes:

| Message | Cause / fix |
|---|---|
| `unknown directive "access_by_lua_block"` | ngx_lua not loaded. On Alpine stock nginx install `nginx-mod-http-lua`; on OpenResty it is **static** (no module needed). |
| `"lua_package_path" directive is not allowed here` | The file is in the **main** context. On Alpine `/etc/nginx/conf.d/` is the main context — put Lua directives in `/etc/nginx/http.d/`. |
| `dlopen() .../modules/ndk_http_module.so failed` | OpenResty relative module path is broken. Use **absolute** paths (`/usr/lib/nginx/modules/x.so`) or remove the dynamic-module conf. |
| `dlopen() .../ngx_http_lua_module.so: already loaded` | lua is compiled **statically** into OpenResty; remove the dynamic lua module package/conf. |
| `mkdir() "/var/tmp/nginx/client_body" failed` | Create the temp dirs: `mkdir -p /var/tmp/nginx/{client_body,proxy,fastcgi,uwsgi,scgi} && chown -R nginx:nginx /var/tmp/nginx`. |

## Bouncer doesn't block

1. Check the CrowdSec init line in `/var/log/nginx/error.log`:
   ```
   [Crowdsec] Initialisation done
   ```
   If absent, initialization failed — the line above it has the reason.

2. Missing Lua libraries are the usual cause:
   ```
   no file '.../resty/string.lua'
   ```
   → install `lua-resty-http`; OpenResty bundles `resty.string`/`cjson`. (On stock nginx, `apk add lua-resty-string` conflicts with OpenResty — install OpenResty or drop in `resty/string.lua`.)

3. Test with a manual decision:
   ```sh
   docker exec crowdsec cscli decisions add --ip 127.0.0.1 --duration 2m
   curl -o /dev/null -w '%{http_code}\n' http://127.0.0.1/    # expect 403
   docker exec crowdsec cscli decisions delete --ip 127.0.0.1
   ```

4. `rc-service openresty restart` after editing the bouncer config (a plain reload may not re-run `init_by_lua`).

## WAF not blocking

```sh
curl -I http://localhost/.env                # expect 403
docker exec crowdsec cscli metrics show appsec
docker exec crowdsec cscli alerts list | tail
```

- No `Appsec Metrics` → AppSec isn't enabled. Check `acquis.d/appsec.yaml` and that the container logs say `Appsec listening on 0.0.0.0:7422`.
- `APPSEC_URL` empty in the bouncer config → enable it and restart.
- AppSec reachable only on loopback: verify from the host:
  ```sh
  curl -o /dev/null -w '%{http_code}\n' http://127.0.0.1:7422/   # 401 = reachable (needs auth headers)
  ```

## Captcha never appears (falls back to 403)

`FALLBACK_REMEDIATION=ban` means a `captcha` decision becomes a ban when the captcha plugin failed to load. Look for:

```
error loading captcha plugin: no <provider> site key provided
```

Fix: set `SITE_KEY` **and** `SECRET_KEY` (the provider must be specified for anything other than recaptcha). Then `rc-service openresty restart`.

If the widget doesn't render in the browser: the client must reach the provider's JS host. reCAPTCHA (Google) is unreachable from mainland China — use **Turnstile** or **hCaptcha**. Also ensure nginx has a working `resolver`.

## Engine exits fatally after adding AppSec config

```
level=fatal msg="... unable to build on_match hook : unable to compile filter any(evt.Appsec.MatchedRules, : unexpected token EOF"
```

The YAML parser ate `#.name ...` as a comment. Wrap the filter in a `|` block scalar (see `appsec-hybrid.yaml`).

## Container can't read nginx logs

CrowdSec runs as a non-root user inside the container. `/var/log/nginx/*.log` must be world-readable (typically `root:root 0644`) or mount with a matching `GID`:

```yaml
    environment:
      GID: "102"     # the group that owns the logs
```

## Look at the right logs

```sh
# nginx side (bouncer, WAF calls)
tail -f /var/log/nginx/error.log

# engine side (acquisition, AppSec, LAPI)
docker compose -f /opt/crowdsec/docker-compose.yml logs -f --tail=100
```
