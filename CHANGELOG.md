# Changelog

## 2026-10-04 — documentation & tooling

- Add `CONTRIBUTING.md`
- Add CI (`lint.yml`): shellcheck, yamllint, docker compose config, nginx -t
- Add `.yamllint` and `scripts/ci-validate-nginx.sh`
- Add `Makefile` one-command deployment entry point
- Add `README.zh-CN.md` (Chinese README)

## 2026-10-04 — initial release

Built and verified end-to-end on Alpine Linux 3.24:

- Docker + China registry mirror
- CrowdSec Security Engine in Docker (LAPI, log processor, collections)
- OpenResty (replacing nginx) with the `cs-nginx-bouncer` Lua module
- AppSec / WAF with `appsec-virtual-patching` + `appsec-generic-rules`
- CAPTCHA via Cloudflare Turnstile
- Hybrid remediation (`appsec-hybrid.yaml`): CVE virtual patches → ban, generic rules → captcha
- Dynamic module loading for OpenResty (geoip, image_filter, perl, xslt, mail, stream_geoip)
- Reverse proxy + TLS + gzip + static caching base config
