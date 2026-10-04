# crowdsec-openresty-alpine

> **CrowdSec IDS/IPS + WAF on Alpine Linux with OpenResty, running in Docker** — a complete, reproducible deployment recipe for a small server: Nginx reverse proxy, IP blocking driven by CrowdSec, the AppSec (WAF) component, CAPTCHA challenges, and a **hybrid remediation** strategy (hard-block known CVEs, challenge the rest).

This repository is the distilled, working result of building that stack end-to-end on Alpine Linux. Every file in [`configs/`](configs) is a real, tested configuration. Every gotcha we hit is documented in [`docs/`](docs).

---

## What you get

- 🐳 **CrowdSec Security Engine in Docker** (LAPI + Log Processor), with a persisted config/database volume.
- 🧩 **CrowdSec Nginx/OpenResty bouncer** — the `cs-nginx-bouncer` Lua module loaded natively into **OpenResty** (no dynamic-module hacks).
- 🛡️ **AppSec / WAF** (`crowdsecurity/appsec-virtual-patching` + `appsec-generic-rules`, ~200 in-band rules).
- 🧮 **CAPTCHA challenge** via **Cloudflare Turnstile** (works from mainland China; reCAPTCHA does not).
- ⚖️ **Hybrid remediation**: known-CVE virtual patches are hard-blocked (403), broad/generic signatures get a CAPTCHA.
- 🔀 **Reverse proxy** for a local app (PM2-managed Node.js example) with WebSocket support and real-client-IP forwarding.
- 🔧 **Reverse proxy / TLS / gzip / caching** base config, plus a **dynamic-module loader** for OpenResty (geoip, image_filter, perl, xslt, mail, stream_geoip).

---

## Architecture

```
                    ┌──────────────────────────────────────────────┐
   client ────────► │  Alpine Linux host                           │
                    │                                              │
                    │  ┌────────────────────────────────────────┐  │
                    │  │ OpenResty (nginx)  :80 / :443          │  │
                    │  │  ├─ cs-nginx-bouncer (Lua, in-process) │  │
                    │  │  │    · checks LAPI decisions per req  │  │
                    │  │  │    · forwards HTTP to AppSec (WAF)   │  │
                    │  │  └─ reverse proxy ──► 127.0.0.1:3000   │  │
                    │  └───────────┬────────────────┬───────────┘  │
                    │              │ 127.0.0.1:8080  │ 127.0.0.1:7422
                    │              │ (LAPI)         │ (AppSec/WAF) │
                    │  ┌───────────▼────────────────▼───────────┐  │
                    │  │ Docker: crowdsecurity/crowdsec         │  │
                    │  │  · Log Processor (reads nginx logs)    │  │
                    │  │  · Local API + AppSec engine           │  │
                    │  └────────────────────────────────────────┘  │
                    │                                              │
                    │  PM2 ──► Node.js app on 127.0.0.1:3000       │
                    └──────────────────────────────────────────────┘
```

**Detect here, remedy there:** the Security Engine only *decides*; the in-process Lua bouncer *enforces* (ban / captcha / allow) and forwards requests to the WAF.

---

## Tested stack

| Component | Version |
|---|---|
| Alpine Linux | 3.24 |
| OpenResty | 1.31.1.1 (LuaJIT, ngx_lua static) |
| CrowdSec Security Engine | 1.8.1 (Docker) |
| cs-nginx-bouncer | v1.2.3 |
| Docker | 29.8.2 |
| Node.js / PM2 | 24.x / 7.x |

---

## Quick start

> Full, copy-paste steps are in [`docs/02-installation.md`](docs/02-installation.md). Below is the gist.

```bash
# 0. Clone
git clone https://github.com/chenxianlong/crowdsec-openresty-alpine.git
cd crowdsec-openresty-alpine

# 1. Docker + China-friendly registry mirror
sudo sh scripts/install-docker.sh

# 2. CrowdSec engine (Docker) + collections
sudo sh scripts/deploy-crowdsec.sh

# 3. OpenResty + the Lua bouncer (native)
sudo sh scripts/install-bouncer.sh

# 4. AppSec / WAF with the hybrid strategy
sudo sh scripts/enable-waf.sh

# 5. CAPTCHA (Turnstile) — put your real keys in the bouncer config afterwards
sudo sh scripts/enable-captcha.sh

# 6. Verify
sudo sh scripts/verify.sh
```

---

## Repository layout

```
.
├── README.md
├── LICENSE
├── docs/
│   ├── 01-architecture.md        # components & data flow
│   ├── 02-installation.md        # step-by-step deploy
│   ├── 03-waf-and-captcha.md     # AppSec, CAPTCHA, hybrid remediation
│   ├── 04-operations.md          # day-2 commands, tuning, upgrades
│   ├── 05-troubleshooting.md     # common failures & fixes
│   └── 06-alpine-gotchas.md      # the Alpine/OpenResty pitfalls we hit
├── configs/
│   ├── docker/
│   │   ├── docker-compose.yml
│   │   ├── daemon.json
│   │   └── .env.example
│   ├── acquis.d/
│   │   ├── nginx.yaml            # parse nginx access/error logs
│   │   └── appsec.yaml           # AppSec (WAF) listener
│   ├── appsec/
│   │   └── appsec-hybrid.yaml    # hybrid remediation config
│   ├── bouncers/
│   │   └── crowdsec-nginx-bouncer.conf.example
│   └── openresty/
│       ├── nginx.conf
│       ├── 00-dynamic-modules.conf
│       ├── 05-crowdsec-lua.conf
│       ├── 10-https.conf
│       ├── 20-app.conf
│       └── default.conf
└── scripts/
    ├── install-docker.sh
    ├── deploy-crowdsec.sh
    ├── install-bouncer.sh
    ├── enable-waf.sh
    ├── enable-captcha.sh
    └── verify.sh
```

---

## Key concepts

| Term | Meaning |
|---|---|
| **Security Engine** | CrowdSec itself: reads logs (and HTTP requests), applies scenarios/rules, produces **decisions**. It blocks nothing by itself. |
| **Bouncer / Remediation Component** | Enforces decisions. Here it's the `cs-nginx-bouncer` Lua module inside OpenResty. |
| **LAPI** | Local API — the decision service the bouncer queries (`127.0.0.1:8080`). |
| **AppSec / WAF** | In-band HTTP inspection. Each request is forwarded to the AppSec engine (`127.0.0.1:7422`), which replies `ban` / `captcha` / `allow`. |
| **Hybrid remediation** | `default_remediation: ban`, then an `on_match` hook downgrades broad `generic-*` matches to `captcha`. |

---

## Security notes

- **Secrets**: `configs/bouncers/crowdsec-nginx-bouncer.conf` (API key + CAPTCHA secret) and `configs/docker/.env` are **git-ignored**. Only `*.example` templates are committed.
- **Bind to loopback**: LAPI (8080) and AppSec (7422) are published to `127.0.0.1` only. They must **never** be exposed to the internet.
- **CAPTCHA keys**: the placeholders are Cloudflare's *test* keys (always pass). Replace them with real Turnstile keys before production.
- **Fail-closed WAF**: the hybrid config hard-blocks anything not explicitly downgraded.

---

## License

[MIT](LICENSE) © 2026 chenxianlong

CrowdSec, OpenResty and Cloudflare Turnstile are the property of their respective owners.
