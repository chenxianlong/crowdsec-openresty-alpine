# WAF (AppSec) + CAPTCHA + hybrid remediation

The CrowdSec **AppSec** component turns the engine into a WAF. Every request is forwarded by the bouncer to the AppSec listener; AppSec replies with a remediation the bouncer enforces.

```
bouncer ──► POST http://127.0.0.1:7422/  ──► AppSec engine ──► "ban" | "captcha" | "allow"
```

---

## 1. Enable AppSec

Install the rule collections:

```sh
docker exec crowdsec cscli collections install \
  crowdsecurity/appsec-virtual-patching \
  crowdsecurity/appsec-generic-rules
```

Add the AppSec acquisition. The engine listens on `0.0.0.0:7422` **inside the container**; compose publishes it to `127.0.0.1:7422` on the host.

`/opt/crowdsec/acquis.d/appsec.yaml`:

```yaml
appsec_configs:
  - crowdsecurity/appsec-hybrid   # or crowdsecurity/appsec-default
labels:
  type: appsec
listen_addr: 0.0.0.0:7422
source: appsec
```

Expose the port in `docker-compose.yml`:

```yaml
    ports:
      - "127.0.0.1:8080:8080"
      - "127.0.0.1:7422:7422"
```

Point the bouncer at it. `/etc/crowdsec/bouncers/crowdsec-nginx-bouncer.conf`:

```
APPSEC_URL=http://127.0.0.1:7422
APPSEC_FAILURE_ACTION=passthrough   # allow if AppSec is unreachable (availability first)
```

Apply:

```sh
docker compose -f /opt/crowdsec/docker-compose.yml up -d
rc-service openresty restart
```

Verify:

```sh
curl -I http://localhost/.env        # → 403
docker exec crowdsec cscli metrics show appsec
```

---

## 2. Remediation modes

The AppSec config controls what a match does. `default_remediation` is a **single value per config**; the last loaded config wins when several are merged.

- `ban` → hard block (`blocked_http_code`, default 403).
- `captcha` → the bouncer returns the CAPTCHA page.
- `allow` → disable blocking.

### Hybrid (recommended)

Hard-block known-CVE exploits, challenge broad/generic signatures. See `configs/appsec/appsec-hybrid.yaml`:

```yaml
name: crowdsecurity/appsec-hybrid
default_remediation: ban                       # fail-closed
inband_rules:
  - crowdsecurity/base-config
  - crowdsecurity/vpatch-*                     # CVE virtual patching
  - crowdsecurity/generic-*                    # broad attack signatures
outofband_rules:
  - crowdsecurity/experimental-*
  - crowdsecurity/appsec-generic-test
on_match:
  - filter: |
      any(evt.Appsec.MatchedRules, #.name startsWith "crowdsecurity/generic-")
    apply:
      - SetRemediation("captcha")
  - filter: |
      any(evt.Appsec.MatchedRules, #.name startsWith "crowdsecurity/vpatch-")
    apply:
      - SetRemediation("ban")                  # wins if both match
```

Install it into the container's config volume:

```sh
docker cp configs/appsec/appsec-hybrid.yaml \
  crowdsec:/etc/crowdsec/appsec-configs/appsec-hybrid.yaml
docker restart crowdsec
```

> **YAML gotcha:** the filter must use a `|` block scalar. In a plain scalar YAML treats `#` as a comment and truncates `#.name ...`, which makes the hook fail to compile and the engine exit fatally. See [06-alpine-gotchas.md](06-alpine-gotchas.md).

Test both branches:

```sh
curl -o /dev/null -w '%{http_code}\n' http://localhost/            # 200
curl -o /dev/null -w '%{http_code}\n' http://localhost/.env        # 403  (vpatch → ban)
curl -o /dev/null -w '%{http_code}\n' \
  'http://localhost/?x=freemarker.template.utility.execute'        # 200  (generic → captcha)
```

---

## 3. CAPTCHA

Providers supported by the bouncer: `recaptcha`, `hcaptcha`, `turnstile`.
**Use Cloudflare Turnstile if your clients are in mainland China** — Google is unreachable, while `challenges.cloudflare.com` and `hcaptcha.com` are reachable.

### Requirements

1. A provider account → Site Key + Secret Key.
2. An nginx DNS **resolver** (used to reach the provider's verification endpoint).
3. `lua_ssl_trusted_certificate` (already set in `05-crowdsec-lua.conf`).

`nginx.conf`:

```nginx
resolver 223.5.5.5 119.29.29.29 valid=300s ipv6=off;
```

Bouncer config:

```
CAPTCHA_PROVIDER=turnstile
SITE_KEY=<your_site_key>
SECRET_KEY=<your_secret_key>
CAPTCHA_TEMPLATE_PATH=/var/lib/crowdsec/lua/templates/captcha.html
CAPTCHA_EXPIRATION=3600
```

Restart OpenResty:

```sh
rc-service openresty restart
```

Create your Turnstile site at <https://dash.cloudflare.com> → Turnstile → Add site.

> **Test keys** (always pass, for wiring only — the widget shows "for testing purposes only"):
> site `1x00000000000000000000AA`, secret `1x0000000000000000000000000000000AA`.

### Verify

```sh
# force a captcha decision for the caller
docker exec crowdsec cscli decisions add --ip 127.0.0.1 --type captcha --duration 2m
curl -s http://localhost/ | grep -o 'CrowdSec Captcha'
docker exec crowdsec cscli decisions delete --ip 127.0.0.1
```

---

## 4. Choosing a strategy

| Goal | Config |
|---|---|
| Block everything | `appsec_configs: [crowdsecurity/appsec-default]` |
| Challenge everything | `default_remediation: captcha`, no `on_match` |
| **Hybrid (CVE ban / generic captcha)** | `appsec-hybrid.yaml` (this repo) |
| Only challenge some rules | change the `on_match` filter to exact rule names |

To change the strategy, replace the file in the container and restart it:

```sh
docker cp <new>.yaml crowdsec:/etc/crowdsec/appsec-configs/<name>.yaml
# update /opt/crowdsec/acquis.d/appsec.yaml to reference it
docker restart crowdsec
```
