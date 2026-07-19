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
# grok CLI → OpenAI chat surface via its base-url override. The bearer is minted
# in-VM by tribes-agent-token (an ES256 JWT signed with the P-256 agent key); it is
# empty on a keyless BYO/external box, so grok then falls back to the user's own
# xAI account. An existing session beats the key, so log out first. Under
# `setsid -w` (own session, no controlling tty) so the grok binary can't grab/leave
# the pty's foreground group backgrounded; -w waits so creds are cleared before grok starts.
token="$(tribes-agent-token 2>/dev/null || true)"
if [ -n "$TRIBES_LLM_MODEL" ] && [ -n "$API_BASE_URL" ] && [ -n "$token" ]; then
  export GROK_MODELS_BASE_URL="${API_BASE_URL}/llm/proxy"
  export GROK_CODE_XAI_API_KEY="$token"
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

# --- shared agent skills: reconverge on every launch -------------------------
# Drive-first (#1914): run the installer baked onto the shared read-only
# /opt/harnesses drive, so every launch reconverges /root/skills on the drive's
# pinned catalog with no network. The fetch survives as the fallback for a
# drive that predates skills (old image, dev backend) and for a pinned
# TRIBES_HARNESS_REF (QA), which must exercise that branch's own installer.
# Tolerant + tight timeout; a slow or failed fetch leaves the launch (and any
# prior install) unaffected.
if [ -z "${TRIBES_HARNESS_REF:-}" ] && [ -f /opt/harnesses/skills/install-skills.sh ]; then
  sh /opt/harnesses/skills/install-skills.sh || true
else
  SKILLS_RAW_BASE="$(echo "${TRIBES_HARNESS_REPO:-https://github.com/tribes-protocol/ai-harness-setup}" | sed 's#//github\.com#//raw.githubusercontent.com#')"
  curl -fsSL --max-time 10 "$SKILLS_RAW_BASE/${TRIBES_HARNESS_REF:-main}/install-skills.sh" | sh || true
fi

# --- close the direct-provider escape hatch (#2255) --------------------------
# On a proxy-routed box the control plane injects a PLACEHOLDER OPENROUTER_API_KEY
# (SandboxBootEnv.ts) intended for an egress injector that swaps in the real key.
# On zipbox no such injector is on this path, so the placeholder is just a stray
# credential-shaped env var: harnesses that auto-register a provider on env
# presence alone (pi, opencode) can pick OpenRouter DIRECTLY and 401 against
# openrouter.ai instead of using the metered proxy. Dropping it before exec leaves
# the metered proxy as the only route the harness can see.
#
# We do NOT set HTTP_PROXY/HTTPS_PROXY: the forwarder catalog is a CONNECT
# allowlist that 403s every non-catalog authority, so a blanket proxy would break
# github/npm/apt/pypi on every box.
#
# The unset is deliberately guard-scoped, NOT value-scoped (i.e. not "unset only
# if it looks like the placeholder"). Value-matching would couple this script to a
# literal defined in another repo's catalog — a silent no-op the day that value
# changes — and, worse, it would PRESERVE a real OpenRouter key that reached a
# proxy-routed box some other way, which is exactly the unmetered bypass this
# closes. byoKey is the supported way to bring your own key, and it is suppressed
# by the guard below.
#
# The guard is the by-construction one: SandboxBootEnv writes TRIBES_LLM_MODEL
# ONLY for proxy-mode, non-byoKey, non-'external' boxes, so BYO/external boxes
# never enter this branch and keep their own OPENROUTER_API_KEY untouched. This is
# structural, not a special case — do not add a byoKey conditional here.
if [ -n "${TRIBES_LLM_MODEL:-}" ] && [ -n "${API_BASE_URL:-}" ]; then
  unset OPENROUTER_API_KEY
fi

# --- launch -----------------------------------------------------------------
# --always-approve disables per-tool approval prompts (no trust gate exists in
# the official xAI CLI) — the microVM is the security boundary.
exec grok --always-approve
