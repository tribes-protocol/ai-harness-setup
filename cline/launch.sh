#!/bin/sh
# Cline harness launch — runs on EVERY launch, as root, cwd /root/workspace, sh.
# Cline's auth is a file the `cline auth` command writes (~/.cline/data/settings/
# providers.json) — there is no committed seed config and no env-based config.

# --- restore-safety: (re-)auth the proxy provider from the LIVE env ---------
# The auth command runs HERE, every launch — not only in bootstrap.sh — so each
# boot re-auths with a freshly-minted bearer. The bearer is a short-lived ES256
# JWT minted in-VM by tribes-agent-token (signed with the P-256 agent key); a
# restored disk still carries the OLD providers.json token (now stale -> proxy
# 401), so only a live re-auth refreshes it. Idempotent — re-running just
# overwrites the provider file. Skipped on a keyless BYO/unset box so the user's own creds stand.
token="$(tribes-agent-token 2>/dev/null || true)"
if [ -n "$TRIBES_LLM_MODEL" ] && [ -n "$API_BASE_URL" ] && [ -n "$token" ]; then
  cline auth openai-compatible \
    --apikey "$token" \
    --baseurl "${API_BASE_URL}/llm/proxy" \
    --modelid "$TRIBES_LLM_MODEL" >/dev/null 2>&1 || true
fi

# --- shared agent skills: refresh to the latest published set every launch ---
# This is the mechanism that makes template-based sandboxes pick up newly
# published skills without any repo change. Tolerant + tight timeout; a slow or
# failed fetch leaves the launch (and any prior install) unaffected.
SKILLS_RAW_BASE="$(echo "${TRIBES_HARNESS_REPO:-https://github.com/tribes-protocol/ai-harness-setup}" | sed 's#//github\.com#//raw.githubusercontent.com#')"
curl -fsSL --max-time 10 "$SKILLS_RAW_BASE/${TRIBES_HARNESS_REF:-main}/install-skills.sh" | sh || true

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

# -i opens the interactive TUI; --auto-approve true runs without prompting (the
# VM is the security boundary).
exec cline -i --auto-approve true
