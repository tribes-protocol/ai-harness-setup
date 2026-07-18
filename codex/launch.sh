#!/bin/sh
# Codex harness launch — runs on EVERY launch, as root, cwd /root/workspace, sh.
# Exports the env-based config that config.toml's env_key reads, then execs the
# harness with its yolo flag (--dangerously-bypass-approvals-and-sandbox = never
# ask, never sandbox; the VM is the security boundary).

# config.toml's [model_providers.tribes] reads OPENAI_API_KEY as the Bearer
# token. The bearer is minted in-VM by tribes-agent-token (an ES256 JWT signed
# with the P-256 agent key); export it only when non-empty so a keyless BYO/
# external box lets Codex fall back to the user's own credentials.
# --- re-render the agent primer (restore-safety, like the token refresh) -----
# bootstrap.sh's sed CONSUMED the primer placeholders, freezing whatever the box
# knew at first boot: the boot-slug hostname (a claim adds a DNS alias and never
# renames the VM) and "none" identity values if the agent_identities row wasn't
# bound yet. AGENTS.md is auto-loaded into the agent's context, so a frozen primer
# feeds it a WRONG public URL by default. Re-render from the untouched template
# with this launch's live env so both self-heal and survive restore.
sh /opt/tribes/render-primer.sh 2>/dev/null || true

token="$(tribes-agent-token 2>/dev/null || true)"
[ -n "$token" ] && export OPENAI_API_KEY="$token"

# --- shared agent skills: refresh to the latest published set every launch ---
# This is the mechanism that makes template-based sandboxes pick up newly
# published skills without any repo change. Tolerant + tight timeout; a slow or
# failed fetch leaves the launch (and any prior install) unaffected.
SKILLS_RAW_BASE="$(echo "${TRIBES_HARNESS_REPO:-https://github.com/tribes-protocol/ai-harness-setup}" | sed 's#//github\.com#//raw.githubusercontent.com#')"
curl -fsSL --max-time 10 "$SKILLS_RAW_BASE/${TRIBES_HARNESS_REF:-main}/install-skills.sh" | sh || true

exec codex --dangerously-bypass-approvals-and-sandbox
