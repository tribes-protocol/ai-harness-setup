#!/bin/sh
# cursor harness — bootstrap (runs ONCE, as root, cwd /workspace, under sh).
# Installs the Cursor CLI (cursor.com/cli). Cursor has NO custom base-URL
# support — the CLI always routes through Cursor's own backend — so there is NO
# metered-proxy config anywhere in this harness: it is BYO-Cursor-account
# (in-TUI `/login`, or CURSOR_API_KEY). The non-interactive config
# (.cursor/cli-config.json: approvalMode unrestricted + cursor's own sandbox
# disabled — the microVM is the security boundary) ships as a committed real
# file in this harness dir, copied verbatim into /workspace by the dispatcher.
set -e

# --- install the harness binary ---------------------------------------------
# The official installer unpacks a self-contained build under
# $HOME/.local/share/cursor-agent and symlinks `agent` into $HOME/.local/bin —
# no root or Node needed. Pin HOME=/workspace so the install lands on the
# persistent workspace disk (HOME at launch time) whatever env the dispatcher
# ran us with. /workspace/.local/bin is not on the dispatcher's PATH, so also
# expose the entry symlink at /usr/local/bin, which always is.
command -v agent >/dev/null 2>&1 ||
  curl -fsS https://cursor.com/install | HOME=/workspace bash || true
[ -x /workspace/.local/bin/agent ] &&
  ln -sf /workspace/.local/bin/agent /usr/local/bin/agent || true

# --- seed the shared agent primer -------------------------------------------
# Seed the shared agent primer from the repo root (single source of truth).
# cursor reads AGENTS.md natively (it also reads CLAUDE.md — same content, so
# one file is enough; do not duplicate).
RAW_BASE="$(echo "${TRIBES_HARNESS_REPO:-https://github.com/tribes-protocol/ai-harness-setup}" | sed 's#//github\.com#//raw.githubusercontent.com#')"
curl -fsSL "$RAW_BASE/main/AGENTS.md" -o /workspace/AGENTS.md 2>/dev/null || true
host="${HOSTNAME:-$(hostname 2>/dev/null || true)}"
[ -n "$host" ] && [ -e /workspace/AGENTS.md ] && sed -i "s|__HOST__|$host|g" /workspace/AGENTS.md
