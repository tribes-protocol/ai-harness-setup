#!/bin/sh
# Pi harness launch — runs on EVERY launch, as root, cwd /workspace, sh.
# Pi is fully FILE-based (bootstrap.sh wrote models.json + settings.json), so
# there is NO env-based config to export here. Pi's theme is "light/dark" (its
# Automatic mode — it queries OSC at startup and follows the terminal's
# light/dark), so no per-launch theme rewrite is needed either.

# --- restore-safety: refresh the proxy token from the LIVE env --------------
# bootstrap.sh baked TRIBES_API_KEY into models.json ONCE, on first boot. But a
# PAUSE -> RESTORE re-mints the per-sandbox key: the control plane REVOKES the old
# token and injects a fresh TRIBES_API_KEY on the boot cmdline, while the restored
# disk still carries the OLD, now-revoked token. Pi would then present a dead key
# and the proxy 401s ("lost LLM key"). launch.sh runs EVERY boot with the live
# cmdline env, so re-point the on-disk apiKey at the current token here. No-op on a
# cold boot (already current); skipped on BYO/unset (file removed, or no key).
CFG=/workspace/.pi/agent/models.json
if [ -n "$TRIBES_API_KEY" ] && [ -f "$CFG" ]; then
  sed -i "s|tribes_sb_[0-9A-Za-z]*|$TRIBES_API_KEY|g" "$CFG"
fi

exec pi
