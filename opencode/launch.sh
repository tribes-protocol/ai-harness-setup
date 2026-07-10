#!/bin/sh
# opencode harness launch — runs on EVERY launch, as root, cwd /root/workspace, sh.
# opencode config is entirely FILE-based (opencode.json, written by bootstrap.sh)
# — there is no env-based config, and theme:"system" makes the TUI follow the
# terminal, so there is no per-launch theme rewrite and nothing to export here.

# --- restore-safety: refresh the proxy token from the LIVE env --------------
# bootstrap.sh baked TRIBES_API_KEY into opencode.json ONCE, on first boot. A
# PAUSE -> RESTORE re-mints the per-sandbox key (the old token is REVOKED and a
# fresh TRIBES_API_KEY rides the boot cmdline), but the restored disk still holds
# the OLD, now-revoked token — so opencode would 401 against the proxy. launch.sh
# runs EVERY boot with the live env, so re-point the on-disk apiKey at the current
# token here. No-op on a cold boot; skipped on BYO/unset (file removed, or no key).
# Config paths are $HOME-relative — the dispatcher decides HOME (old: workspace,
# new: /root).
CFG="$HOME/.config/opencode/opencode.json"
if [ -n "$TRIBES_API_KEY" ] && [ -f "$CFG" ]; then
  sed -i "s|tribes_sb_[0-9A-Za-z]*|$TRIBES_API_KEY|g" "$CFG"
fi

# --- shared agent skills: refresh to the latest published set every launch ---
# This is the mechanism that makes template-based sandboxes pick up newly
# published skills without any repo change. Tolerant + tight timeout; a slow or
# failed fetch leaves the launch (and any prior install) unaffected.
SKILLS_RAW_BASE="$(echo "${TRIBES_HARNESS_REPO:-https://github.com/tribes-protocol/ai-harness-setup}" | sed 's#//github\.com#//raw.githubusercontent.com#')"
curl -fsSL --max-time 10 "$SKILLS_RAW_BASE/${TRIBES_HARNESS_REF:-main}/install-skills.sh" | sh || true

exec opencode
