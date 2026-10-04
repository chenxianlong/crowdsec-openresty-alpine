#!/bin/sh
# install-docker.sh — Install Docker on Alpine and configure a China-friendly registry mirror.
set -eu

MIRRORS_JSON='{
  "registry-mirrors": ["https://docker.m.daocloud.io", "https://docker.1ms.run"],
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}'

echo "==> Installing docker + compose"
apk add --no-cache docker docker-cli-compose

echo "==> Configuring registry mirror (/etc/docker/daemon.json)"
mkdir -p /etc/docker
printf '%s\n' "$MIRRORS_JSON" > /etc/docker/daemon.json

echo "==> Enabling and starting the docker service"
rc-update add docker default
if rc-service docker status >/dev/null 2>&1; then
  rc-service docker restart
else
  rc-service docker start
fi

sleep 3
echo "==> Versions"
docker version --format 'client={{.Client.Version}} server={{.Server.Version}}'
echo "==> Registry mirrors"
docker info 2>/dev/null | grep -A3 'Registry Mirrors' || true
echo "Done."
