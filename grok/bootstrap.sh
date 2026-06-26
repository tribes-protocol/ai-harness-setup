#!/bin/sh
# grok harness — bootstrap (runs ONCE, as root, cwd /workspace, under sh).
# Installs the xAI grok CLI and stamps the host into AGENTS.md. grok's only
# FILE-based config is its theme (.grok/config.toml, committed as a SEED FILE with
# a __TRIBES_THEME__ placeholder) — that placeholder is filled on EVERY launch in
# launch.sh, not here. grok's proxy is ENV-only (GROK_* vars), also in launch.sh.

set -e

# --- install the harness binary ---------------------------------------------
if ! command -v grok >/dev/null 2>&1; then
  echo "Installing grok (first boot of this sandbox)..."
  curl -fsSL https://x.ai/cli/install.sh | GROK_BIN_DIR=/usr/local/bin bash || true
fi

# --- stamp the host into the primer -----------------------------------------
# AGENTS.md ships with a __HOST__ placeholder; substitute the VM's public
# subdomain so the agent knows its live URL. (grok reads AGENTS.md.)
host="${HOSTNAME:-$(cat /etc/hostname 2>/dev/null)}"
if [ -n "$host" ]; then
  for file in /workspace/AGENTS.md; do
    [ -e "$file" ] && sed -i "s|__HOST__|$host|g" "$file"
  done
fi

# --- safety net -------------------------------------------------------------
# Belt-and-suspenders: no file under /workspace may survive bootstrap with a raw
# __TRIBES_* placeholder. grok's ONLY placeholder (__TRIBES_THEME__ in
# .grok/config.toml) is filled per-launch in launch.sh, which also recreates the
# file if missing — so removing it here is harmless. AGENTS.md only carries
# __HOST__, so it is not matched.
grep -rlZ "__TRIBES_" /workspace 2>/dev/null | xargs -0 rm -f 2>/dev/null || true
