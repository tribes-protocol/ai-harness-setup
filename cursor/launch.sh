#!/bin/sh
# cursor harness — launch (runs on EVERY launch, as root, cwd /root/workspace, under sh).
# Cursor cannot be pointed at the metered LLM proxy (no base-URL override), so
# auth is the user's OWN Cursor account: `/login` in the TUI, or CURSOR_API_KEY
# if the env carries one — we pass the inherited env through untouched. No
# tribes token lives in any file, so there is no per-launch token refresh.

# No browser exists in the VM — make `agent login` PRINT its auth URL instead
# of trying to open one, so the user completes OAuth on their own machine.
export NO_OPEN_BROWSER=1

# bootstrap.sh symlinked the binary to /usr/local/bin; keep the installer's own
# bin dir (HOME is /root/workspace) on PATH too as a fallback.
export PATH="/root/workspace/.local/bin:$PATH"

exec agent
