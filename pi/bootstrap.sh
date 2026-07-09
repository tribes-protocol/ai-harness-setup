#!/bin/sh
# Pi harness bootstrap — runs ONCE on first boot, as root, cwd /root/workspace, sh.
# Pi is fully FILE-based: it reads $HOME/.pi/agent/{models,settings}.json,
# so there is NO env-based config to defer to launch.sh. The two config files are
# COMMITTED real files (seed files) carrying placeholders; this script only fills
# the handful of runtime values it can't commit (proxy base, token, default model,
# and the live model catalog). Skip the proxy fill gracefully when the proxy env
# is absent (the CLI then falls back to the user's own creds). Config paths are
# $HOME-relative — the dispatcher decides HOME (old: workspace, new: /root).
set -e

# --- install ----------------------------------------------------------------
command -v pi >/dev/null 2>&1 ||
  { npm install -g --no-fund --no-audit @earendil-works/pi-coding-agent@latest && (pi update || true); }

# --- seed the shared agent primer -------------------------------------------
# Seed the shared agent primer from the repo root (single source of truth).
RAW_BASE="$(echo "${TRIBES_HARNESS_REPO:-https://github.com/tribes-protocol/ai-harness-setup}" | sed 's#//github\.com#//raw.githubusercontent.com#')"
curl -fsSL "$RAW_BASE/main/AGENTS.md" -o /root/workspace/AGENTS.md 2>/dev/null || true
host="${HOSTNAME:-$(hostname 2>/dev/null || true)}"
[ -n "$host" ] && [ -e /root/workspace/AGENTS.md ] && sed -i "s|__HOST__|$host|g" /root/workspace/AGENTS.md

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

  m="$HOME/.pi/agent/models.json"
  s="$HOME/.pi/agent/settings.json"
  fill "$m" "__TRIBES_PROXY__" "$proxy"
  fill "$m" "__TRIBES_TOKEN__" "$token"
  fill "$m" "__TRIBES_MODELS__" "$pi_models"
  fill "$s" "__TRIBES_MODEL__" "$TRIBES_LLM_MODEL"
else
  # No proxy env (BYO key) — never leave raw placeholders on disk. models.json is
  # ONLY the tribes provider, so drop it; pi falls back to its own provider/creds.
  # settings.json carries "theme" (pi's Automatic mode = follow the terminal's
  # light/dark), which is independent of our proxy — KEEP it, but drop the now-dead
  # defaultProvider/defaultModel that referenced the absent tribes provider.
  rm -f "$HOME/.pi/agent/models.json"
  s="$HOME/.pi/agent/settings.json"
  [ -e "$s" ] && command -v bun >/dev/null 2>&1 &&
    bun -e '
      const f = process.argv[1];
      const s = require(f);
      delete s.defaultProvider;
      delete s.defaultModel;
      require("fs").writeFileSync(f, JSON.stringify(s));
    ' "$s" || true
fi

# --- safety net -------------------------------------------------------------
# Belt-and-suspenders: no file under /root/workspace may survive with a raw
# __TRIBES_* placeholder (broken/invalid config). AGENTS.md only carries
# __HOST__, so it is not matched.
# NEVER delete *.sh — bootstrap.sh/launch.sh legitimately contain __TRIBES_ in
# their sed patterns/fallbacks; only NON-script files with a raw placeholder are
# broken config and get removed.
grep -rl "__TRIBES_" /root/workspace "$HOME/.pi" 2>/dev/null | while IFS= read -r f; do
  case "$f" in *.sh) ;; *) rm -f "$f" ;; esac
done

# --- shared agent skills (single source of truth, refreshed at boot) --------
# Install the published skill set into $HOME/.agent-skills and wire the native
# (claude/pi) or AGENTS.md loaders. Runs after all config writes; fully
# tolerant, so it never blocks or fails the boot.
curl -fsSL --max-time 20 "$RAW_BASE/main/install-skills.sh" | sh || true
