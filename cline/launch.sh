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
# --- re-render the agent primer (restore-safety, like the token refresh) -----
# bootstrap.sh's sed CONSUMED the primer placeholders, freezing whatever the box
# knew at first boot: the boot-slug hostname (a claim adds a DNS alias and never
# renames the VM) and "none" identity values if the agent_identities row wasn't
# bound yet. AGENTS.md is auto-loaded into the agent's context, so a frozen primer
# feeds it a WRONG public URL by default. Re-render from the untouched template
# with this launch's live env so both self-heal and survive restore.
sh /opt/tribes/render-primer.sh 2>/dev/null || true

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

# -i opens the interactive TUI; --auto-approve true runs without prompting (the
# VM is the security boundary).
exec cline -i --auto-approve true
