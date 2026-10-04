# Contributing

Thanks for wanting to help! This project is a **deployment recipe**: real, tested
configs plus docs and scripts for running CrowdSec (IDS/IPS + WAF) on Alpine Linux
with OpenResty. Contributions of all sizes are welcome.

- [Ways to contribute](#ways-to-contribute)
- [Ground rules](#ground-rules)
- [Local checks (run these before a PR)](#local-checks-run-these-before-a-pr)
- [Repository layout](#repository-layout)
- [Style guide](#style-guide)
- [Adding a new platform](#adding-a-new-platform)
- [Commit messages](#commit-messages)
- [Pull requests](#pull-requests)
- [Security & secrets](#security--secrets)
- [License](#license)

## Ways to contribute

| I want to… | Do this |
|---|---|
| Report a bug / install failure | Open an issue with your OS, versions, the exact command and the error output |
| Improve docs | Edit the relevant `docs/*.md` or the READMEs |
| Fix / add a script | Edit `scripts/*.sh`, keep it POSIX `sh` and shellcheck-clean |
| Improve a config | Edit the relevant file under `configs/` and explain **why** in the PR |
| Add a gotcha | Add it to `docs/06-alpine-gotchas.md` with the exact symptom and fix |
| Support another distro | See [Adding a new platform](#adding-a-new-platform) |

Please **do not** open a PR that only re-formats unrelated files — it makes review hard.

## Ground rules

1. **Everything committed must be reproducible and tested.** If you change a config,
   say how you verified it (`nginx -t`, `cscli metrics show appsec`, a `curl` you ran…).
2. **Never commit secrets.** See [Security & secrets](#security--secrets).
3. **Keep it POSIX.** Scripts target Alpine/busybox `sh` (`/bin/sh`), not bash, unless
   they live under `scripts/ci-*.sh`.
4. **Fail closed by default.** Security defaults should deny/challenge unless explicitly
   downgraded.
5. Be respectful and constructive. Assume good faith in reviews.

## Local checks (run these before a PR)

CI runs the same checks. Reproduce them locally first:

```sh
# 1. Shell scripts (POSIX sh + shellcheck)
sh -n scripts/*.sh
shellcheck scripts/*.sh                       # brew/apt install shellcheck

# 2. YAML
yamllint -c .yamllint configs                 # pip install yamllint

# 3. Docker Compose
CROWDSEC_NGINX_BOUNCER_KEY=ci_dummy docker compose \
  -f configs/docker/docker-compose.yml config --quiet

# 4. nginx / OpenResty syntax (Debian/Ubuntu; stubs the Lua module)
sudo bash scripts/ci-validate-nginx.sh

# or just:
make lint
```

| Check | Tool | Config |
|---|---|---|
| Shell scripts | `shellcheck` | default rules (must be clean) |
| YAML | `yamllint` | [`.yamllint`](.yamllint) |
| Compose | `docker compose config` | — |
| nginx | `nginx -t` via OpenResty | [`scripts/ci-validate-nginx.sh`](scripts/ci-validate-nginx.sh) |

> The CI `nginx` job stubs the CrowdSec Lua module so `nginx -t` can load
> `access_by_lua_block` without a real engine. It validates **syntax**, not bouncer
> behaviour — describe any behavioural testing in your PR.

## Repository layout

```
docs/       explanation & guides (one topic per file)
configs/    deployable configuration, mirroring the target paths:
              configs/openresty/*  -> /etc/nginx/...
              configs/acquis.d/*   -> /opt/crowdsec/acquis.d/*  (engine)
              configs/appsec/*     -> /etc/crowdsec/appsec-configs/* (engine)
              configs/bouncers/*   -> /etc/crowdsec/bouncers/*
              configs/docker/*     -> /opt/crowdsec/*
scripts/    idempotent-ish install/verify scripts, plus CI helpers (ci-*.sh)
Makefile    ergonomic entry points that call the scripts
```

When you change a runtime file, remember it may exist **in two places**: the copy in
`configs/` and the path described in the docs. Keep them consistent.

## Style guide

### Shell (`scripts/*.sh`)

- `#!/bin/sh`, `set -eu`.
- Quote every expansion: `"$var"`, `"$(cmd)"`.
- Resolve the repo root instead of assuming a CWD:

  ```sh
  SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
  REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
  ```

- Guard `cd`: `cd "$DEST" || exit 1`.
- Prefer `if cmd; then …; else …; fi` over `cmd && a || b` (shellcheck SC2015).
- Allow overrides via environment variables with sensible defaults:

  ```sh
  SERVER_NAME=${SERVER_NAME:-localhost}
  ```

- Scripts should be safe to re-run where possible.

### nginx / OpenResty configs

- Put **http-context** directives (e.g. `lua_package_path`, `lua_shared_dict`,
  `access_by_lua_block`) in files included from the `http` block. On Alpine,
  `/etc/nginx/http.d/` is inside `http`, while `/etc/nginx/conf.d/` is the **main**
  context — this difference has bitten us (see `docs/06-alpine-gotchas.md`).
- Load OpenResty dynamic modules with **absolute** paths
  (`/usr/lib/nginx/modules/…`), never the relative `modules/…` form.
- Use `map` variables for WebSocket `Connection` handling rather than hard-coding.
- Always be able to answer: *does `nginx -t` pass?*

### YAML

- Linted with the repo's `.yamllint`.
- **Wrap hook filters in `|` block scalars.** A bare scalar containing `#.name …`
  is truncated by YAML as a comment and makes the engine exit fatally.
- Keep secrets as placeholders (`<BOUNCER_API_KEY>`), never real values.

### Docs

- One topic per file, lowercase-hyphenated names, linked from the README and `docs/`.
- Prefer runnable commands in fenced blocks with a language hint (```sh, ```nginx, ```yaml).
- When documenting a pitfall, include: **symptom → cause → fix**.

## Adding a new platform

The stack is split so that the engine is platform-independent (Docker) and only the
bouncer glue is distro-specific. To add a platform:

1. Add a `docs/0x-<platform>.md` with the exact package names and paths.
2. Keep the shared configs under `configs/`; add platform-specific overrides only if
   truly needed (e.g. a different module prefix).
3. If a `.deb`/`.rpm` package now exists for the engine, mention the native install as
   an alternative to Docker.

## Commit messages

Short imperative subject (< 72 chars), then an optional body explaining *why*.

```
Fix CI: load ndk before lua, resolve shellcheck SC2015

ngx_http_lua_module links against ndk_set_var_value, so ndk_http_module
must be loaded first. Also rewrote two `A && B || C` patterns.
```

Prefixes that are welcome: `docs:`, `fix:`, `feat:`, `ci:`, `config:`.

## Pull requests

1. Fork, branch from `main` (`fix/…`, `docs/…`, `feat/…`).
2. Make your change; run [local checks](#local-checks-run-these-before-a-pr).
3. If your change affects behaviour, describe how you tested it on a real host
   (commands + observed results). Screenshots of the CAPTCHA page are welcome.
4. Keep PRs focused; one logical change per PR.
5. Update the relevant docs and, if user-facing, `CHANGELOG.md`.
6. Ensure CI is green.

Maintainers may ask for changes; that is normal, not a rejection.

## Security & secrets

- **Never commit** bouncer API keys, CAPTCHA secrets, tokens, private keys, real
  domains belonging to others, or backup archives.
- Commit only `*.example` templates with `<PLACEHOLDER>` values.
- `.gitignore` already blocks:
  `configs/bouncers/crowdsec-nginx-bouncer.conf`, `configs/docker/.env`, `*.tgz`, `backups/`.
- Loopback only: LAPI (`8080`) and AppSec (`7422`) must stay bound to `127.0.0.1`.
- If you spot a committed secret, **open an issue immediately** (or a private security
  advisory) — do not just delete it in a new commit; it stays in history.

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE).
