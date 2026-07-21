#!/bin/sh
# Codex harness launch — runs on EVERY launch, as root, cwd /root/workspace, sh.
# Exports the env-based config that config.toml's env_key reads, then execs the
# harness with its yolo flag (--dangerously-bypass-approvals-and-sandbox = never
# ask, never sandbox; the VM is the security boundary).

# --- re-render the agent primer (restore-safety, like the token refresh) -----
# bootstrap.sh's sed CONSUMED the primer placeholders, freezing whatever the box
# knew at first boot: the boot-slug hostname (a claim adds a DNS alias and never
# renames the VM) and "none" identity values if the agent_identities row wasn't
# bound yet. AGENTS.md is auto-loaded into the agent's context, so a frozen primer
# feeds it a WRONG public URL by default. Re-render from the untouched template
# with this launch's live env so both self-heal and survive restore.
if [ -e /opt/tribes/render-primer.sh ]; then
  sh /opt/tribes/render-primer.sh ||
    echo "[primer] render-primer.sh FAILED — primer may be stale" >&2
else
  # Loud on purpose: `2>/dev/null || true` here once turned "my dependency was
  # never installed" into silence, and the primer fix sat INERT on every box
  # through review, a Fable pass and four ref moves. A missing renderer means the
  # harness install fetched the wrong ref — say so.
  echo "[primer] /opt/tribes/render-primer.sh MISSING — primer NOT refreshed (harness install incomplete / wrong ref?)" >&2
fi

# config.toml's [model_providers.tribes] reads OPENAI_API_KEY as the Bearer
# token. The bearer is minted in-VM by tribes-agent-token (an ES256 JWT signed
# with the P-256 agent key); export it only when non-empty so a keyless BYO/
# external box lets Codex fall back to the user's own credentials.
token="$(tribes-agent-token 2>/dev/null || true)"
[ -n "$token" ] && export OPENAI_API_KEY="$token"

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

# --- proxy-routed but NO credential: fail LOUD, don't boot silently broken ----
# The proxy guard above skips config when the minted $token is empty — correct for a
# BYO box (all three env vars unset). But a box the control plane marked
# proxy-routed (TRIBES_LLM_MODEL + API_BASE_URL present) that arrives with an
# EMPTY $token (tribes-agent-token minted nothing) is a FAILED credential mint, not BYO: it boots, every LLM
# call 401s (totalTokens:0), and every other vantage reads green. Surface it — a
# loud boot-log line AND a health marker the fleet can poll — so "booted with no
# proxy auth" is no longer silent. Cleared on any healthy/BYO boot so the marker
# is a LIVE signal (self-heals on a restore that re-mints the key). (#2472)
if [ -n "$TRIBES_LLM_MODEL" ] && [ -n "$API_BASE_URL" ] && [ -z "$token" ]; then
  echo "[llm-proxy] proxy-routed but tribes-agent-token minted NO bearer this boot — no VALID proxy credential; every LLM call will 401 (mint failed; any on-disk key is stale/revoked)." >&2
  mkdir -p /opt/tribes 2>/dev/null || true
  : > /opt/tribes/.llm-proxy-auth-missing 2>/dev/null || true
else
  rm -f /opt/tribes/.llm-proxy-auth-missing 2>/dev/null || true
fi

exec codex --dangerously-bypass-approvals-and-sandbox
