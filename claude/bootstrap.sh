#!/bin/sh
# claude harness — bootstrap (runs ONCE, as root, cwd /root/workspace, under sh).
# Installs the Claude Code binary and stamps the host into the primer. All
# FILE-based config (.claude.json trust file, .claude/settings.json) ships as
# committed real files in this harness dir, copied verbatim into /root/workspace by
# the dispatcher, then relocated to $HOME (old dispatcher: stays in the workspace;
# new dispatcher: moves to /root). settings.json's "env" block carries the proxy
# config (ANTHROPIC_BASE_URL/AUTH_TOKEN/MODEL) filled below — this is what a
# MANUALLY-typed `claude` in the exit shell reads, since launch.sh's own `export`s
# die with the harness process and never reach that shell. launch.sh still
# exports the same values too (belt-and-suspenders for the auto-launched harness)
# and refreshes the on-disk token every launch (restore-safety).

set -e

# --- install the harness binary ---------------------------------------------
# Gate on the binary already being present: sandbox rootfs images pre-install the
# harness onto a shared read-only drive on PATH, so first boot skips the install
# and writes only config (matches every other harness's bootstrap).
command -v claude >/dev/null 2>&1 ||
  npm install -g --no-fund --no-audit @anthropic-ai/claude-code@latest || true

# --- seed the shared agent primer -------------------------------------------
# Seed the shared agent primer from the repo root (single source of truth).
RAW_BASE="$(echo "${TRIBES_HARNESS_REPO:-https://github.com/tribes-protocol/ai-harness-setup}" | sed 's#//github\.com#//raw.githubusercontent.com#')"
curl -fsSL "$RAW_BASE/main/AGENTS.md" -o /root/workspace/AGENTS.md 2>/dev/null || true
host="${HOSTNAME:-$(hostname 2>/dev/null || true)}"
[ -n "$host" ] && [ -e /root/workspace/AGENTS.md ] && sed -i "s|__HOST__|$host|g" /root/workspace/AGENTS.md
# claude also reads CLAUDE.md — give it the same primer.
[ -e /root/workspace/AGENTS.md ] && cp /root/workspace/AGENTS.md /root/workspace/CLAUDE.md

# --- proxy config (settings.json "env" block) -------------------------------
# Proxy present  → fill the three placeholders so settings.json's env block is a
#      real, working gateway config claude reads on EVERY invocation (launched OR
#      manually typed in the exit shell). Filled via awk literal gsub (NOT sed) so
#      the proxy URL/token — which may contain '/', '&', or other regex/
#      replacement metacharacters — are inserted verbatim and the result stays
#      valid JSON (mirrors pi/bootstrap.sh's fill()).
# BYO (proxy env unset) → strip the WHOLE "env" key so claude falls back to the
#      user's own login/key with zero leftover proxy creds and zero raw
#      __TRIBES_* placeholders. Structured edit via bun (always present on the
#      sandbox rootfs, unlike node/npm) so theme/skipDangerousModePermissionPrompt
#      survive untouched; falls back to an awk line-range delete if bun is
#      somehow unavailable. settings.json commits "env" as the FIRST key
#      specifically so that fallback's line range (open brace to matching close)
#      is unambiguous.
CFG="$HOME/.claude/settings.json"
if [ -n "$TRIBES_LLM_MODEL" ] && [ -n "$API_BASE_URL" ] && [ -n "$TRIBES_API_KEY" ] && [ -e "$CFG" ]; then
  fill() {
    # fill <file> <placeholder> <value>
    awk -v ph="$2" -v val="$3" '
      { while ((i = index($0, ph)) > 0)
          $0 = substr($0, 1, i - 1) val substr($0, i + length(ph))
        print }
    ' "$1" > "$1.tmp" && mv "$1.tmp" "$1"
  }
  fill "$CFG" "__TRIBES_PROXY__" "${API_BASE_URL}/llm/proxy"
  fill "$CFG" "__TRIBES_TOKEN__" "$TRIBES_API_KEY"
  fill "$CFG" "__TRIBES_MODEL__" "$TRIBES_LLM_MODEL"
elif [ -e "$CFG" ]; then
  command -v bun >/dev/null 2>&1 && bun -e '
    const f = process.argv[1];
    const s = require(f);
    delete s.env;
    require("fs").writeFileSync(f, JSON.stringify(s));
  ' "$CFG" || true
  # Fallback: if a raw __TRIBES_ placeholder survived (e.g. bun unavailable),
  # delete the "env": { ... } block by line range so the safety net below does
  # not nuke the whole file and lose theme/skipDangerousModePermissionPrompt.
  if grep -q "__TRIBES_" "$CFG" 2>/dev/null; then
    awk '
      /^[[:space:]]*"env": \{/ { skip=1; next }
      skip && /^[[:space:]]*\},?[[:space:]]*$/ { skip=0; next }
      skip { next }
      { print }
    ' "$CFG" > "$CFG.tmp" &&
      mv "$CFG.tmp" "$CFG"
  fi
fi

# --- safety net -------------------------------------------------------------
# Belt-and-suspenders: no file under /root/workspace may survive with a raw
# __TRIBES_* placeholder. AGENTS.md/CLAUDE.md only carry __HOST__, so they are
# not matched.
# NEVER delete *.sh — bootstrap.sh/launch.sh legitimately contain __TRIBES_ in
# their sed patterns/fallbacks; only NON-script files with a raw placeholder are
# broken config and get removed.
grep -rl "__TRIBES_" /root/workspace "$HOME/.claude.json" "$HOME/.claude" 2>/dev/null | while IFS= read -r f; do
  case "$f" in *.sh) ;; *) rm -f "$f" ;; esac
done

# --- shared agent skills (single source of truth, refreshed at boot) --------
# Install the published skill set into $HOME/.agent-skills and wire the native
# (claude/pi) or AGENTS.md loaders. Runs after all config writes; fully
# tolerant, so it never blocks or fails the boot.
curl -fsSL --max-time 20 "$RAW_BASE/main/install-skills.sh" | sh || true
