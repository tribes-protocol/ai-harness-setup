#!/bin/sh
# Regression test for the PAUSE -> RESTORE re-mint bug.
#
# A paused box's disk is archived to R2; on restore the control plane RE-MINTS the
# per-sandbox proxy key (it REVOKES the old TRIBES_API_KEY and injects a fresh one
# on the boot cmdline). A file-based harness that baked the token into its config
# ONCE (in bootstrap.sh) would then present the OLD, revoked token and the proxy
# 401s. launch.sh runs on EVERY boot with the live cmdline env, so it must refresh
# the on-disk token from $TRIBES_API_KEY.
#
# This test simulates a RESTORED disk: the harness config already holds an OLD
# token. It runs each file-based harness's launch.sh with a fresh TRIBES_API_KEY
# and a stubbed harness binary, then asserts the harness will read the NEW token,
# never the OLD (revoked) one.
#
# POSIX sh; relies on GNU sed -i (the guest + CI are Linux). Run: sh test/launch-token-refresh.test.sh
set -u

REPO="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

OLD="tribes_sb_old0000000000000000000000000000000000000000000000000000000000"
NEW="tribes_sb_new1111111111111111111111111111111111111111111111111111111111"

# Stub binaries on PATH so each launch.sh's `exec <harness>` succeeds (exit 0).
# `cline` is special: it WRITES its token via `cline auth ... --apikey <token>`,
# so the stub captures that arg to a file the test asserts on.
STUB="$TMP/bin"
mkdir -p "$STUB"
for bin in pi opencode openclaw hermes claude; do
  printf '#!/bin/sh\nexit 0\n' > "$STUB/$bin"
  chmod +x "$STUB/$bin"
done
cat > "$STUB/cline" <<EOF
#!/bin/sh
if [ "\$1" = auth ]; then
  while [ \$# -gt 0 ]; do
    [ "\$1" = --apikey ] && { printf '%s' "\$2" > "$TMP/cline_apikey"; }
    shift
  done
fi
exit 0
EOF
chmod +x "$STUB/cline"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }
skip() { printf 'skip - %s\n' "$1"; }

# launch.sh uses GNU `sed -i "expr" file` (the guest + CI are Linux); BSD/macOS sed
# reads the next arg as a backup suffix, so the file-config checks can only validate
# on GNU sed. Detect it (GNU sed has --version; BSD does not) and skip — never
# falsely fail — on a non-GNU dev box. cline + the env-based checks are sed-agnostic.
GNU_SED=0
sed --version >/dev/null 2>&1 && GNU_SED=1

# Run one file-based harness whose token lives in a config file we sed.
# Config paths in launch.sh are $HOME-relative (the dispatcher decides HOME), so
# this test points HOME at a throwaway sandbox dir instead of rewriting the script.
#   $1 harness dir   $2 config path relative to $HOME
run_file_harness() {
  h="$1"; cfgrel="$2"
  if [ "$GNU_SED" -ne 1 ]; then
    skip "$h: needs GNU sed to validate launch.sh's in-place token rewrite"
    return
  fi
  home="$TMP/$h/home"
  mkdir -p "$home/$(dirname "$cfgrel")"
  # Simulate a restored disk: the committed seed with its token placeholder
  # already filled to the OLD (revoked) token (what bootstrap.sh wrote at first
  # boot, now stale).
  sed "s|__TRIBES_TOKEN__|$OLD|g" "$REPO/$h/$cfgrel" > "$home/$cfgrel"

  HOME="$home" PATH="$STUB:$PATH" \
    TRIBES_API_KEY="$NEW" API_BASE_URL="https://api.example" \
    TRIBES_LLM_MODEL="m" TRIBES_THEME="dark" \
    sh "$REPO/$h/launch.sh" >/dev/null 2>&1 || true

  if grep -q "$NEW" "$home/$cfgrel" && ! grep -q "$OLD" "$home/$cfgrel"; then
    pass "$h: launch.sh refreshed the on-disk token to the live key"
  else
    fail "$h: on-disk token NOT refreshed (still revoked) — restored box would 401"
  fi
}

run_file_harness pi      ".pi/agent/models.json"
run_file_harness opencode ".config/opencode/opencode.json"
run_file_harness openclaw ".openclaw/openclaw.json"
run_file_harness hermes  ".hermes/config.yaml"
# claude is a HYBRID: launch.sh both exports ANTHROPIC_* (for the auto-launched
# harness) AND refreshes the same live token into settings.json's "env" block
# (for a manually typed `claude` in the exit shell, which never sees the export —
# see the env-based loop below for the export half). run_file_harness covers the
# file half exactly like the other file-based harnesses.
run_file_harness claude ".claude/settings.json"

