#!/bin/sh
# opencode harness launch — runs on EVERY launch, as root, cwd /root/workspace, sh.
# opencode config is entirely FILE-based (opencode.json, written by bootstrap.sh)
# — there is no env-based config, and theme:"system" makes the TUI follow the
# terminal, so there is no per-launch theme rewrite and nothing to export here.

# --- restore-safety: refresh the proxy token from the LIVE env --------------
# The bearer is a short-lived ES256 JWT minted in-VM by tribes-agent-token (signed
# with the P-256 agent key). bootstrap.sh baked one into opencode.json (apiKey) on
# first boot; it goes stale (expiry, or a PAUSE -> RESTORE onto a disk holding the
# previous boot's token), so re-mint and re-point the on-disk apiKey every launch.
# Match the apiKey field value so the swap works for any prior token (a JWT has no
# sed-special chars). No-op on a cold boot; skipped on a keyless BYO/unset box
# (file removed, or no mintable key). Config paths are $HOME-relative — the
# dispatcher decides HOME (old: workspace, new: /root).
CFG="$HOME/.config/opencode/opencode.json"
token="$(tribes-agent-token 2>/dev/null || true)"
if [ -n "$token" ] && [ -f "$CFG" ]; then
  sed -i "s|\"apiKey\": \"[^\"]*\"|\"apiKey\": \"$token\"|" "$CFG"
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

exec opencode
