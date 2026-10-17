#!/usr/bin/env bash
# One-time (or re-)authorization of a mailbox on the University Mail Bridge.
# Run it once per account (each address in emailproxy.config).
#
# Prereqs: the stack is already running (`docker compose up -d`) and, in
# another terminal, you have an SSH tunnel so the browser redirect reaches the
# VPS:
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

# Trigger the sign-in from inside the running container. The address and the
# password travel over stdin, so neither shows up in a command line or `ps`.
printf '%s\n%s\n' "$USER_ADDR" "$BRIDGE_PW" |
  docker compose exec -T bridge python /data/authorize.py

echo
echo 'Done. The bridge now has a saved sign-in and will refresh it automatically.'
