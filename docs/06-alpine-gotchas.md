# Alpine / OpenResty gotchas

CrowdSec and the Nginx bouncer are documented primarily for Debian/Ubuntu. These are the Alpine-specific traps we hit while building this, and how each is solved here.

## 1. There is no Alpine package for the Security Engine

CrowdSec only ships `.deb`/`.rpm` and doesn't list Alpine as a supported platform. **Run the engine as the official Docker image** — it is distro-agnostic and upgrades with `docker compose pull`.

## 2. `nginx-extras` doesn't exist

Alpine splits Nginx extras into per-module packages (`nginx-mod-http-geoip`, …), plus a separate OpenResty build. OpenResty already compiles many extras in (`lua`, `echo`, `headers-more`, `set-misc`, `ndk`, …).

## 3. OpenResty uses a broken relative module prefix

OpenResty is built with `--prefix=/usr/lib/nginx/nginx`, so:

```nginx
load_module "modules/ngx_http_geoip_module.so";   # ✗ resolves to /usr/lib/nginx/nginx/modules/...
```

Use absolute paths:

```nginx
load_module /usr/lib/nginx/modules/ngx_http_geoip_module.so;
```

The bundled dynamic modules (shipped in the `openresty` package) are:
`ngx_http_geoip_module`, `ngx_http_image_filter_module`, `ngx_http_perl_module`, `ngx_http_xslt_filter_module`, `ngx_mail_module`, `ngx_stream_geoip_module`. See `configs/openresty/00-dynamic-modules.conf`.

## 4. Lua is static in OpenResty — don't install the dynamic module

`nginx -V` shows `--add-module=../ngx_lua-...`: ngx_lua is compiled **into** the binary. The Alpine `openresty-mod-http-lua` package ships a *dynamic* `ngx_http_lua_module.so` whose `load_module` then fails (bad prefix or "already loaded"). **Do not install it** — just use OpenResty's built-in Lua directives.

## 5. `conf.d/` is the *main* context on Alpine

Alpine's `nginx.conf` includes:

```
include /etc/nginx/conf.d/*.conf;   # main context
include /etc/nginx/http.d/*.conf;   # http context
```

The upstream bouncer `install.sh` drops its config into `conf.d/`, which fails on Alpine with `"lua_package_path" directive is not allowed here`. Put the bouncer config in **`http.d/`**.

## 6. `lua-resty-string` conflicts with OpenResty

`apk add lua-resty-string` pulls `openresty` and conflicts with `nginx`. With OpenResty installed, `resty.string` is already in its lualib (`/usr/lib/nginx/lualib/resty/string.lua`). If you must stay on stock nginx, drop the pure-Lua `resty/string.lua` into `/usr/share/lua/common/resty/` by hand.

## 7. `sed` `\t` is literal on busybox

`sed 'c\\tresolver ...'` on busybox produces `tresolver ...`. Avoid `\t` in `sed` replacements (or fix it up with a second `sed`).

## 8. YAML `#` comments truncate hook filters

```yaml
filter: any(evt.Appsec.MatchedRules, #.name startsWith "crowdsecurity/generic-")
# YAML sees "#.name ..." as a comment  →  compile error
```

Use a block scalar:

```yaml
filter: |
  any(evt.Appsec.MatchedRules, #.name startsWith "crowdsecurity/generic-")
```

## 9. Docker Hub is unreachable from mainland China

Configure a registry mirror in `/etc/docker/daemon.json` (`docker.m.daocloud.io`, `docker.1ms.run`, …). CrowdSec *hub* downloads (collections/rules) use a different endpoint and generally work.

## 10. OpenResty needs its temp paths to exist

It is compiled with `--http-*-temp-path=/var/tmp/nginx/*`. Create the directories and own them by the `nginx` user, otherwise startup fails with `mkdir() ... failed`.

## 11. Google reCAPTCHA is unusable from mainland China

`www.google.com` is unreachable, so both the widget and server-side verification fail. Use **Cloudflare Turnstile** (or hCaptcha) instead.

---

**TL;DR** — on Alpine, prefer **OpenResty** over stock nginx for the bouncer: Lua is static, `resty.*` libraries are bundled, and the only real adaptations are absolute `load_module` paths and putting configs in `http.d/` instead of `conf.d/`.
