#!/bin/sh
# Cline harness bootstrap — runs ONCE on first boot, as root, cwd /workspace, sh.
#
# WHY NO COMMITTED SEED CONFIG (cline is the contract's documented exception):
# Every other harness commits a real, version-controlled config file with
# __TRIBES_*__ placeholders that bootstrap.sh seds. Cline has none — its
# provider config is produced by the `cline auth openai-compatible ...` CLI
# command, which writes cline's OWN provider file (~/.cline/data/settings/
# providers.json) at runtime from the live proxy/token/model. That command
# needs the `cline` binary plus runtime creds, so it is inherently runtime and
# there is no static file to commit (no heredoc to convert to a seed file).
#
# Installs the Cline CLI, then runs that auth command AFTER install. Cline has
# no env-based proxy config — its auth lives entirely in that file — so
# launch.sh exports nothing. Cline also has no theme support (hardcoded palette).
set -e

# --- install ----------------------------------------------------------------
command -v cline >/dev/null 2>&1 ||
  npm install -g --no-fund --no-audit cline@latest

# --- AGENTS.md: substitute the VM's public host -----------------------------
# Cline reads AGENTS.md; replace the __HOST__ placeholder with this VM's host.
[ -n "$HOSTNAME" ] && [ -e /workspace/AGENTS.md ] &&
  sed -i "s/__HOST__/$HOSTNAME/g" /workspace/AGENTS.md || true

# --- proxy-routed config ----------------------------------------------------
# Cline → OpenAI-Compatible provider via its own `cline auth` command (the
# stable interface; it writes ~/.cline/data/settings/providers.json). The
# provider lists the full catalog from the proxy's GET /models; --modelid just
# preselects the default. The bearer is the apikey. Never pin one model here.
# Skip gracefully if the proxy env is absent — the CLI then falls back to
# whatever creds the user supplies.
if [ -n "$TRIBES_LLM_MODEL" ] && [ -n "$API_BASE_URL" ] && [ -n "$TRIBES_API_KEY" ]; then
  proxy="${API_BASE_URL}/llm/proxy"
  token="$TRIBES_API_KEY"
  cline auth openai-compatible \
    --apikey "$token" \
    --baseurl "$proxy" \
    --modelid "$TRIBES_LLM_MODEL" >/dev/null 2>&1 || true
fi

# --- safety net -------------------------------------------------------------
# Belt-and-suspenders: no file under /workspace may survive with a raw
# __TRIBES_* placeholder. cline has no committed seed config (auth is a runtime
# command), so this is a no-op guard. AGENTS.md only carries __HOST__, so it is
# not matched.
grep -rlZ "__TRIBES_" /workspace 2>/dev/null | xargs -0 rm -f 2>/dev/null || true
