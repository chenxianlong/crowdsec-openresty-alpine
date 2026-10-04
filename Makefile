# crowdsec-openresty-alpine — one-command deployment entry point
SHELL := /bin/sh
SCRIPTS := scripts

# Pass these through to the scripts when set on the command line / environment
export SERVER_NAME
export BOUNCER_VER
export CAPTCHA_PROVIDER
export SITE_KEY
export SECRET_KEY

.DEFAULT_GOAL := help
.PHONY: help all docker engine bouncer waf captcha verify lint clean

help:
	@echo "crowdsec-openresty-alpine"
	@echo ""
	@echo "Targets:"
	@echo "  make all        docker + engine + bouncer + waf + captcha + verify"
	@echo "  make docker     install Docker and a China-friendly registry mirror"
	@echo "  make engine     deploy the CrowdSec Security Engine (Docker)"
	@echo "  make bouncer    install OpenResty and the Lua bouncer"
	@echo "  make waf        enable AppSec (WAF) with the hybrid remediation strategy"
	@echo "  make captcha    enable CAPTCHA (Cloudflare Turnstile by default)"
	@echo "  make verify     health-check the whole stack"
	@echo "  make lint       run shellcheck + yamllint locally (if installed)"
	@echo ""
	@echo "Variables (example):"
	@echo "  SERVER_NAME=app.example.com make bouncer"
	@echo "  CAPTCHA_PROVIDER=turnstile SITE_KEY=... SECRET_KEY=... make captcha"

all: docker engine bouncer waf captcha verify

docker:
	sh $(SCRIPTS)/install-docker.sh

engine:
	sh $(SCRIPTS)/deploy-crowdsec.sh

bouncer:
	sh $(SCRIPTS)/install-bouncer.sh

waf:
	sh $(SCRIPTS)/enable-waf.sh

captcha:
	sh $(SCRIPTS)/enable-captcha.sh

verify:
	sh $(SCRIPTS)/verify.sh

lint:
	@command -v shellcheck >/dev/null 2>&1 && shellcheck $(SCRIPTS)/*.sh || echo "shellcheck not installed, skipping"
	@command -v yamllint  >/dev/null 2>&1 && yamllint -c .yamllint configs || echo "yamllint not installed, skipping"

clean:
	@echo "Nothing to clean locally. The deployment lives under /opt/crowdsec and /etc/nginx."
