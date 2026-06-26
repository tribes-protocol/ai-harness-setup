#!/bin/sh
# Pi harness bootstrap — runs ONCE on first boot, as root, cwd /workspace, sh.
# Pi is fully FILE-based: it reads /workspace/.pi/agent/{models,settings}.json,
# so there is NO env-based config to defer to launch.sh. The two config files are
# COMMITTED real files (seed files) carrying placeholders; this script only fills
# the handful of runtime values it can't commit (proxy base, token, default model,
# and the live model catalog). Skip the proxy fill gracefully when the proxy env
# is absent (the CLI then falls back to the user's own creds).
set -e

# --- install ----------------------------------------------------------------
command -v pi >/dev/null 2>&1 ||
  { npm install -g --no-fund --no-audit @earendil-works/pi-coding-agent@latest && (pi update || true); }

# --- AGENTS.md: substitute the VM's public host -----------------------------
# Pi reads AGENTS.md; replace the __HOST__ placeholder with this VM's host.
[ -n "$HOSTNAME" ] && [ -e /workspace/AGENTS.md ] &&
  sed -i "s/__HOST__/$HOSTNAME/g" /workspace/AGENTS.md || true

# --- proxy-routed config ----------------------------------------------------
# Pi → an openai-completions provider declared in models.json. Pi does NOT
# auto-discover models for a custom provider, so fetch the full live catalog from
# the proxy's GET /models and embed it. If the fetch is empty (boot-time hiccup),
# substitute an empty array so models.json stays valid JSON.
if [ -n "$TRIBES_LLM_MODEL" ] && [ -n "$API_BASE_URL" ] && [ -n "$TRIBES_API_KEY" ]; then
  proxy="${API_BASE_URL}/llm/proxy"
  token="$TRIBES_API_KEY"

  # Live catalog → the array CONTENTS for "models": [ ... ] (may be empty).
  pi_models=$(curl -s --max-time 10 "$proxy/models" -H "Authorization: Bearer $token" 2>/dev/null \
    | grep -oE '"id":[[:space:]]*"[^"]+"' \
    | sed -E 's/.*"([^"]+)"$/{ "id": "\1" }/' | paste -sd, -)

  # Fill the seed files. Substitute via awk literal gsub (NOT sed) so values that
  # contain '/', '&', or other regex/replacement metacharacters — proxy URL, JSON
  # model objects — are inserted verbatim and the result stays valid JSON.
  fill() {
    # fill <file> <placeholder> <value>
    awk -v ph="$2" -v val="$3" '
      { while ((i = index($0, ph)) > 0)
          $0 = substr($0, 1, i - 1) val substr($0, i + length(ph))
        print }
    ' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
  }

  m=/workspace/.pi/agent/models.json
  s=/workspace/.pi/agent/settings.json
  fill "$m" "__TRIBES_PROXY__" "$proxy"
  fill "$m" "__TRIBES_TOKEN__" "$token"
  fill "$m" "__TRIBES_MODELS__" "$pi_models"
  fill "$s" "__TRIBES_MODEL__" "$TRIBES_LLM_MODEL"
else
  # No proxy env (BYO key) — never leave raw placeholders on disk. Drop both seed
  # files; pi then falls back to its own provider/creds.
  rm -f /workspace/.pi/agent/models.json /workspace/.pi/agent/settings.json
fi

# --- safety net -------------------------------------------------------------
# Belt-and-suspenders: no file under /workspace may survive with a raw
# __TRIBES_* placeholder (broken/invalid config). AGENTS.md only carries
# __HOST__, so it is not matched.
grep -rlZ "__TRIBES_" /workspace 2>/dev/null | xargs -0 rm -f 2>/dev/null || true
