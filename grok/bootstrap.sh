#!/bin/sh
# grok harness — bootstrap (runs ONCE, as root, cwd /root/workspace, under sh).
# Installs the xAI grok CLI and stamps the host into AGENTS.md. grok's only
# FILE-based config is its theme (.grok/config.toml, committed as a SEED FILE with
# a __TRIBES_THEME__ placeholder) — we fill that placeholder HERE from the
# create-time TRIBES_THEME so the file is valid (no raw placeholder) and survives
# the end-of-bootstrap safety net. launch.sh re-seds it each launch so a theme
# toggle takes effect on relaunch. grok's proxy is ENV-only (GROK_* vars), in launch.sh.

set -e

# --- install the harness binary ---------------------------------------------
if ! command -v grok >/dev/null 2>&1; then
  echo "Installing grok (first boot of this sandbox)..."
  curl -fsSL https://x.ai/cli/install.sh | GROK_BIN_DIR=/usr/local/bin bash || true
fi

# --- fill the theme placeholder (FILE config) -------------------------------
# .grok/config.toml ships as a SEED with theme = "__TRIBES_THEME__". Substitute
# the create-time theme so the committed file ends up CONCRETE (light/dark) — no
# raw placeholder left for the safety net below to delete. Default dark.
theme=$([ "$TRIBES_THEME" = light ] && echo light || echo dark)
if [ -e /root/workspace/.grok/config.toml ]; then
  sed -i "s|__TRIBES_THEME__|$theme|g" /root/workspace/.grok/config.toml
fi

# --- seed the shared agent primer -------------------------------------------
# Seed the shared agent primer from the repo root (single source of truth).
RAW_BASE="$(echo "${TRIBES_HARNESS_REPO:-https://github.com/tribes-protocol/ai-harness-setup}" | sed 's#//github\.com#//raw.githubusercontent.com#')"
curl -fsSL "$RAW_BASE/main/AGENTS.md" -o /root/workspace/AGENTS.md 2>/dev/null || true
host="${HOSTNAME:-$(hostname 2>/dev/null || true)}"
[ -n "$host" ] && [ -e /root/workspace/AGENTS.md ] && sed -i "s|__HOST__|$host|g" /root/workspace/AGENTS.md

# --- safety net -------------------------------------------------------------
# Belt-and-suspenders: no file under /root/workspace may survive bootstrap with a raw
# __TRIBES_* placeholder. grok's ONLY placeholder (__TRIBES_THEME__ in
# .grok/config.toml) is now filled above, so the config is CONCRETE and is NOT
# matched here. AGENTS.md only carries __HOST__, so it is not matched either. This
# only fires if some file slips through unfilled.
# NEVER delete *.sh — bootstrap.sh/launch.sh legitimately contain __TRIBES_ in
# their sed patterns/fallbacks; only NON-script files with a raw placeholder are
# broken config and get removed.
grep -rl "__TRIBES_" /root/workspace 2>/dev/null | while IFS= read -r f; do
  case "$f" in *.sh) ;; *) rm -f "$f" ;; esac
done
