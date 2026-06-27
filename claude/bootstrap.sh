#!/bin/sh
# claude harness — bootstrap (runs ONCE, as root, cwd /workspace, under sh).
# Installs the Claude Code binary and stamps the host into the primer. All
# FILE-based config (.claude.json trust file, .claude/settings.json) ships as
# committed real files in this harness dir, copied verbatim into /workspace by
# the dispatcher — there is nothing to generate here. The proxy is ENV-only for
# claude (ANTHROPIC_*), configured in launch.sh.

set -e

# --- install the harness binary ---------------------------------------------
npm install -g --no-fund --no-audit @anthropic-ai/claude-code@latest || true

# --- seed the shared agent primer -------------------------------------------
# Seed the shared agent primer from the repo root (single source of truth).
RAW_BASE="$(echo "${TRIBES_HARNESS_REPO:-https://github.com/tribes-protocol/ai-harness-setup}" | sed 's#//github\.com#//raw.githubusercontent.com#')"
curl -fsSL "$RAW_BASE/main/AGENTS.md" -o /workspace/AGENTS.md 2>/dev/null || true
host="${HOSTNAME:-$(hostname 2>/dev/null || true)}"
[ -n "$host" ] && [ -e /workspace/AGENTS.md ] && sed -i "s|__HOST__|$host|g" /workspace/AGENTS.md
# claude also reads CLAUDE.md — give it the same primer.
[ -e /workspace/AGENTS.md ] && cp /workspace/AGENTS.md /workspace/CLAUDE.md

# --- safety net -------------------------------------------------------------
# Belt-and-suspenders: no file under /workspace may survive with a raw
# __TRIBES_* placeholder. claude config is fully static (no placeholders) and the
# proxy is ENV-only in launch.sh, so this is a no-op guard. AGENTS.md/CLAUDE.md
# only carry __HOST__, so they are not matched.
# NEVER delete *.sh — bootstrap.sh/launch.sh legitimately contain __TRIBES_ in
# their sed patterns/fallbacks; only NON-script files with a raw placeholder are
# broken config and get removed.
grep -rl "__TRIBES_" /workspace 2>/dev/null | while IFS= read -r f; do
  case "$f" in *.sh) ;; *) rm -f "$f" ;; esac
done
