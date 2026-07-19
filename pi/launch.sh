#!/bin/sh
# Pi harness launch — runs on EVERY launch, as root, cwd /root/workspace, sh.
# Pi is fully FILE-based (models.json + settings.json). There is NO env-based
# config to export here, and pi's theme is "light/dark" (its Automatic mode — it
# queries OSC at startup and follows the terminal), so no per-launch theme rewrite
# is needed either. What DOES run every launch is the models.json (re)generation
# below — the one thing that must NOT be baked once at bootstrap.

# --- (re)generate models.json from the LIVE env every boot ------------------
# Two problems this fixes, both from doing it ONCE in bootstrap.sh:
#   1. restore-safety: a PAUSE -> RESTORE re-mints the per-sandbox key — the
#      control plane REVOKES the old TRIBES_API_KEY and injects a fresh one on the
#      boot cmdline, while the restored disk still holds the OLD, now-revoked
#      token. Pi would present a dead key and the proxy 401s. Regenerating with the
#      live cmdline env re-points apiKey at the current token.
#   2. empty-catalog self-heal: the catalog comes from an authenticated GET
#      /models; a first-boot empty/401 fetch would otherwise be BAKED IN forever
#      ("No models available"). Re-fetching every boot lets the next boot recover,
#      and an empty fetch falls back to the single default model (never an empty
#      array) — mirroring opencode/openclaw.
# No-op-equivalent on a cold boot (rewrites identical content); skipped on BYO/unset
# (bootstrap removed models.json, so the -f guard is false; pi uses the user's
# creds). Config paths are $HOME-relative — the dispatcher decides HOME.
CFG="$HOME/.pi/agent/models.json"
if [ -n "$TRIBES_LLM_MODEL" ] && [ -n "$API_BASE_URL" ] && [ -n "$TRIBES_API_KEY" ] && [ -f "$CFG" ]; then
  proxy="${API_BASE_URL}/llm/proxy"
  token="$TRIBES_API_KEY"

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

exec pi
