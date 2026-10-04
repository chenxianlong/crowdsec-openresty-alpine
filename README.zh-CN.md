# crowdsec-openresty-alpine

> **在 Alpine Linux 上用 OpenResty 部署 CrowdSec IDS/IPS + WAF** —— 一套可复现的完整方案：Nginx 反向代理、CrowdSec 驱动的 IP 封禁、AppSec（WAF）、CAPTCHA 人机验证，以及**混合处置策略**（已知 CVE 直接硬封锁，其余通用攻击特征走验证码）。

本仓库是一台小服务器上从零搭建该技术栈的**真实、可验证**成果。`configs/` 里是线上实测过的配置，`docs/` 里记录了踩过的每一个坑。

[English README](README.md)

---

## 你能得到什么

- 🐳 **CrowdSec 安全引擎跑在 Docker**（LAPI + 日志处理器），配置与数据库持久化。
- 🧩 **CrowdSec Nginx/OpenResty bouncer** —— `cs-nginx-bouncer` Lua 模块**原生**加载进 **OpenResty**（无需动态模块的 hack）。
- 🛡️ **AppSec / WAF**（`appsec-virtual-patching` + `appsec-generic-rules`，约 200 条 in-band 规则）。
- 🧮 **CAPTCHA 挑战**，用 **Cloudflare Turnstile**（国内可用；Google reCAPTCHA 不可用）。
- ⚖️ **混合策略**：已知 CVE 虚拟补丁 → 硬封锁（403）；通用/宽泛特征 → CAPTCHA。
- 🔀 **反向代理**（PM2 托管的 Node.js 示例），支持 WebSocket 与真实客户端 IP 透传。
- 🔧 反向代理/TLS/gzip/静态缓存基础配置，以及 **OpenResty 动态模块加载器**（geoip、image_filter、perl、xslt、mail、stream_geoip）。

---

## 架构

```
                    ┌──────────────────────────────────────────────┐
   客户端 ────────► │  Alpine Linux 宿主机                          │
                    │                                              │
                    │  ┌────────────────────────────────────────┐  │
                    │  │ OpenResty (nginx)  :80 / :443          │  │
                    │  │  ├─ cs-nginx-bouncer (Lua, 进程内)      │  │
                    │  │  │    · 每请求查 LAPI 决策              │  │
                    │  │  │    · 转发 HTTP 给 AppSec (WAF)       │  │
                    │  │  └─ 反向代理 ──────► 127.0.0.1:3000    │  │
                    │  └───────────┬────────────────┬───────────┘  │
                    │              │ 127.0.0.1:8080  │ 127.0.0.1:7422
                    │              │ (LAPI)         │ (AppSec/WAF) │
                    │  ┌───────────▼────────────────▼───────────┐  │
                    │  │ Docker: crowdsecurity/crowdsec         │  │
                    │  │  · 日志处理器（读 nginx 日志）          │  │
                    │  │  · Local API + AppSec 引擎             │  │
                    │  └────────────────────────────────────────┘  │
                    │                                              │
                    │  PM2 ──► Node.js 应用  127.0.0.1:3000        │
                    └──────────────────────────────────────────────┘
```

**"在此检测，在彼处置"**：安全引擎只负责**决策**；进程内的 Lua bouncer 负责**执行**（ban / captcha / allow），并把请求转发给 WAF。

---

## 实测版本

| 组件 | 版本 |
|---|---|
| Alpine Linux | 3.24 |
| OpenResty | 1.31.1.1（LuaJIT，ngx_lua 静态内置） |
| CrowdSec Security Engine | 1.8.1 (Docker) |
| cs-nginx-bouncer | v1.2.3 |
| Docker | 29.8.2 |
| Node.js / PM2 | 24.x / 7.x |

---

## 快速开始

> 完整逐步说明见 [`docs/02-installation.md`](docs/02-installation.md)。

**方式一：一键 `make`**

```sh
git clone https://github.com/chenxianlong/crowdsec-openresty-alpine.git
cd crowdsec-openresty-alpine

sudo make all        # docker + 引擎 + bouncer + WAF + captcha + 验证
# 或分步执行：
#   sudo make docker    # Docker + 国内镜像源
#   sudo make engine    # CrowdSec 引擎 (Docker)
#   sudo make bouncer   # OpenResty + Lua bouncer
#   sudo make waf       # AppSec/WAF（混合策略）
#   sudo make captcha   # CAPTCHA (Turnstile)
#   sudo make verify    # 健康检查
```

