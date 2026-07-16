#!/bin/sh
# cursor harness — bootstrap (runs ONCE, as root, cwd /root/workspace, under sh).
# Installs the Cursor CLI (cursor.com/cli). Cursor has NO custom base-URL
# support — the CLI always routes through Cursor's own backend — so there is NO
# metered-proxy config anywhere in this harness: it is BYO-Cursor-account
# (in-TUI `/login`, or CURSOR_API_KEY). The non-interactive config
# (.cursor/cli-config.json: approvalMode unrestricted + cursor's own sandbox
# disabled — the microVM is the security boundary) ships as a committed real
# file in this harness dir, copied verbatim into /root/workspace by the dispatcher,
# then — like every other harness's dot-config — relocated to $HOME (the
# dispatcher decides HOME: old dispatcher leaves it in the workspace, new
# dispatcher moves it to /root). cursor-agent reads its config from the actual
# HOME env var at runtime, so no path in this script needs to know which.
set -e

# --- install the harness binary ---------------------------------------------
# The official installer unpacks a self-contained build under
# $HOME/.local/share/cursor-agent and symlinks `agent` into $HOME/.local/bin —
# no root or Node needed. Pin HOME=/root/workspace for the INSTALL regardless of
# what HOME the dispatcher runs this script with, so the binary always lands on
# the persistent workspace disk (.local/ is never relocated by the dispatcher —
# only the dot-config dirs are). /root/workspace/.local/bin is not on the
# dispatcher's PATH, so also expose the entry symlink at /usr/local/bin, which
# always is.
command -v agent >/dev/null 2>&1 ||
  curl -fsS https://cursor.com/install | HOME=/root/workspace bash || true
[ -x /root/workspace/.local/bin/agent ] &&
  ln -sf /root/workspace/.local/bin/agent /usr/local/bin/agent || true

# --- seed the shared agent primer -------------------------------------------
# Seed the shared agent primer from the repo root (single source of truth).
# cursor reads AGENTS.md natively (it also reads CLAUDE.md — same content, so
# one file is enough; do not duplicate).
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

# --- shared agent skills (single source of truth, refreshed at boot) --------
# Install the published skill set read-only under /root/skills and wire the native
# (claude/pi) or AGENTS.md loaders. Runs after all config writes; fully
# tolerant, so it never blocks or fails the boot.
curl -fsSL --max-time 20 "$RAW_BASE/${TRIBES_HARNESS_REF:-main}/install-skills.sh" | sh || true
