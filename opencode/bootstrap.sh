#!/bin/sh
# opencode harness bootstrap — runs ONCE on first boot, as root, cwd /root/workspace, sh.
# Installs the opencode CLI and fills the SEEDED file-based config
# ($HOME/.config/opencode/opencode.json, copied verbatim from this harness
# dir with __...__ placeholders): the yolo permission, theme, and the proxy
# provider with the embedded model catalog.
# opencode config is entirely FILE-based — theme:"system" follows the terminal —
# so launch.sh just execs it; there is nothing to export per launch. Config paths
# are $HOME-relative — the dispatcher decides HOME (old: workspace, new: /root).
set -e

# --- install ----------------------------------------------------------------
command -v opencode >/dev/null 2>&1 ||
  npm install -g --no-fund --no-audit opencode-ai@latest

# --- seed the shared agent primer -------------------------------------------
# Seed the shared agent primer from the repo root (single source of truth).
RAW_BASE="$(echo "${TRIBES_HARNESS_REPO:-https://github.com/tribes-protocol/ai-harness-setup}" | sed 's#//github\.com#//raw.githubusercontent.com#')"
curl -fsSL "$RAW_BASE/main/AGENTS.md" -o /root/workspace/AGENTS.md 2>/dev/null || true
host="${HOSTNAME:-$(hostname 2>/dev/null || true)}"
[ -n "$host" ] && [ -e /root/workspace/AGENTS.md ] && sed -i "s|__HOST__|$host|g" /root/workspace/AGENTS.md

# --- proxy-routed config ----------------------------------------------------
# opencode → @ai-sdk/openai-compatible provider (appends /chat/completions to
# baseURL). The top-level "permission": "allow" approves every tool in the TUI
# with no prompt (the auto-approve flag exists only on the headless `opencode
# run` subcommand, not the interactive TUI; opencode has no trust-folder gate).
# opencode does NOT auto-discover models for a fully-custom provider — it only
# knows the models declared in the config's "models" map, so `model: tribes/<id>`
# won't resolve without it and opencode silently drops to its built-in default.
# So fetch the catalog from the proxy's GET /models and embed it as the models
# map (like pi). If the fetch is empty (boot-time hiccup), declare at least the
# default model so the preselected `model` still resolves.
CFG="$HOME/.config/opencode/opencode.json"
mkdir -p "$HOME/.config/opencode"

if [ -n "$TRIBES_LLM_MODEL" ] && [ -n "$API_BASE_URL" ] && [ -n "$TRIBES_API_KEY" ] && [ -e "$CFG" ]; then
  proxy="${API_BASE_URL}/llm/proxy"
  token="$TRIBES_API_KEY"
  oc_models=$(curl -s --max-time 10 "$proxy/models" -H "Authorization: Bearer $token" 2>/dev/null \
    | grep -oE '"id":[[:space:]]*"[^"]+"' \
    | sed -E 's/.*"([^"]+)"$/"\1": {}/' | paste -sd, -)
  [ -n "$oc_models" ] || oc_models="\"$TRIBES_LLM_MODEL\": {}"

  # Substitute the placeholders into the seeded config. The model-catalog map
  # is arbitrary JSON (quotes, braces, commas), so pass every replacement
  # value through the environment and let awk do a literal (non-regex) swap —
  # no sed delimiter or shell-quoting hazards. Result is written atomically.
  TRIBES_PROXY="$proxy" TRIBES_TOKEN="$token" \
  TRIBES_MODEL="$TRIBES_LLM_MODEL" TRIBES_MODELS="$oc_models" \
  awk '
    function repl(line, tok, val,   i) {
      while ((i = index(line, tok)) > 0)
        line = substr(line, 1, i - 1) val substr(line, i + length(tok))
      return line
    }
    {
      $0 = repl($0, "__TRIBES_PROXY__",  ENVIRON["TRIBES_PROXY"])
      $0 = repl($0, "__TRIBES_TOKEN__",  ENVIRON["TRIBES_TOKEN"])
      $0 = repl($0, "__TRIBES_MODELS__", ENVIRON["TRIBES_MODELS"])
      $0 = repl($0, "__TRIBES_MODEL__",  ENVIRON["TRIBES_MODEL"])
      print
    }
  ' "$CFG" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
else
  # No proxy env (or the seed is missing) — leave a minimal valid trusted config
  # so the TUI is auto-approved and follows the terminal theme, with NO leftover
  # __...__ tokens; the CLI then falls back to the user's own key.
  cat > "$CFG" <<'EOF'
{
  "$schema": "https://opencode.ai/config.json",
  "permission": "allow",
  "theme": "system"
}
EOF
fi

# --- safety net -------------------------------------------------------------
# Belt-and-suspenders: no file under /root/workspace may survive with a raw
# __TRIBES_* placeholder (broken/invalid config). AGENTS.md only carries
# __HOST__, so it is not matched.
# NEVER delete *.sh — bootstrap.sh/launch.sh legitimately contain __TRIBES_ in
# their sed patterns/fallbacks; only NON-script files with a raw placeholder are
# broken config and get removed.
grep -rl "__TRIBES_" /root/workspace "$HOME/.config/opencode" 2>/dev/null | while IFS= read -r f; do
  case "$f" in *.sh) ;; *) rm -f "$f" ;; esac
done

# --- shared agent skills (single source of truth, refreshed at boot) --------
# Install the published skill set read-only under /root/skills and wire the native
# (claude/pi) or AGENTS.md loaders. Runs after all config writes; fully
# tolerant, so it never blocks or fails the boot.
curl -fsSL --max-time 20 "$RAW_BASE/${TRIBES_HARNESS_REF:-main}/install-skills.sh" | sh || true
