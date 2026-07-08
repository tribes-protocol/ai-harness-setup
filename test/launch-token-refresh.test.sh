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
for bin in pi opencode openclaw hermes; do
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

# env-based harnesses (claude/codex/grok) export the live $TRIBES_API_KEY each
# launch, so they are restore-safe by construction — guard that they still do.
for h in claude codex grok; do
  if grep -q 'TRIBES_API_KEY' "$REPO/$h/launch.sh"; then
    pass "$h: launch.sh exports the live token (env-based, restore-safe)"
  else
    fail "$h: launch.sh no longer references the live token"
  fi
done

if [ "$fails" -ne 0 ]; then
  printf '\n%d check(s) failed\n' "$fails"
  exit 1
fi
printf '\nall token-refresh checks passed\n'
