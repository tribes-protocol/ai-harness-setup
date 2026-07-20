#!/bin/sh
# Regression test for the silent "proxy-routed but no credential" boot (#2472).
#
# The control plane marks a box proxy-routed by injecting TRIBES_LLM_MODEL +
# API_BASE_URL + a per-sandbox TRIBES_API_KEY. Each launch.sh gates its proxy
# config on all three being present and SKIPS gracefully when they are empty —
# correct for a BYO box (all three unset). But if the key MINT fails, a box
# arrives proxy-routed (model + base present) with an EMPTY TRIBES_API_KEY: the
# old code skipped silently, the box booted, every LLM call 401'd (totalTokens:0)
# and every other vantage read green.
#
# launch.sh must now make that case VISIBLE: a loud stderr line AND a health
# marker (/opt/tribes/.llm-proxy-auth-missing) the fleet can poll. The marker is
# a LIVE signal — cleared on any healthy/BYO boot so a restore that re-mints the
# key self-heals it.
#
# POSIX sh. /opt/tribes is a hardcoded marker dir (CONTRACT.md exempts it from
# $HOME-relative), so — like the existing token-refresh test rewrites
# /root/workspace — we sed-rewrite /opt/tribes to a throwaway dir per run.
# Run: sh test/launch-proxy-auth-missing.test.sh
set -u

REPO="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Proxy-capable harnesses (cursor is BYO-only — no proxy env, intentionally omitted).
HARNESSES="claude cline codex grok hermes openclaw opencode pi"

# Stub every harness binary + curl so `exec <harness>` and the skills fetch are
# instant no-ops and never touch the network.
STUB="$TMP/bin"
mkdir -p "$STUB"
for bin in $HARNESSES curl; do
  printf '#!/bin/sh\nexit 0\n' > "$STUB/$bin"
  chmod +x "$STUB/$bin"
done

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }

MARKER=".llm-proxy-auth-missing"

# Run one harness's launch.sh in an isolated HOME + isolated /opt/tribes, with the
# given proxy env, and report whether the marker exists + what hit stderr.
#   $1 harness   $2 scenario label   $3 MODEL   $4 BASE   $5 KEY
run_case() {
  h="$1"; label="$2"; model="$3"; base="$4"; key="$5"
  home="$TMP/$h/$label/home"
  state="$TMP/$h/$label/opt-tribes"
  mkdir -p "$home" "$state"
  # Point the hardcoded /opt/tribes at the throwaway state dir for this run.
  sed "s#/opt/tribes#$state#g" "$REPO/$h/launch.sh" > "$TMP/$h-$label-launch.sh"

  HOME="$home" PATH="$STUB:$PATH" \
    TRIBES_LLM_MODEL="$model" API_BASE_URL="$base" TRIBES_API_KEY="$key" \
    sh "$TMP/$h-$label-launch.sh" >/dev/null 2>"$TMP/$h-$label.err" || true

  MARKER_PATH="$state/$MARKER"
}

for h in $HARNESSES; do
  # 1. Failed mint: model + base present, key EMPTY -> marker + loud stderr.
  run_case "$h" broken "m" "https://api.example" ""
  if [ -f "$MARKER_PATH" ] && grep -q 'TRIBES_API_KEY is EMPTY' "$TMP/$h-broken.err"; then
    pass "$h: proxy-routed + empty key -> marker written + loud stderr"
  else
    fail "$h: proxy-routed + empty key did NOT surface (marker/stderr missing) — silent broken boot"
  fi

  # 2. Healthy proxy box: all three present -> no marker.
  run_case "$h" healthy "m" "https://api.example" "tribes_sb_live"
  if [ ! -f "$MARKER_PATH" ]; then
    pass "$h: healthy proxy boot -> no marker"
  else
    fail "$h: healthy proxy boot left a stale auth-missing marker"
  fi

  # 3. BYO box: all three empty -> no marker (silent skip is correct here).
  run_case "$h" byo "" "" ""
  if [ ! -f "$MARKER_PATH" ]; then
    pass "$h: BYO boot -> no marker (graceful skip preserved)"
  else
    fail "$h: BYO boot falsely flagged auth-missing"
  fi

  # 4. Self-heal on restore: a broken boot writes the marker; a later healthy boot
  #    against the SAME state dir must CLEAR it (a restore re-mints the key). This
  #    is the ONLY check that exercises the else-branch `rm -f` — the marker is a
  #    LIVE signal, not a sticky one. (Scenarios 1-3 each use a fresh dir and would
  #    pass even if the else branch were deleted.)
  home="$TMP/$h/heal/home"; state="$TMP/$h/heal/opt-tribes"
  mkdir -p "$home" "$state"
  sed "s#/opt/tribes#$state#g" "$REPO/$h/launch.sh" > "$TMP/$h-heal-launch.sh"
  # first boot: broken mint -> marker created
  HOME="$home" PATH="$STUB:$PATH" \
    TRIBES_LLM_MODEL="m" API_BASE_URL="https://api.example" TRIBES_API_KEY="" \
    sh "$TMP/$h-heal-launch.sh" >/dev/null 2>&1 || true
  if [ ! -f "$state/$MARKER" ]; then
    fail "$h: self-heal precondition failed — broken boot did not create the marker"
    continue
  fi
  # second boot: healthy (key re-minted) on the SAME state dir -> marker cleared
  HOME="$home" PATH="$STUB:$PATH" \
    TRIBES_LLM_MODEL="m" API_BASE_URL="https://api.example" TRIBES_API_KEY="tribes_sb_live" \
    sh "$TMP/$h-heal-launch.sh" >/dev/null 2>&1 || true
  if [ ! -f "$state/$MARKER" ]; then
    pass "$h: self-heal -> healthy boot clears the prior auth-missing marker"
  else
    fail "$h: STALE marker -> healthy boot did NOT clear a prior marker (else-branch broken)"
  fi
done

if [ "$fails" -ne 0 ]; then
  printf '\n%d check(s) failed\n' "$fails"
  exit 1
fi
printf '\nall proxy-auth-missing checks passed\n'
