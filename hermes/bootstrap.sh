#!/bin/sh
# Hermes harness bootstrap — runs ONCE on first boot, as root, cwd /workspace, sh.
# Installs the Hermes CLI, then fills the placeholders in the COMMITTED seed config
# /workspace/.hermes/config.yaml. Hermes is fully FILE-based: it reads
# model/provider/skin from that file, so there is NO env-based config to defer to
# launch.sh. launch.sh re-seds the display.skin line each launch so a theme toggle
# takes effect on relaunch.
set -e

# --- install ----------------------------------------------------------------
command -v hermes >/dev/null 2>&1 ||
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash

# --- AGENTS.md: substitute the VM's public host -----------------------------
# Hermes reads AGENTS.md; replace the __HOST__ placeholder with this VM's host.
[ -n "$HOSTNAME" ] && [ -e /workspace/AGENTS.md ] &&
  sed -i "s|__HOST__|$HOSTNAME|g" /workspace/AGENTS.md || true

# --- proxy-routed config ----------------------------------------------------
# Fill the seed config's placeholders. Hermes declares a user `tribes` provider in
# config.yaml's providers map and points model.provider at it (the built-in
# openai-api provider has a hardcoded Nous baseUrl, so an env override never takes
# effect — this MUST be a file). transport: chat_completions makes the OpenAI SDK
# append /chat/completions to `api`. We omit a provider `models` list so the picker
# discovers the full catalog from the proxy's GET /models; model.default preselects
# ours. Skip gracefully if the proxy env is absent (CLI falls back to user creds).
if [ -n "$TRIBES_LLM_MODEL" ] && [ -n "$API_BASE_URL" ] && [ -n "$TRIBES_API_KEY" ]; then
  sed -i "s|__TRIBES_PROXY__|${API_BASE_URL}/llm/proxy|g" /workspace/.hermes/config.yaml
  sed -i "s|__TRIBES_TOKEN__|$TRIBES_API_KEY|g" /workspace/.hermes/config.yaml
  sed -i "s|__TRIBES_MODEL__|$TRIBES_LLM_MODEL|g" /workspace/.hermes/config.yaml
  # Resolve the create-time skin now so no __TRIBES_SKIN__ placeholder reaches the
  # safety net below (launch.sh still re-seds the generic `skin:` line each launch
  # so a later theme toggle takes effect on relaunch).
  skin=$([ "$TRIBES_THEME" = light ] && echo daylight || echo default)
  sed -i "s|^  skin:.*|  skin: $skin|" /workspace/.hermes/config.yaml
else
  # No proxy env (BYO key) — never leave raw placeholders on disk. Drop the seed
  # entirely; hermes then falls back to its built-in Nous provider/OAuth.
  # (launch.sh's skin re-sed is guarded with [ -f ] so a removed file stays gone.)
  rm -f /workspace/.hermes/config.yaml
fi

# --- safety net -------------------------------------------------------------
# Belt-and-suspenders: no file under /workspace may survive with a raw
# __TRIBES_* placeholder (broken/invalid config). AGENTS.md only carries
# __HOST__, so it is not matched.
grep -rlZ "__TRIBES_" /workspace 2>/dev/null | xargs -0 rm -f 2>/dev/null || true
