# Architecture

## Components

| Component | Where | Role |
|---|---|---|
| **OpenResty** | host, `:80`/`:443` | Reverse proxy + hosts the Lua bouncer. OpenResty = nginx + LuaJIT + bundles. |
| **cs-nginx-bouncer** | inside OpenResty | Lua module: asks LAPI for decisions per request, and forwards requests to AppSec. |
| **CrowdSec Security Engine** | Docker container | Log Processor (scenarios) + Local API (decisions) + AppSec engine (WAF). |
| **PM2 app** | host, `127.0.0.1:3000` | The protected backend (any HTTP service works). |

## Request lifecycle

```
client
  │
  ▼
OpenResty ──► access_by_lua_block (cs-nginx-bouncer)
  │              │
  │              ├─ 1. Ask LAPI: is this IP banned?        → 403 / captcha
  │              │      GET http://127.0.0.1:8080/v1/decisions?ip=...
  │              │
  │              ├─ 2. Forward request to AppSec (WAF):     → ban / captcha / allow
  │              │      POST http://127.0.0.1:7422/...
  │              │
  │              └─ 3. allow  → continue
  │
  ▼
location /  → proxy_pass 127.0.0.1:3000
```

## Why "detect here, remedy there"

The Security Engine only **decides**. The bouncer only **enforces**. This decoupling means:

- you can parse logs from one machine and block on another;
- one LAPI can serve many bouncers/reverse-proxies;
- the engine can be a container while the proxy stays on the host (our setup).

## Deployment topology used here

- Engine in **Docker** (distro-agnostic, easy upgrades) — the official package only ships `.deb`/`.rpm`, so this is how you run it on Alpine.
- Bouncer **native** in the host OpenResty (it is an in-process Lua module, so it cannot be a standalone container).

## Ports

| Port | Bound to | Purpose |
|---|---|---|
| 80 / 443 | `0.0.0.0` | Public HTTP/HTTPS |
| 3000 | `127.0.0.1` | Backend app (PM2) |
| 8080 | `127.0.0.1` | CrowdSec LAPI |
| 7422 | `127.0.0.1` | CrowdSec AppSec (WAF) |
