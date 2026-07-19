#!/bin/sh
# grok harness — bootstrap (runs ONCE, as root, cwd /root/workspace, under sh).
# Installs the xAI grok CLI and stamps the host into AGENTS.md. grok's only
# FILE-based config is its theme (.grok/config.toml, committed as a SEED FILE with
# a __TRIBES_THEME__ placeholder) — we fill that placeholder HERE from the
# create-time TRIBES_THEME so the file is valid (no raw placeholder) and survives
# the end-of-bootstrap safety net. launch.sh re-seds it each launch so a theme
# toggle takes effect on relaunch. grok's proxy is ENV-only (GROK_* vars), in launch.sh.
# Config paths are $HOME-relative — the dispatcher decides HOME (old: workspace,
# new: /root).

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
if [ -e "$HOME/.grok/config.toml" ]; then
  sed -i "s|__TRIBES_THEME__|$theme|g" "$HOME/.grok/config.toml"
fi

# --- seed the shared agent primer -------------------------------------------
# Seed the shared agent primer from the repo root (single source of truth).
RAW_BASE="$(echo "${TRIBES_HARNESS_REPO:-https://github.com/tribes-protocol/ai-harness-setup}" | sed 's#//github\.com#//raw.githubusercontent.com#')"
curl -fsSL "$RAW_BASE/main/AGENTS.md" -o /root/workspace/AGENTS.md 2>/dev/null || true
host="${HOSTNAME:-$(hostname 2>/dev/null || true)}"
[ -n "$host" ] && [ -e /root/workspace/AGENTS.md ] && sed -i "s|__HOST__|$host|g" /root/workspace/AGENTS.md
# Fill the sandbox's own mailbox address the same way as __HOST__. Unlike the
# hostname it is not a boot env var (different apex, per-sandbox), so read it from
# the baked tribes-email CLI — the same source the zipbox-email skill uses. Drop
# the line when no address is available (older, pre-email sandboxes) so no raw
# placeholder survives.
if [ -e /root/workspace/AGENTS.md ]; then
  email="$(tribes-email status 2>/dev/null | grep -oE '"address"[[:space:]]*:[[:space:]]*"[^"]+"' | sed -E 's/.*"([^"]+)"$/\\1/' | head -n1)"
  if [ -n "$email" ]; then
    sed -i "s|__EMAIL__|$email|g" /root/workspace/AGENTS.md
  else
    sed -i "/__EMAIL__/d" /root/workspace/AGENTS.md
  fi
fi

# --- safety net -------------------------------------------------------------
# Belt-and-suspenders: no file under /root/workspace may survive bootstrap with a raw
# __TRIBES_* placeholder. grok's ONLY placeholder (__TRIBES_THEME__ in
# .grok/config.toml) is now filled above, so the config is CONCRETE and is NOT
# matched here. AGENTS.md only carries __HOST__ and __EMAIL__ (both filled above), so it is not matched either. This
# only fires if some file slips through unfilled.
# NEVER delete *.sh — bootstrap.sh/launch.sh legitimately contain __TRIBES_ in
# their sed patterns/fallbacks; only NON-script files with a raw placeholder are
# broken config and get removed.
grep -rl "__TRIBES_" /root/workspace "$HOME/.grok" 2>/dev/null | while IFS= read -r f; do
  case "$f" in *.sh) ;; *) rm -f "$f" ;; esac
done

# --- shared agent skills (single source of truth, installed at boot) --------
# Install the skill set read-only under /root/skills and wire the native
# (claude/pi) or AGENTS.md loaders. Drive-first (#1914): the shared read-only
# /opt/harnesses drive bakes the pinned catalog AND this installer, so a stock
# boot runs the baked copy and needs no network for skills. The installer is
# fetched only when the drive predates skills (old image, dev backend) or a
# pinned TRIBES_HARNESS_REF (QA) must exercise that branch's own installer.
# Runs after all config writes; fully tolerant, so it never blocks or fails
# the boot.
if [ -z "${TRIBES_HARNESS_REF:-}" ] && [ -f /opt/harnesses/skills/install-skills.sh ]; then
  sh /opt/harnesses/skills/install-skills.sh || true
else
  curl -fsSL --max-time 20 "$RAW_BASE/${TRIBES_HARNESS_REF:-main}/install-skills.sh" | sh || true
fi
