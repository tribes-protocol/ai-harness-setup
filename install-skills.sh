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
#   - installs the complete zipbox catalog read-only under /root/skills
#   - native harness skill paths symlink to that canonical installation
#   - real native skill directories keep non-zipbox skills and receive one
#     canonical symlink per zipbox skill
#   - AGENTS.md-only harnesses get a marker-fenced "## Skills" section in
#     /root/workspace/AGENTS.md pointing at each canonical SKILL.md
#
# POSIX sh. Harness config paths are $HOME-relative (the dispatcher decides
# HOME). The shared catalog and visible workspace instructions use their fixed
# sandbox paths under /root.

# Kill switch: one line, earliest possible exit.
[ -n "${TRIBES_SKILLS_DISABLE:-}" ] && exit 0

AGENTS="/root/workspace/AGENTS.md"
SKILLS_DIR="/root/skills"
LEGACY_SKILLS_DIR="$HOME/.agent-skills"
EXPECTED_SKILLS="zipbox-browser zipbox-caddy zipbox-dns zipbox-egress zipbox-email zipbox-wallet zipbox-websearch"

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

# --- stage and install the complete catalog under /root/skills ---------------
# A failed or incomplete fetch leaves the previous installation in place. The
# swap manages zipbox-* entries only, preserving unrelated skills already under
# /root/skills.
STAGED=""
if [ -n "$SRC" ]; then
  complete=1
  for slug in $EXPECTED_SKILLS; do
    [ -f "$SRC/$slug/SKILL.md" ] || complete=0
  done

  if [ "$complete" -eq 1 ]; then
    STAGED="$TMP/catalog"
    mkdir -p "$STAGED" 2>/dev/null || STAGED=""
    if [ -n "$STAGED" ]; then
      for s in "$SRC"/zipbox-*; do
        [ -d "$s" ] && [ -f "$s/SKILL.md" ] || continue
        cp -R "$s" "$STAGED/$(basename "$s")" 2>/dev/null || STAGED=""
        [ -n "$STAGED" ] || break
      done
    fi

    if [ -n "$STAGED" ]; then
      for slug in $EXPECTED_SKILLS; do
        [ -f "$STAGED/$slug/SKILL.md" ] || STAGED=""
      done
    fi
  fi
fi

if [ -n "$STAGED" ]; then
  if [ -L "$SKILLS_DIR" ] || { [ -e "$SKILLS_DIR" ] && [ ! -d "$SKILLS_DIR" ]; }; then
    rm -rf "$SKILLS_DIR" 2>/dev/null || true
  fi
  mkdir -p "$SKILLS_DIR" 2>/dev/null || true
  chmod u+w "$SKILLS_DIR" 2>/dev/null || true

  for stale in "$SKILLS_DIR"/zipbox-*; do
    [ -e "$stale" ] || [ -L "$stale" ] || continue
    rm -rf "$stale" 2>/dev/null || true
  done

  for s in "$STAGED"/zipbox-*; do
    [ -d "$s" ] && [ -f "$s/SKILL.md" ] || continue
    mv "$s" "$SKILLS_DIR/$(basename "$s")" 2>/dev/null || true
  done

  for slug in $EXPECTED_SKILLS; do
    find "$SKILLS_DIR/$slug" -type f -exec chmod 0444 {} + 2>/dev/null || true
    find "$SKILLS_DIR/$slug" -type d -exec chmod 0555 {} + 2>/dev/null || true
  done
  chmod 0555 "$SKILLS_DIR" 2>/dev/null || true
fi

# Do not publish loader links to a partial catalog.
[ -d "$SKILLS_DIR" ] && [ ! -L "$SKILLS_DIR" ] || exit 0
for slug in $EXPECTED_SKILLS; do
  [ -f "$SKILLS_DIR/$slug/SKILL.md" ] || exit 0
done

# Remove managed copies from the former location. Any unrelated local skill is
# left untouched.
if [ "$LEGACY_SKILLS_DIR" != "$SKILLS_DIR" ]; then
  if [ -L "$LEGACY_SKILLS_DIR" ]; then
    rm -f "$LEGACY_SKILLS_DIR" 2>/dev/null || true
  elif [ -d "$LEGACY_SKILLS_DIR" ]; then
    chmod u+w "$LEGACY_SKILLS_DIR" 2>/dev/null || true
    for stale in "$LEGACY_SKILLS_DIR"/zipbox-*; do
      [ -e "$stale" ] || [ -L "$stale" ] || continue
      rm -rf "$stale" 2>/dev/null || true
    done
    rmdir "$LEGACY_SKILLS_DIR" 2>/dev/null || true
  fi
fi

# --- native loaders: symlink $HOME/.claude/skills, $HOME/.pi/agent/skills, $HOME/.openclaw/skills ------
# Whole-dir symlink by default; per-slug symlinks if the harness already ships a
# real skills dir. Only zipbox-* entries are replaced in a real directory, so
# harness-specific skills remain intact.
link_skills() {
  base="$HOME/$1"                       # e.g. $HOME/.claude
  [ -d "$base" ] || return 0
  target="$base/skills"
  if [ -L "$target" ]; then
    rm -f "$target" 2>/dev/null || true
    ln -sfn "$SKILLS_DIR" "$target" 2>/dev/null || true
  elif [ -d "$target" ]; then
    for stale in "$target"/zipbox-*; do
      [ -e "$stale" ] || [ -L "$stale" ] || continue
      rm -rf "$stale" 2>/dev/null || true
    done
    for slug in $EXPECTED_SKILLS; do
      ln -s "$SKILLS_DIR/$slug" "$target/$slug" 2>/dev/null || true
    done
  else
    rm -rf "$target" 2>/dev/null || true
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
skill_description() {
  awk '
    /^description:[[:space:]]*/ {
      sub(/^description:[[:space:]]*/, "")
      if ($0 !~ /^[>|][-+]?$/ && length($0) > 0) { print; exit }
      reading=1
      next
    }
    reading && /^[A-Za-z][A-Za-z-]*:/ { exit }
    reading {
      sub(/^[[:space:]]+/, "")
      if (length($0) > 0) { print; exit }
    }
  ' "$1"
}

if [ -f "$AGENTS" ]; then
  BLOCK="$TMP/skills-block.md"
  {
    echo "<!-- BEGIN TRIBES SKILLS -->"
    echo "## Skills"
    echo ""
    echo "This sandbox ships skills that document its baked helper CLIs. Before doing any task below, READ the linked SKILL.md in full — it documents the exact, safe command surface for that task."
    echo ""
    for slug in $EXPECTED_SKILLS; do
      s="$SKILLS_DIR/$slug"
      desc="$(skill_description "$s/SKILL.md")"
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
