#!/bin/sh
# claude harness — launch (runs EVERY launch, as root, cwd /root/workspace, under sh).
# Exports the ENV-based proxy config, then execs the harness. Env exports MUST
# live here (not bootstrap.sh): only this process's env reaches the harness.

# --- proxy-routed: point claude at the metered LLM proxy --------------------
# When the control plane marks claude proxy-routed it injects TRIBES_LLM_MODEL +
# API_BASE_URL + the per-sandbox static API key (TRIBES_API_KEY). Point claude's
# Anthropic Messages surface at `${API_BASE_URL}/llm/proxy`; ANTHROPIC_AUTH_TOKEN
# is sent as the Authorization: Bearer header. If any are absent we skip and
# claude falls back to whatever creds the user supplies.
if [ -n "$TRIBES_LLM_MODEL" ] && [ -n "$API_BASE_URL" ] && [ -n "$TRIBES_API_KEY" ]; then
  proxy="${API_BASE_URL}/llm/proxy"
  export ANTHROPIC_BASE_URL="$proxy"
  export ANTHROPIC_AUTH_TOKEN="$TRIBES_API_KEY"
  # Map each /model tier to a real proxy model (all three allow-listed) so
  # Opus/Sonnet/Haiku are genuine choices, not three aliases of one model. The
  # session default stays the configured model ($TRIBES_LLM_MODEL) to keep cost
  # predictable until the user picks Opus.
  export ANTHROPIC_MODEL="$TRIBES_LLM_MODEL"
  export ANTHROPIC_DEFAULT_OPUS_MODEL="claude-opus"
  export ANTHROPIC_DEFAULT_SONNET_MODEL="claude-sonnet"
  export ANTHROPIC_DEFAULT_HAIKU_MODEL="claude-haiku"
fi

# IS_SANDBOX=1 lets --dangerously-skip-permissions run as root.
exec env IS_SANDBOX=1 claude --dangerously-skip-permissions
