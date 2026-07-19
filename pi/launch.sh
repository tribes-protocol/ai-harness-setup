#!/bin/sh
# Pi harness launch — runs on EVERY launch, as root, cwd /root/workspace, sh.
# Pi is fully FILE-based (models.json + settings.json). There is NO env-based
# config to export here, and pi's theme is "light/dark" (its Automatic mode — it
# queries OSC at startup and follows the terminal), so no per-launch theme rewrite
# is needed either. What DOES run every launch is the models.json (re)generation
# below — the one thing that must NOT be baked once at bootstrap.

# --- (re)generate models.json from the LIVE env every boot ------------------
# Two problems this fixes, both from doing it ONCE in bootstrap.sh:
#   1. token freshness: the bearer is a short-lived ES256 JWT minted in-VM by
#      tribes-agent-token (signed with the P-256 agent key). Re-minting every launch
#      keeps the on-disk apiKey a live, unexpired token — including after a PAUSE ->
#      RESTORE, where the disk still holds the previous boot's now-stale JWT.
#   2. empty-catalog self-heal: the catalog comes from an authenticated GET
#      /models; a first-boot empty/401 fetch would otherwise be BAKED IN forever
#      ("No models available"). Re-fetching every boot lets the next boot recover,
#      and an empty fetch falls back to the single default model (never an empty
#      array) — mirroring opencode/openclaw.
# No-op-equivalent on a cold boot (rewrites identical content); skipped on BYO/unset
# (bootstrap removed models.json, so the -f guard is false; pi uses the user's
# creds). Config paths are $HOME-relative — the dispatcher decides HOME.
CFG="$HOME/.pi/agent/models.json"
token="$(tribes-agent-token 2>/dev/null || true)"
if [ -n "$TRIBES_LLM_MODEL" ] && [ -n "$API_BASE_URL" ] && [ -n "$token" ] && [ -f "$CFG" ]; then
  proxy="${API_BASE_URL}/llm/proxy"

  # Live catalog → the array CONTENTS for "models": [ ... ]. Fall back to the
  # single default model on an empty/failed fetch — NEVER an empty array.
  pi_models=$(curl -s --max-time 10 "$proxy/models" -H "Authorization: Bearer $token" 2>/dev/null \
    | grep -oE '"id":[[:space:]]*"[^"]+"' \
    | sed -E 's/.*"([^"]+)"$/{ "id": "\1" }/' | paste -sd, -)
  [ -n "$pi_models" ] || pi_models="{ \"id\": \"$TRIBES_LLM_MODEL\" }"

  # Write atomically. printf only interprets the format string, so proxy/token/
  # model values (which contain '/', braces, quotes) are inserted verbatim and the
  # JSON stays valid.
  printf '{ "providers": { "tribes-llm-proxy": { "baseUrl": "%s", "api": "openai-completions", "apiKey": "%s", "models": [%s] } } }\n' \
    "$proxy" "$token" "$pi_models" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
fi

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

exec pi
