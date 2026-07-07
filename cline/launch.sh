#!/bin/sh
# Cline harness launch — runs on EVERY launch, as root, cwd /root/workspace, sh.
# Cline's auth is a file the `cline auth` command writes (~/.cline/data/settings/
# providers.json) — there is no committed seed config and no env-based config.

# --- restore-safety: (re-)auth the proxy provider from the LIVE env ---------
# The auth command runs HERE, every launch — not only in bootstrap.sh — so a
# PAUSE -> RESTORE picks up the re-minted TRIBES_API_KEY. The control plane
# REVOKES the old token and injects a fresh TRIBES_API_KEY on the boot cmdline,
# but the restored disk still carries the OLD providers.json token (now revoked ->
# proxy 401); only a live re-auth refreshes it. Idempotent — re-running just
# overwrites the provider file. Skipped on BYO/unset so the user's own creds stand.
if [ -n "$TRIBES_LLM_MODEL" ] && [ -n "$API_BASE_URL" ] && [ -n "$TRIBES_API_KEY" ]; then
  cline auth openai-compatible \
    --apikey "$TRIBES_API_KEY" \
    --baseurl "${API_BASE_URL}/llm/proxy" \
    --modelid "$TRIBES_LLM_MODEL" >/dev/null 2>&1 || true
fi

# -i opens the interactive TUI; --auto-approve true runs without prompting (the
# VM is the security boundary).
exec cline -i --auto-approve true
