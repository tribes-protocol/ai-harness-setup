#!/bin/sh
# Codex harness bootstrap — runs ONCE on first boot, as root, cwd /workspace, sh.
# Installs the Codex CLI and fills the committed seed config (.codex/config.toml)
# with the runtime proxy + model. Env-based config (OPENAI_API_KEY) is set in
# launch.sh, because exports from this process are lost before the harness launches.
set -e

# --- install ----------------------------------------------------------------
command -v codex >/dev/null 2>&1 ||
  npm install -g --no-fund --no-audit @openai/codex@latest

# --- AGENTS.md: substitute the VM's public host -----------------------------
# Codex reads AGENTS.md; replace the __HOST__ placeholder with this VM's host.
[ -n "$HOSTNAME" ] && [ -e /workspace/AGENTS.md ] &&
  sed -i "s/__HOST__/$HOSTNAME/g" /workspace/AGENTS.md || true

# --- proxy-routed config ----------------------------------------------------
# Fill the committed seed .codex/config.toml placeholders with the live proxy
# base + model. The custom provider reads OPENAI_API_KEY (set in launch.sh) as
# the Bearer token. Skip gracefully if the proxy env is absent — the CLI then
# falls back to whatever creds the user supplies, leaving the placeholders be.
if [ -n "$TRIBES_LLM_MODEL" ] && [ -n "$API_BASE_URL" ] && [ -n "$TRIBES_API_KEY" ]; then
  sed -i "s|__TRIBES_PROXY__|${API_BASE_URL}/llm/proxy|g" /workspace/.codex/config.toml
  sed -i "s|__TRIBES_MODEL__|$TRIBES_LLM_MODEL|g" /workspace/.codex/config.toml
else
  # No proxy env (BYO key) — never leave raw placeholders on disk. Drop the seed
  # entirely; codex then uses its own provider/creds, and the launch flag
  # --dangerously-bypass-approvals-and-sandbox covers approvals.
  rm -f /workspace/.codex/config.toml
fi

# --- safety net -------------------------------------------------------------
# Belt-and-suspenders: no file under /workspace may survive with a raw
# __TRIBES_* placeholder (broken/invalid config). AGENTS.md only carries
# __HOST__, so it is not matched.
grep -rlZ "__TRIBES_" /workspace 2>/dev/null | xargs -0 rm -f 2>/dev/null || true