可用变量：

```sh
SERVER_NAME=app.example.com make bouncer
CAPTCHA_PROVIDER=turnstile SITE_KEY=xxx SECRET_KEY=yyy make captcha
```

**方式二：直接跑脚本**

```sh
sudo sh scripts/install-docker.sh
sudo sh scripts/deploy-crowdsec.sh
sudo sh scripts/install-bouncer.sh
sudo sh scripts/enable-waf.sh
sudo sh scripts/enable-captcha.sh
sudo sh scripts/verify.sh
```

---

## 目录结构

```
.
├── README.md / README.zh-CN.md
├── LICENSE                         # MIT
├── Makefile                        # 一键部署入口
├── .github/workflows/lint.yml      # CI: shellcheck / yamllint / compose / nginx -t
├── docs/
│   ├── 01-architecture.md          # 组件与请求生命周期
│   ├── 02-installation.md          # 从零部署
│   ├── 03-waf-and-captcha.md       # AppSec、CAPTCHA、混合策略
│   ├── 04-operations.md            # 日常运维、调优、升级
│   ├── 05-troubleshooting.md       # 故障排查
│   └── 06-alpine-gotchas.md        # Alpine/OpenResty 的 11 个坑
├── configs/
│   ├── docker/{docker-compose.yml,daemon.json,.env.example}
│   ├── acquis.d/{nginx.yaml,appsec.yaml}
│   ├── appsec/appsec-hybrid.yaml
│   ├── bouncers/crowdsec-nginx-bouncer.conf.example
│   └── openresty/{nginx.conf,00-dynamic-modules.conf,05-crowdsec-lua.conf,10-https.conf,20-app.conf,default.conf}
└── scripts/
    ├── install-docker.sh           # Docker + 国内镜像
    ├── deploy-crowdsec.sh          # 引擎 (Docker) + collections
    ├── install-bouncer.sh          # OpenResty + Lua bouncer
    ├── enable-waf.sh               # AppSec/WAF + 混合策略
    ├── enable-captcha.sh           # CAPTCHA (Turnstile)
    ├── verify.sh                   # 健康检查
    └── ci-validate-nginx.sh        # CI 用：nginx -t 语法校验
```

---

## 关键概念

| 术语 | 含义 |
|---|---|
| **Security Engine** | CrowdSec 本体：读日志/HTTP 请求，套用场景与规则，产出**决策**。它本身不封禁任何东西。 |
| **Bouncer / 修复组件** | 执行决策。这里是 OpenResty 内的 `cs-nginx-bouncer` Lua 模块。 |
| **LAPI** | Local API，bouncer 查询决策的服务（`127.0.0.1:8080`）。 |
| **AppSec / WAF** | 同步 HTTP 检测。每个请求转发给 AppSec 引擎（`127.0.0.1:7422`），返回 `ban` / `captcha` / `allow`。 |
| **混合策略** | `default_remediation: ban`，再用 `on_match` hook 把宽泛的 `generic-*` 命中降级为 `captcha`。 |

---

## 安全须知

- **密钥**：`configs/bouncers/crowdsec-nginx-bouncer.conf`（API key + 验证码密钥）与 `configs/docker/.env` 已在 `.gitignore` 中屏蔽，仓库只提交 `*.example` 模板。
- **仅绑定回环**：LAPI（8080）与 AppSec（7422）只发布到 `127.0.0.1`，**绝不能**暴露到公网。
- **CAPTCHA 密钥**：仓库里的占位符是 Cloudflare **测试**密钥（永远通过），上线前务必替换为真实密钥。
- **WAF fail-closed**：混合配置默认封锁任何未被显式降级的命中。

---

## 贡献

见 [CONTRIBUTING.md](CONTRIBUTING.md)。提交 PR 前请先运行 `make lint`。

## 许可证

[MIT](LICENSE) © 2026 chenxianlong

CrowdSec、OpenResty、Cloudflare Turnstile 分别归其各自所有者所有。
