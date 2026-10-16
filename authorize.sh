#!/usr/bin/env bash
# One-time (or re-)authorization of a mailbox on the University Mail Bridge.
# Run it once per account (each address in emailproxy.config).
#
# Prereqs: the stack is already running (`docker compose up -d --build`) and,
# in another terminal, you have an SSH tunnel so the browser redirect reaches
# the VPS:
#
#     ssh -L 8080:localhost:8080 you@your-vps
#
set -euo pipefail
cd "$(dirname "$0")"

printf 'Email address to authorize (must match a section in emailproxy.config): '
read -r USER_ADDR
[ -n "$USER_ADDR" ] || { echo 'No address entered; aborting.'; exit 1; }

printf 'Choose a bridge password for %s\n' "$USER_ADDR"
printf '(you will enter this SAME password in your mail client): '
read -rs BRIDGE_PW
printf '\n'
[ -n "$BRIDGE_PW" ] || { echo 'No password entered; aborting.'; exit 1; }

echo
echo '==> Watch this terminal for a line like:'
echo '    "Please visit the following URL to authenticate ... https://login.microsoftonline.com/..."'
echo '    Open that URL in your browser (with the SSH tunnel active) and sign in to your university account.'
echo

# Stream the service log so the sign-in URL is visible.
docker compose logs -f --since 2s bridge &
LOGS_PID=$!
trap 'kill "$LOGS_PID" 2>/dev/null || true' EXIT

# Trigger the sign-in from inside the compose network. `run` does not publish
# ports, so it cannot clash with the running service.
BRIDGE_PW="$BRIDGE_PW" docker compose run --rm --no-deps \
  -e BRIDGE_USER="$USER_ADDR" \
  -e BRIDGE_PASSWORD="$BRIDGE_PW" \
  -e BRIDGE_CONTAINER="university-mail-bridge" \
  --entrypoint python bridge /data/authorize.py

echo
echo 'Done. The bridge now has a saved sign-in and will refresh it automatically.'
