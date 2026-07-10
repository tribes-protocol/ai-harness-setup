#!/bin/sh
# Codex harness launch — runs on EVERY launch, as root, cwd /root/workspace, sh.
# Exports the env-based config that config.toml's env_key reads, then execs the
# harness with its yolo flag (--dangerously-bypass-approvals-and-sandbox = never
# ask, never sandbox; the VM is the security boundary).

# config.toml's [model_providers.tribes] reads OPENAI_API_KEY as the Bearer
# token. Only export when present so an unset proxy key lets Codex fall back to
# the user's own credentials.
[ -n "$TRIBES_API_KEY" ] && export OPENAI_API_KEY="$TRIBES_API_KEY"

# --- shared agent skills: refresh to the latest published set every launch ---
# This is the mechanism that makes template-based sandboxes pick up newly
# published skills without any repo change. Tolerant + tight timeout; a slow or
# failed fetch leaves the launch (and any prior install) unaffected.
SKILLS_RAW_BASE="$(echo "${TRIBES_HARNESS_REPO:-https://github.com/tribes-protocol/ai-harness-setup}" | sed 's#//github\.com#//raw.githubusercontent.com#')"
curl -fsSL --max-time 10 "$SKILLS_RAW_BASE/${TRIBES_HARNESS_REF:-main}/install-skills.sh" | sh || true

exec codex --dangerously-bypass-approvals-and-sandbox
