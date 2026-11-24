#!/bin/bash
# The image under the deployment server's hardening (read-only, every capability dropped, no new privileges, pids,
# memory and CPU limits, as deploy.sh runs it): it must answer /healthz and run as a user other than root.
# Used by .github/workflows/image.yml, for a pull request and before publishing: bash .github/smoke-test.sh IMAGE
# Settings the app needs get test values here: GREETING, plus smoke-test.env next to this script when it exists (one
# KEY=value per line; test values only, never real secrets). The servers' values live in the deployment manager's app
# spec, so a release that needs a setting the environment lacks passes here and fails the server's health check.
# The spec's own limits, when it sets other ones: .github/smoke-test.conf next to this script, lines SMOKE_TMPFS="/tmp
# /run" (the spec's hardening.tmpfs) and SMOKE_MEMORY=128m (its limits.memory). Read as data, never run as shell.
set -euo pipefail
image=${1:?the image to test}
port=${SMOKE_PORT:-18080}      # another free port on a machine where 18080 is taken
name=smoke-$$
conf="$(dirname "$0")/smoke-test.conf"
if [ -f "$conf" ]; then
  while IFS= read -r line; do
    case "$line" in
      SMOKE_TMPFS=*) v=${line#SMOKE_TMPFS=}; v=${v//\"/}
                     [[ $v =~ ^[A-Za-z0-9/_.\ -]*$ ]] || { echo "smoke-test.conf: SMOKE_TMPFS takes paths only"; exit 1; }
                     SMOKE_TMPFS=${SMOKE_TMPFS:-$v} ;;
      SMOKE_MEMORY=*) v=${line#SMOKE_MEMORY=}; v=${v//\"/}
                      [[ $v =~ ^[0-9]+[mg]$ ]] || { echo "smoke-test.conf: SMOKE_MEMORY is like 128m"; exit 1; }
                      SMOKE_MEMORY=${SMOKE_MEMORY:-$v} ;;
    esac
  done < "$conf"
fi
memory=${SMOKE_MEMORY:-64m}
tmpfs=()
for p in ${SMOKE_TMPFS:-}; do tmpfs+=(--tmpfs "$p"); done
user=$(docker inspect -f '{{.Config.User}}' "$image")
case "$user" in ""|root|0|0:*|root:*) echo "the image runs as root (USER is '${user}'): the server runs it as is"; exit 1 ;; esac
env=(-e GREETING="CI smoke test")
[ -f "$(dirname "$0")/smoke-test.env" ] && env+=(--env-file "$(dirname "$0")/smoke-test.env")
cleanup() {                    # the container goes either way, even one created but never started; its log on failure
  local rc=$?
  [ "$rc" = 0 ] || docker logs "$name" 2>&1 | tail -20
  docker rm -f "$name" >/dev/null 2>&1 || true
}
trap cleanup EXIT
docker run -d --name "$name" --read-only --cap-drop=ALL --security-opt=no-new-privileges --pids-limit=128 \
  --memory "$memory" --cpus 0.25 ${tmpfs[@]+"${tmpfs[@]}"} "${env[@]}" -p "127.0.0.1:$port:8080" "$image" >/dev/null
for _ in $(seq 1 30); do curl -fsS -o /dev/null "http://127.0.0.1:$port/healthz" 2>/dev/null && break; sleep 1; done
curl -fsS "http://127.0.0.1:$port/healthz"
echo
# Coolify's own health check runs inside the container, with curl or wget, against 127.0.0.1:8080
if ! docker exec "$name" sh -c 'curl -fsS -o /dev/null http://127.0.0.1:8080/healthz 2>/dev/null ||
                                wget -q -O /dev/null http://127.0.0.1:8080/healthz' >/dev/null 2>&1; then
  echo "the health check inside the container failed: the server's check needs sh plus curl or wget in the image,"
  echo "and /healthz answering on 127.0.0.1:8080 there"
  exit 1
fi
echo "smoke test passed: /healthz answered under the hardening ($memory, tmpfs: ${SMOKE_TMPFS:-none}), as user $user"
