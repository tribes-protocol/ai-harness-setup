#!/bin/sh
# install-skills.sh — deliver the published agent-skill set into this sandbox.
#
# Single source of truth: ai-harness-setup's skills/ directory. This script is
# curl'd + run from BOTH bootstrap.sh (once, first boot) and launch.sh (every
# launch) of all harnesses, so a restored/relaunched box always refreshes to the
# LATEST published skills without any change to the harness template. It is
# fully tolerant — every step `|| true`, curl is `--max-time`-bounded — and must
# NEVER block or fail a boot.
#
# What it does, self-adapting to the harness by directory existence:
#   - installs each skill to the canonical $HOME/.agent-skills/<slug>/
#   - claude ($HOME/.claude) and pi ($HOME/.pi) get a native skills symlink
#   - AGENTS.md-only harnesses get a marker-fenced "## Skills" section in
#     /root/workspace/AGENTS.md pointing at each canonical SKILL.md
#
# POSIX sh. All config paths are $HOME-relative (the dispatcher decides HOME);
# the sole hardcoded path is the visible workspace AGENTS.md, which both
# dispatchers leave in /root/workspace (matches the existing AGENTS.md curl).

# Kill switch: one line, earliest possible exit.
[ -n "${TRIBES_SKILLS_DISABLE:-}" ] && exit 0

AGENTS="/root/workspace/AGENTS.md"
SKILLS_DIR="$HOME/.agent-skills"

TMP="$(mktemp -d 2>/dev/null || true)"
[ -n "$TMP" ] || { TMP="/tmp/agent-skills.$$"; mkdir -p "$TMP" 2>/dev/null || true; }
trap 'rm -rf "$TMP" 2>/dev/null || true' EXIT

# --- fetch the repo tarball once, extract only skills/ ----------------------
# Derive the codeload tarball URL from the same repo var the AGENTS.md block
# uses (github.com -> codeload.github.com), defaulting to the canonical repo.
REPO="${TRIBES_HARNESS_REPO:-https://github.com/tribes-protocol/ai-harness-setup}"
TGZ_URL="$(echo "$REPO" | sed 's#//github\.com#//codeload.github.com#')/tar.gz/${TRIBES_HARNESS_REF:-main}"

curl -fsSL --max-time 20 "$TGZ_URL" -o "$TMP/repo.tgz" 2>/dev/null || true
tar -xzf "$TMP/repo.tgz" -C "$TMP" 2>/dev/null || true

# Locate the extracted skills/ dir (tarball top-level is <repo>-main/).
SRC=""
for d in "$TMP"/*/skills; do
  [ -d "$d" ] && SRC="$d" && break
done

# --- install to the canonical $HOME/.agent-skills/<slug>/ -------------------
# Only refreshes when a fresh tarball was fetched; a failed fetch leaves any
# previously-installed skills in place (tolerant, idempotent).
if [ -n "$SRC" ]; then
  mkdir -p "$SKILLS_DIR" 2>/dev/null || true
  for s in "$SRC"/*; do
    [ -d "$s" ] && [ -f "$s/SKILL.md" ] || continue
    slug="$(basename "$s")"
    [ -n "$slug" ] || continue
    rm -rf "$SKILLS_DIR/$slug" 2>/dev/null || true
    cp -R "$s" "$SKILLS_DIR/$slug" 2>/dev/null || true
  done
fi

# Nothing installed and nothing pre-existing: leave quietly.
[ -d "$SKILLS_DIR" ] || exit 0

# --- native loaders: symlink $HOME/.claude/skills, $HOME/.pi/agent/skills, $HOME/.openclaw/skills ------
# Whole-dir symlink by default; per-slug symlinks if the harness already ships a
# real skills dir with content. Self-gates on the harness config dir existing,
# so this is a no-op on the other 7 harnesses.
link_skills() {
  base="$HOME/$1"                       # e.g. $HOME/.claude
  [ -d "$base" ] || return 0
  target="$base/skills"
  if [ -L "$target" ]; then
    ln -sfn "$SKILLS_DIR" "$target" 2>/dev/null || true
  elif [ -d "$target" ]; then
    for s in "$SKILLS_DIR"/*; do
      [ -d "$s" ] || continue
      ln -sfn "$s" "$target/$(basename "$s")" 2>/dev/null || true
    done
  else
    ln -sfn "$SKILLS_DIR" "$target" 2>/dev/null || true
  fi
}
link_skills ".claude"
link_skills ".pi/agent"
link_skills ".openclaw"

# --- AGENTS.md-only harnesses: marker-fenced "## Skills" section ------------
# Idempotently rewrite the block between the markers so the 7 non-native
# harnesses (which read AGENTS.md only) learn the skills exist and where to read
# them. The markers deliberately contain no "__TRIBES_" literal, so claude's
# end-of-bootstrap safety-net sweep never matches them.
if [ -f "$AGENTS" ] && [ -n "$(ls "$SKILLS_DIR" 2>/dev/null)" ]; then
  BLOCK="$TMP/skills-block.md"
  {
    echo "<!-- BEGIN TRIBES SKILLS -->"
    echo "## Skills"
    echo ""
    echo "This sandbox ships skills that document its baked helper CLIs. Before doing any task below, READ the linked SKILL.md in full — it documents the exact, safe command surface for that task."
    echo ""
    for s in "$SKILLS_DIR"/*; do
      [ -d "$s" ] && [ -f "$s/SKILL.md" ] || continue
      slug="$(basename "$s")"
      desc="$(sed -n 's/^description:[[:space:]]*//p' "$s/SKILL.md" | head -n1)"
      echo "- **$slug** — $desc Read: $s/SKILL.md"
    done
    echo "<!-- END TRIBES SKILLS -->"
  } > "$BLOCK" 2>/dev/null || true

  # Strip any existing block AND trailing blank lines, then re-append exactly one
  # blank line + the fresh block. This is idempotent (repeated runs converge).
  awk '
    /<!-- BEGIN TRIBES SKILLS -->/ { s=1 }
    s==0 { buf[++n]=$0 }
    /<!-- END TRIBES SKILLS -->/ { s=0 }
    END { while (n>0 && buf[n] ~ /^[[:space:]]*$/) n--
          for (i=1;i<=n;i++) print buf[i] }
  ' "$AGENTS" > "$TMP/agents.stripped" 2>/dev/null || true
  [ -s "$TMP/agents.stripped" ] || cp "$AGENTS" "$TMP/agents.stripped" 2>/dev/null || true

  { cat "$TMP/agents.stripped"; printf '\n'; cat "$BLOCK"; } > "$TMP/agents.new" 2>/dev/null || true
  [ -s "$TMP/agents.new" ] && mv "$TMP/agents.new" "$AGENTS" 2>/dev/null || true
fi

exit 0
