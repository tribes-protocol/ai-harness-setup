#!/bin/sh
# claude harness — launch (runs EVERY launch, as root, cwd /root/workspace, under sh).
# Exports the ENV-based proxy config for the auto-launched harness process, then
# refreshes the SAME live token into settings.json's "env" block so a manually
# typed `claude` in the exit shell — a separate process that never sees these
# exports, which die with this process once we exec — is authenticated too.
# Config paths are $HOME-relative — the dispatcher decides HOME (old: workspace,
# new: /root).

# --- proxy-routed: point claude at the metered LLM proxy --------------------
# When the control plane marks claude proxy-routed it injects TRIBES_LLM_MODEL +
# API_BASE_URL + the per-sandbox static API key (TRIBES_API_KEY). Point claude's
# Anthropic Messages surface at `${API_BASE_URL}/llm/proxy`; ANTHROPIC_AUTH_TOKEN
# is sent as the Authorization: Bearer header. If any are absent we skip and
# claude falls back to whatever creds the user supplies. Kept even though
# settings.json's env block (below) covers the same values: it's what actually
# authenticates the launched harness if the on-disk config was ever left
# mid-edit (bootstrap fill failure) or a BYO box flips to proxy-routed on a
# restore (bootstrap already ran once and won't re-seed the placeholders).
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

# --- restore-safety: refresh the on-disk token (manual/exit-shell auth) ----
# TRIBES_API_KEY is re-minted on every restore (the old one is revoked), so the
# token baked into settings.json at bootstrap goes stale. Re-point it at the
# live key on every launch — same idiom as the other file-based harnesses (see
# CONTRACT.md). No-op on a cold boot (bootstrap just wrote this same value);
# skipped entirely on BYO/unset (bootstrap.sh already stripped the env block).
CFG="$HOME/.claude/settings.json"
if [ -n "$TRIBES_API_KEY" ] && [ -f "$CFG" ]; then
  sed -i "s|tribes_sb_[0-9A-Za-z]*|$TRIBES_API_KEY|g" "$CFG"
fi

# IS_SANDBOX=1 lets --dangerously-skip-permissions run as root.
exec env IS_SANDBOX=1 claude --dangerously-skip-permissions
