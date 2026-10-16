#!/usr/bin/env bash
# Optional local at-rest encryption for the bridge's data/ directory.
#
# Encrypts EVERYTHING the bridge keeps on disk — the OAuth token cache, the
# TLS private key and the config — with gocryptfs. While locked, only
# ciphertext (in data.enc/) exists on disk; data/ is an empty mountpoint.
# You unlock it with a passphrase, then start the container.
#
# Note: the OAuth tokens are ALSO encrypted by the bridge itself with your
# per-account password; this layer additionally protects the TLS key and
# guards against disk/snapshot theft.
#
# Requires gocryptfs + FUSE on the host:
#     Debian/Ubuntu:  sudo apt install gocryptfs
#     and enable non-root access for the container bind-mount:
#     echo user_allow_other | sudo tee -a /etc/fuse.conf
#
# Usage:
#     ./secure-data.sh init      # one-time: create the encrypted store
#     ./secure-data.sh unlock     # mount data/  (run before: docker compose up -d)
#     ./secure-data.sh lock       # unmount data/ (run after: docker compose down)
#     ./secure-data.sh status
#
# Typical boot sequence after a VPS restart:
#     ./secure-data.sh unlock && docker compose up -d
set -euo pipefail
cd "$(dirname "$0")"

CIPHER="data.enc"     # ciphertext at rest (git-ignored)
PLAIN="data"          # mountpoint / plaintext view used by docker compose

is_mounted() { mountpoint -q "$PLAIN"; }

case "${1:-}" in
  init)
    command -v gocryptfs >/dev/null || { echo 'gocryptfs not installed.'; exit 1; }
    [ -d "$CIPHER" ] && { echo "$CIPHER already exists; refusing to re-init."; exit 1; }

    # Preserve any template files already in data/ (config, certs placeholder).
    STASH=""
    if [ -d "$PLAIN" ] && [ -n "$(ls -A "$PLAIN" 2>/dev/null)" ]; then
      STASH="data.preinit.$$"
      echo "Moving existing $PLAIN/ aside to $STASH/ ..."
      mv "$PLAIN" "$STASH"
    fi

    mkdir -p "$CIPHER" "$PLAIN"
    chmod 700 "$CIPHER" "$PLAIN"
    echo 'Initialising encrypted store (choose a strong passphrase):'
    gocryptfs -init "$CIPHER"
    echo 'Unlocking to import your files:'
    gocryptfs -allow_other "$CIPHER" "$PLAIN"

    if [ -n "$STASH" ]; then
      ( shopt -s dotglob; mv "$STASH"/* "$PLAIN"/ )
      rmdir "$STASH"
    fi
    chmod 600 "$PLAIN"/certs/*.pem 2>/dev/null || true
    echo "Done. data/ is unlocked and populated. Start with: docker compose up -d"
    ;;

  unlock)
    command -v gocryptfs >/dev/null || { echo 'gocryptfs not installed.'; exit 1; }
    [ -d "$CIPHER" ] || { echo "No $CIPHER/ found. Run: $0 init"; exit 1; }
    if is_mounted; then echo "$PLAIN/ already unlocked."; exit 0; fi
    mkdir -p "$PLAIN"
    gocryptfs -allow_other "$CIPHER" "$PLAIN"
    chmod 600 "$PLAIN"/certs/*.pem 2>/dev/null || true
    echo "Unlocked. Now: docker compose up -d"
    ;;

  lock)
    if ! is_mounted; then echo "$PLAIN/ is not mounted."; exit 0; fi
    # Stop the container first so nothing holds the mount open.
    docker compose ps --quiet 2>/dev/null | grep -q . && docker compose down || true
    fusermount -u "$PLAIN" 2>/dev/null || umount "$PLAIN"
    echo "Locked. data/ now shows only the empty mountpoint; secrets are in $CIPHER/."
    ;;

  status)
    if is_mounted; then echo "UNLOCKED: $PLAIN/ is mounted (plaintext visible)."
    else echo "LOCKED: $PLAIN/ not mounted; only ciphertext in $CIPHER/."; fi
    ;;

  *)
    echo "Usage: $0 {init|unlock|lock|status}"; exit 2 ;;
esac
