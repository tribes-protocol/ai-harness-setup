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
# bin dir (pinned to /root/workspace at install time, regardless of the
# dispatcher's HOME) on PATH too as a fallback.
export PATH="/root/workspace/.local/bin:$PATH"

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

exec agent
