#!/bin/sh
# OpenClaw harness bootstrap — runs ONCE on first boot, as root, cwd /root/workspace, sh.
# Installs the OpenClaw CLI and fills the committed seed config. OpenClaw is fully
# FILE-based — there is no env-based config — so launch.sh just execs it. The two
# committed files are .openclaw/exec-approvals.json (fully static yolo defaults)
# and .openclaw/openclaw.json (proxy provider + the live model catalog), the
# latter carrying placeholders this script fills. Config paths are $HOME-relative
# — the dispatcher decides HOME (old: workspace, new: /root).
set -e

# --- install ----------------------------------------------------------------
command -v openclaw >/dev/null 2>&1 ||
  npm install -g --no-fund --no-audit openclaw@latest

# --- seed the shared agent primer -------------------------------------------
# Seed the shared agent primer from the repo root (single source of truth).
RAW_BASE="$(echo "${TRIBES_HARNESS_REPO:-https://github.com/tribes-protocol/ai-harness-setup}" | sed 's#//github\.com#//raw.githubusercontent.com#')"
curl -fsSL "$RAW_BASE/main/AGENTS.md" -o /root/workspace/AGENTS.md 2>/dev/null || true
host="${HOSTNAME:-$(hostname 2>/dev/null || true)}"
[ -n "$host" ] && [ -e /root/workspace/AGENTS.md ] && sed -i "s|__HOST__|$host|g" /root/workspace/AGENTS.md
# Fill the sandbox's own mailbox address the same way as __HOST__. Unlike the
# hostname it is not a boot env var (different apex, per-sandbox), so read it from
# the baked tribes-email CLI — the same source the zipbox-email skill uses. Drop
# the line when no address is available (older, pre-email sandboxes) so no raw
# placeholder survives.
if [ -e /root/workspace/AGENTS.md ]; then
  email="$(tribes-email status 2>/dev/null | grep -oE '"address"[[:space:]]*:[[:space:]]*"[^"]+"' | sed -E 's/.*"([^"]+)"$/\\1/' | head -n1)"
  if [ -n "$email" ]; then
    sed -i "s|__EMAIL__|$email|g" /root/workspace/AGENTS.md
  else
    sed -i "/__EMAIL__/d" /root/workspace/AGENTS.md
  fi
fi

# --- proxy-routed config ----------------------------------------------------
# Fill the committed seed .openclaw/openclaw.json placeholders. OpenClaw uses a
# custom openai-completions provider (appends /chat/completions) and REQUIRES it
# to declare its models as an array of {id,name} objects — a provider with no
# models is rejected as invalid ("custom model providers must declare models")
# and openclaw exits to a shell. It does NOT auto-discover, so fetch the catalog
# from the proxy's GET /models and embed each id (reusing id as name); fall back
# to just the default model if the fetch hiccups at boot. Skip gracefully if the
# proxy env is absent — the placeholders are left untouched and the CLI falls
# back to whatever creds the user supplies.
if [ -n "$TRIBES_LLM_MODEL" ] && [ -n "$API_BASE_URL" ] && [ -n "$TRIBES_API_KEY" ]; then
  proxy="${API_BASE_URL}/llm/proxy"
  token="$TRIBES_API_KEY"
  claw_models=$(curl -s --max-time 10 "$proxy/models" -H "Authorization: Bearer $token" 2>/dev/null \
    | grep -oE '"id":[[:space:]]*"[^"]+"' \
    | sed -E 's/.*"([^"]+)"$/{"id": "\1", "name": "\1"}/' | paste -sd, -)
  [ -n "$claw_models" ] || claw_models="{\"id\": \"$TRIBES_LLM_MODEL\", \"name\": \"$TRIBES_LLM_MODEL\"}"

  # Substitute every placeholder via awk so the catalog array (which contains
  # slashes, braces and quotes) is injected verbatim — no sed-delimiter clash.
  # awk's gsub replacement treats `&` and `\` specially, so escape them in each
  # value first; the placeholders are then replaced literally and JSON stays valid.
  cfg="$HOME/.openclaw/openclaw.json"
  awk \
    -v proxy="$proxy" -v token="$token" \
    -v model="$TRIBES_LLM_MODEL" -v models="$claw_models" '
    function esc(s) { gsub(/\\/, "\\\\", s); gsub(/&/, "\\&", s); return s }
    BEGIN { proxy=esc(proxy); token=esc(token); model=esc(model); models=esc(models) }
    {
      gsub(/__TRIBES_PROXY__/, proxy)
      gsub(/__TRIBES_TOKEN__/, token)
      gsub(/__TRIBES_MODEL__/, model)
      gsub(/__TRIBES_MODELS__/, models)
      print
    }
  ' "$cfg" > "$cfg.tmp" && mv "$cfg.tmp" "$cfg"
else
  # No proxy env (BYO key) — never leave raw placeholders on disk. Drop the
  # proxy-provider seed (keep the static exec-approvals.json); openclaw then
  # uses its own provider/creds.
  rm -f "$HOME/.openclaw/openclaw.json"
fi

# --- safety net -------------------------------------------------------------
# Belt-and-suspenders: no file under /root/workspace may survive with a raw
# __TRIBES_* placeholder (broken/invalid config). AGENTS.md only carries
# __HOST__ and __EMAIL__ (both filled above), so it is not matched.
# NEVER delete *.sh — bootstrap.sh/launch.sh legitimately contain __TRIBES_ in
# their sed patterns/fallbacks; only NON-script files with a raw placeholder are
# broken config and get removed.
grep -rl "__TRIBES_" /root/workspace "$HOME/.openclaw" 2>/dev/null | while IFS= read -r f; do
  case "$f" in *.sh) ;; *) rm -f "$f" ;; esac
done

# --- shared agent skills (single source of truth, installed at boot) --------
# Install the skill set read-only under /root/skills and wire the native
# (claude/pi) or AGENTS.md loaders. Drive-first (#1914): the shared read-only
# /opt/harnesses drive bakes the pinned catalog AND this installer, so a stock
# boot runs the baked copy and needs no network for skills. The installer is
# fetched only when the drive predates skills (old image, dev backend) or a
# pinned TRIBES_HARNESS_REF (QA) must exercise that branch's own installer.
# Runs after all config writes; fully tolerant, so it never blocks or fails
# the boot.
if [ -z "${TRIBES_HARNESS_REF:-}" ] && [ -f /opt/harnesses/skills/install-skills.sh ]; then
  sh /opt/harnesses/skills/install-skills.sh || true
else
  curl -fsSL --max-time 20 "$RAW_BASE/${TRIBES_HARNESS_REF:-main}/install-skills.sh" | sh || true
fi
