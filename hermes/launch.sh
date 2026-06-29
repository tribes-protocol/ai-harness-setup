#!/bin/sh
# Hermes harness launch — runs on EVERY launch, as root, cwd /workspace, sh.
# Hermes is fully FILE-based (config.yaml), so there is NO env-based config to
# export here. We re-sed the display.skin line from the CURRENT theme so a
# TRIBES_THEME toggle takes effect on relaunch. The ^  skin: anchor matches both
# the initial __TRIBES_SKIN__ placeholder and a previously-set value, so relaunch
# toggles work. Then exec hermes with --yolo (bypasses dangerous-command
# approvals; the microVM is the security boundary).
# The ^  skin: line is present in BOTH configs bootstrap.sh can produce: the full
# proxy config and the BYO skin-only config (display block only). Guard on [ -f ]
# anyway so a missing file never makes sed -i create/break one.
if [ -f /workspace/.hermes/config.yaml ]; then
  skin=$([ "$TRIBES_THEME" = light ] && echo daylight || echo default)
  sed -i "s|^  skin:.*|  skin: $skin|" /workspace/.hermes/config.yaml
fi

# --- restore-safety: refresh the proxy token from the LIVE env --------------
# bootstrap.sh baked TRIBES_API_KEY (api_key) into config.yaml ONCE, on first
# boot. A PAUSE -> RESTORE re-mints the per-sandbox key (the old token is REVOKED
# and a fresh TRIBES_API_KEY rides the boot cmdline), but the restored disk still
# holds the OLD, now-revoked token — so hermes would 401 against the proxy.
# launch.sh runs EVERY boot with the live env, so re-point the on-disk api_key at
# the current token here. No-op on a cold boot; skipped on BYO/unset.
if [ -n "$TRIBES_API_KEY" ] && [ -f /workspace/.hermes/config.yaml ]; then
  sed -i "s|tribes_sb_[0-9A-Za-z]*|$TRIBES_API_KEY|g" /workspace/.hermes/config.yaml
fi

# --- seal the venv against banner-time lazy installs ------------------------
# hermes-agent's startup show_banner() -> get_tool_definitions() runs EVERY
# toolset's requirements check_fn, and the TTS check (check_tts_requirements ->
# _import_edge_tts) — plus the browser check — trigger a BLOCKING `pip install`
# of optional deps (edge-tts, Playwright Chromium) on EVERY launch. They never
# persist in this rootfs, so each relaunch re-attempts the slow install, which
# floods/stalls startup and breaks the exit->bash->relaunch cycle (the dropped
# bash can't hold while the relaunched hermes is mid-install). This env var is
# hermes-agent's own opt-out (the upstream Docker image sets it): the checks then
# report the tool "unavailable" instead of installing, so hermes boots instantly.
# Core LLM chat + its tools are unaffected; only optional audio/browser tools that
# need extra runtime deps are skipped — fine for a microVM agent.
export HERMES_DISABLE_LAZY_INSTALLS=1

exec hermes --yolo
