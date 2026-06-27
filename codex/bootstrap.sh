#!/bin/sh
# Codex harness bootstrap — runs ONCE on first boot, as root, cwd /workspace, sh.
# Installs the Codex CLI and fills the committed seed config (.codex/config.toml)
# with the runtime proxy + model. Env-based config (OPENAI_API_KEY) is set in
# launch.sh, because exports from this process are lost before the harness launches.
set -e

# --- install ----------------------------------------------------------------
command -v codex >/dev/null 2>&1 ||
  npm install -g --no-fund --no-audit @openai/codex@latest

# --- seed the shared agent primer -------------------------------------------
# Seed the shared agent primer from the repo root (single source of truth).
RAW_BASE="$(echo "${TRIBES_HARNESS_REPO:-https://github.com/tribes-protocol/ai-harness-setup}" | sed 's#//github\.com#//raw.githubusercontent.com#')"
curl -fsSL "$RAW_BASE/main/AGENTS.md" -o /workspace/AGENTS.md 2>/dev/null || true
host="${HOSTNAME:-$(hostname 2>/dev/null || true)}"
[ -n "$host" ] && [ -e /workspace/AGENTS.md ] && sed -i "s|__HOST__|$host|g" /workspace/AGENTS.md

# --- config -----------------------------------------------------------------
# The committed seed .codex/config.toml has two layers:
#   1. trust/yolo (approval_policy, sandbox_mode, [projects."/workspace"]) —
#      ALWAYS keep; the microVM is the security boundary, so codex must be
#      fully non-interactive regardless of which provider it talks to.
#   2. proxy routing (model, model_provider, [model_providers.tribes]) — only
#      valid when the metered proxy env is present.
# Proxy present  → fill the proxy placeholders, keep the whole file.
# BYO (proxy env unset) → strip ONLY the proxy bits so codex falls back to its
#      own provider/creds while staying auto-approved + trusted. No raw
#      __TRIBES_* placeholders survive either way.
# Done with `bun` (smol-toml) for a robust structured edit, not fragile sed.
if [ -n "$TRIBES_LLM_MODEL" ] && [ -n "$API_BASE_URL" ] && [ -n "$TRIBES_API_KEY" ]; then
  sed -i "s|__TRIBES_PROXY__|${API_BASE_URL}/llm/proxy|g" /workspace/.codex/config.toml
  sed -i "s|__TRIBES_MODEL__|$TRIBES_LLM_MODEL|g" /workspace/.codex/config.toml
elif [ -e /workspace/.codex/config.toml ]; then
  # Preferred: structured edit via bun + smol-toml (robust to whitespace/order).
  ( cd /workspace && bun add --silent smol-toml >/dev/null 2>&1 || true )
  TOML_PATH=/workspace/.codex/config.toml bun -e '
    import { parse, stringify } from "smol-toml";
    const p = process.env.TOML_PATH;
    const cfg = parse(await Bun.file(p).text());
    delete cfg.model;
    delete cfg.model_provider;
    delete cfg.model_providers;
    await Bun.write(p, stringify(cfg) + "\n");
  ' 2>/dev/null || true
  # Fallback: if a raw __TRIBES_ placeholder survived (e.g. bun/smol-toml
  # unavailable offline), strip the proxy bits with awk so the safety net below
  # does not nuke the whole file and lose the trust/yolo settings. Drops the
  # top-level model/model_provider keys and the [model_providers.*] table.
  if grep -q "__TRIBES_" /workspace/.codex/config.toml 2>/dev/null; then
    awk '
      /^[[:space:]]*\[model_providers/ { skip=1; next }
      /^[[:space:]]*\[/               { skip=0 }
      skip                            { next }
      /^[[:space:]]*model[[:space:]]*=/          { next }
      /^[[:space:]]*model_provider[[:space:]]*=/ { next }
      { print }
    ' /workspace/.codex/config.toml > /workspace/.codex/config.toml.tmp &&
      mv /workspace/.codex/config.toml.tmp /workspace/.codex/config.toml
  fi
fi

# --- safety net -------------------------------------------------------------
# Belt-and-suspenders: no file under /workspace may survive with a raw
# __TRIBES_* placeholder (broken/invalid config). AGENTS.md only carries
# __HOST__, so it is not matched.
# NEVER delete *.sh — bootstrap.sh/launch.sh legitimately contain __TRIBES_ in
# their sed patterns/fallbacks; only NON-script files with a raw placeholder are
# broken config and get removed.
grep -rl "__TRIBES_" /workspace 2>/dev/null | while IFS= read -r f; do
  case "$f" in *.sh) ;; *) rm -f "$f" ;; esac
done
