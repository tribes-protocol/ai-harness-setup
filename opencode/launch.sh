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

# --- shared agent skills: refresh to the latest published set every launch ---
# This is the mechanism that makes template-based sandboxes pick up newly
# published skills without any repo change. Tolerant + tight timeout; a slow or
# failed fetch leaves the launch (and any prior install) unaffected.
SKILLS_RAW_BASE="$(echo "${TRIBES_HARNESS_REPO:-https://github.com/tribes-protocol/ai-harness-setup}" | sed 's#//github\.com#//raw.githubusercontent.com#')"
curl -fsSL --max-time 10 "$SKILLS_RAW_BASE/${TRIBES_HARNESS_REF:-main}/install-skills.sh" | sh || true

exec opencode
