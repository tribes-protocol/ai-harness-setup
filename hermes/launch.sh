#!/bin/sh
# Hermes harness launch — runs on EVERY launch, as root, cwd /root/workspace, sh.
# Hermes is fully FILE-based (config.yaml), so there is NO env-based config to
# export here. We re-sed the display.skin line from the CURRENT theme so a
# TRIBES_THEME toggle takes effect on relaunch. The ^  skin: anchor matches both
# the initial __TRIBES_SKIN__ placeholder and a previously-set value, so relaunch
# toggles work. Then exec hermes with --yolo (bypasses dangerous-command
# approvals; the microVM is the security boundary).
# The ^  skin: line is present in BOTH configs bootstrap.sh can produce: the full
# proxy config and the BYO skin-only config (display block only). Guard on [ -f ]
# anyway so a missing file never makes sed -i create/break one.
# Config paths are $HOME-relative — the dispatcher decides HOME (old: workspace,
# new: /root).
if [ -f "$HOME/.hermes/config.yaml" ]; then
  skin=$([ "$TRIBES_THEME" = light ] && echo daylight || echo default)
  sed -i "s|^  skin:.*|  skin: $skin|" "$HOME/.hermes/config.yaml"
fi

# --- restore-safety: refresh the proxy token from the LIVE env --------------
# bootstrap.sh baked TRIBES_API_KEY (api_key) into config.yaml ONCE, on first
# boot. A PAUSE -> RESTORE re-mints the per-sandbox key (the old token is REVOKED
# and a fresh TRIBES_API_KEY rides the boot cmdline), but the restored disk still
# holds the OLD, now-revoked token — so hermes would 401 against the proxy.
# launch.sh runs EVERY boot with the live env, so re-point the on-disk api_key at
# the current token here. No-op on a cold boot; skipped on BYO/unset.
if [ -n "$TRIBES_API_KEY" ] && [ -f "$HOME/.hermes/config.yaml" ]; then
  sed -i "s|tribes_sb_[0-9A-Za-z]*|$TRIBES_API_KEY|g" "$HOME/.hermes/config.yaml"
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

# --- BYO onboarding: land on the setup wizard, not a bare [Y/n] prompt -------
# In BYO mode (no proxy env) bootstrap.sh wrote a skin-only config — hermes has
# no provider/key, and `hermes --yolo` parks on a plain "Hermes isn't configured
# yet ... Run setup now? [Y/n]" text line. Launch `hermes setup` DIRECTLY on the
# first BYO boot so the user lands in real onboarding (Nous OAuth quick setup /
# bring-your-own-keys). The /opt/tribes marker keeps a user who backs out from
# being re-trapped on every relaunch (they can rerun `hermes setup` anytime),
# and a completed setup writes providers into config.yaml, which also skips.
if [ -z "$TRIBES_API_KEY" ] \
   && ! grep -q '^providers:' "$HOME/.hermes/config.yaml" 2>/dev/null \
   && [ ! -e /opt/tribes/.hermes-setup-offered ]; then
  mkdir -p /opt/tribes && : > /opt/tribes/.hermes-setup-offered
  hermes setup || true
fi

exec hermes --yolo
