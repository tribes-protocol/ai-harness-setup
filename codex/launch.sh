#!/bin/sh
# Codex harness launch — runs on EVERY launch, as root, cwd /root/workspace, sh.
# Exports the env-based config that config.toml's env_key reads, then execs the
# harness with its yolo flag (--dangerously-bypass-approvals-and-sandbox = never
# ask, never sandbox; the VM is the security boundary).

# config.toml's [model_providers.tribes] reads OPENAI_API_KEY as the Bearer
# token. Only export when present so an unset proxy key lets Codex fall back to
# the user's own credentials.
[ -n "$TRIBES_API_KEY" ] && export OPENAI_API_KEY="$TRIBES_API_KEY"

exec codex --dangerously-bypass-approvals-and-sandbox