# cline: the token is written by `cline auth --apikey <token>`, which launch.sh
# must run every boot. Assert it re-auths with the LIVE key on restore.
ws="$TMP/cline/workspace"; mkdir -p "$ws"
sed "s|/root/workspace|$ws|g" "$REPO/cline/launch.sh" > "$TMP/cline-launch.sh"
PATH="$STUB:$PATH" \
  TRIBES_API_KEY="$NEW" API_BASE_URL="https://api.example" \
  TRIBES_LLM_MODEL="m" \
  sh "$TMP/cline-launch.sh" >/dev/null 2>&1 || true
if [ -f "$TMP/cline_apikey" ] && [ "$(cat "$TMP/cline_apikey")" = "$NEW" ]; then
  pass "cline: launch.sh re-auths with the live key"
else
  fail "cline: launch.sh did not re-auth with the live key on restore"
fi

# env-based harnesses (codex/grok) export the live $TRIBES_API_KEY each launch,
# so they are restore-safe by construction for the LAUNCHED harness — guard that
# they still do. claude also still exports (belt-and-suspenders for the launched
# harness — see run_file_harness above for its file-based half, which is what
# fixes manual/exit-shell auth).
for h in claude codex grok; do
  if grep -q 'TRIBES_API_KEY' "$REPO/$h/launch.sh"; then
    pass "$h: launch.sh exports the live token (env-based, restore-safe)"
  else
    fail "$h: launch.sh no longer references the live token"
  fi
done

# Regression guard for the safety-net-nukes-the-file failure class: on a BYO box
# (no proxy env), claude/bootstrap.sh must strip settings.json's "env" key
# cleanly — leaving valid JSON, no leftover proxy creds, and no raw __TRIBES_
# placeholder for the end-of-bootstrap safety net to trip on (which would delete
# the whole file, including unrelated settings like "theme").
#
# claude/bootstrap.sh hardcodes /root/workspace (AGENTS.md fetch + the safety-net
# grep), same as every harness's bootstrap.sh (CONTRACT.md exempts visible
# workspace files from $HOME-relative). Run it for real here, NOT against the
# actual /root/workspace: on a box where that path exists (any real sandbox
# guest), it would overwrite the live AGENTS.md/CLAUDE.md and let the safety net
# rm -f real files. sed-rewrite it to a throwaway dir first, mirroring the cline
# block above. Stub curl LOCALLY (its own bin dir, not the shared $STUB) so this
# doesn't shadow curl for any other check.
if command -v bun >/dev/null 2>&1; then
  home="$TMP/claude-byo/home"
  ws="$TMP/claude-byo/workspace"
  curlstub="$TMP/claude-byo/bin"
  mkdir -p "$home/.claude" "$ws" "$curlstub"
  cp "$REPO/claude/.claude/settings.json" "$home/.claude/settings.json"
  printf '#!/bin/sh\nexit 1\n' > "$curlstub/curl"
  chmod +x "$curlstub/curl"
  sed "s|/root/workspace|$ws|g" "$REPO/claude/bootstrap.sh" > "$TMP/claude-byo/bootstrap.sh"
  ( unset TRIBES_LLM_MODEL API_BASE_URL TRIBES_API_KEY
    HOME="$home" PATH="$curlstub:$STUB:$PATH" sh "$TMP/claude-byo/bootstrap.sh" ) >/dev/null 2>&1 || true
  cfg="$home/.claude/settings.json"
  if [ -f "$cfg" ] && ! grep -q "__TRIBES_" "$cfg" && ! grep -q '"env"' "$cfg" &&
    (command -v python3 >/dev/null 2>&1 && python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$cfg" >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1); then
    pass "claude: bootstrap.sh strips the env block cleanly on BYO (valid JSON, no leftover creds)"
  else
    fail "claude: bootstrap.sh left settings.json broken/missing on BYO"
  fi
else
  skip "claude: BYO bootstrap check needs bun"
fi

# Ordering guard: the awk BYO-strip fallback (used when bun is absent) deletes a
# LINE RANGE from `"env": {` to its matching `},`, which only produces valid JSON
# when "env" is the settings.json's FIRST key (see the comment in bootstrap.sh).
# Guard the invariant directly so a future reorder fails loudly here instead of
# silently shipping corrupt JSON on a box without bun.
if sed -n '2p' "$REPO/claude/.claude/settings.json" | grep -q '"env": {'; then
  pass "claude: settings.json keeps \"env\" as the first key (bun-absent fallback stays valid)"
else
  fail "claude: settings.json's \"env\" key moved — the bun-absent awk fallback will emit invalid JSON"
fi

if [ "$fails" -ne 0 ]; then
  printf '\n%d check(s) failed\n' "$fails"
  exit 1
fi
printf '\nall token-refresh checks passed\n'
