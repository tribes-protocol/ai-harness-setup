#!/bin/sh
# grok harness — launch (runs on EVERY launch, as root, cwd /root/workspace, under sh).
# Rewrites the SEED config's theme from the create-time TRIBES_THEME, exports the
# ENV-based proxy config (GROK_*), waits (bounded) for egress, then execs grok.

# --- theme (per-launch FILE config) -----------------------------------------
# Grok (xAI, ratatui) has NO OSC/auto theme detection — it hard-defaults to dark
# (GrokNight) and only reads its theme from .grok/config.toml [ui] theme. The
# placeholder was already filled to a CONCRETE theme in bootstrap.sh; here we
# re-sed the live theme line in place on every launch so a theme toggle takes
# effect on relaunch. The regex matches the `theme = "..."` line generically, so
# it works on any prior value (concrete or, defensively, an unfilled placeholder).
# We do NOT touch the tty: an OSC-11 probe right before exec wedged grok's pager
# so it never painted its first frame.
# Prefer the LIVE theme the in-VM bridge writes to /run/tribes-theme on every
# browser theme frame (so a mid-session light/dark TOGGLE takes effect on the next
# grok launch); fall back to the create-time TRIBES_THEME when that file is absent.
# Config paths are $HOME-relative — the dispatcher decides HOME (old: workspace,
# new: /root).
theme="$(cat /run/tribes-theme 2>/dev/null)"
[ "$theme" = light ] || [ "$theme" = dark ] || theme=$([ "$TRIBES_THEME" = light ] && echo light || echo dark)
mkdir -p "$HOME/.grok"
[ -e "$HOME/.grok/config.toml" ] || printf '[ui]\ntheme = "__TRIBES_THEME__"\n' > "$HOME/.grok/config.toml"
sed -i "s|theme = \"[^\"]*\"|theme = \"$theme\"|" "$HOME/.grok/config.toml"

# --- proxy (ENV-only for grok) ----------------------------------------------
# grok CLI → OpenAI chat surface via its base-url override. An existing session
# beats the key, so log out first. Under `setsid -w` (own session, no controlling
# tty) so the grok binary can't grab/leave the pty's foreground group
# backgrounded; -w waits so creds are cleared before grok starts.
if [ -n "$TRIBES_LLM_MODEL" ] && [ -n "$API_BASE_URL" ] && [ -n "$TRIBES_API_KEY" ]; then
  export GROK_MODELS_BASE_URL="${API_BASE_URL}/llm/proxy"
  export GROK_CODE_XAI_API_KEY="$TRIBES_API_KEY"
  setsid -w grok logout </dev/null >/dev/null 2>&1 || true
fi

# --- bounded egress wait ----------------------------------------------------
# grok's startup BLOCKS its first paint on a model-catalog fetch to api.x.ai over
# IPv6, fired ~3s after boot. On a COLD boot, egress (host ND/routing for the
# routed prefix) can lag the eager-spawn, so that SYN is silently dropped and
# connect() hangs on SYN-retransmit for minutes — grok sits at "Starting grok..."
# forever. Wait — bounded — for egress to api.x.ai before launching, so the fetch
# returns fast (RST/HTTP) instead of hanging. curl returning at all proves the TCP
# path is alive; 30s cap so a truly offline VM still launches.
for _ in $(seq 1 30); do
  curl -s -o /dev/null --max-time 2 https://api.x.ai/ 2>/dev/null && break
  sleep 1
done

# --- shared agent skills: refresh to the latest published set every launch ---
# This is the mechanism that makes template-based sandboxes pick up newly
# published skills without any repo change. Tolerant + tight timeout; a slow or
# failed fetch leaves the launch (and any prior install) unaffected.
SKILLS_RAW_BASE="$(echo "${TRIBES_HARNESS_REPO:-https://github.com/tribes-protocol/ai-harness-setup}" | sed 's#//github\.com#//raw.githubusercontent.com#')"
curl -fsSL --max-time 10 "$SKILLS_RAW_BASE/${TRIBES_HARNESS_REF:-main}/install-skills.sh" | sh || true

# --- launch -----------------------------------------------------------------
# --always-approve disables per-tool approval prompts (no trust gate exists in
# the official xAI CLI) — the microVM is the security boundary.
# --- proxy-routed but NO credential: fail LOUD, don't boot silently broken ----
# The proxy guard above skips config when TRIBES_API_KEY is empty — correct for a
# BYO box (all three env vars unset). But a box the control plane marked
# proxy-routed (TRIBES_LLM_MODEL + API_BASE_URL present) that arrives with an
# EMPTY TRIBES_API_KEY is a FAILED credential mint, not BYO: it boots, every LLM
# call 401s (totalTokens:0), and every other vantage reads green. Surface it — a
# loud boot-log line AND a health marker the fleet can poll — so "booted with no
# proxy auth" is no longer silent. Cleared on any healthy/BYO boot so the marker
# is a LIVE signal (self-heals on a restore that re-mints the key). (#2472)
if [ -n "$TRIBES_LLM_MODEL" ] && [ -n "$API_BASE_URL" ] && [ -z "$TRIBES_API_KEY" ]; then
  echo "[llm-proxy] proxy-routed but TRIBES_API_KEY is EMPTY this boot — no VALID proxy credential; every LLM call will 401 (mint failed; any on-disk key is stale/revoked)." >&2
  mkdir -p /opt/tribes 2>/dev/null || true
  : > /opt/tribes/.llm-proxy-auth-missing 2>/dev/null || true
else
  rm -f /opt/tribes/.llm-proxy-auth-missing 2>/dev/null || true
fi

exec grok --always-approve
