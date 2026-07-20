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
# Identity block (email/EVM/SOL) — same substitution as __HOST__ above; "none"
# when this boot has no bound agent_identities row (composeSandboxBootEnv omits
# the env var for a non-identity box).
email="${TRIBES_IDENTITY_EMAIL:-none}"
evm="${TRIBES_IDENTITY_EVM_ADDRESS:-none}"
sol="${TRIBES_IDENTITY_SOL_ADDRESS:-none}"
[ -e /root/workspace/AGENTS.md ] && sed -i "s|__EMAIL__|$email|g; s|__EVM__|$evm|g; s|__SOL__|$sol|g" /root/workspace/AGENTS.md

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
