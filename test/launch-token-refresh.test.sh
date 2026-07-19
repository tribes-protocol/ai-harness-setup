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

# --- #2255: the direct-provider escape hatch is closed at exec ---------------
# On a proxy-routed box SandboxBootEnv injects a PLACEHOLDER OPENROUTER_API_KEY.
# Harnesses that auto-register a provider on env presence alone (pi via
# pi-ai/dist/providers/openrouter.js + env-api-keys.js; opencode likewise) can then
# pick OpenRouter DIRECTLY, bypassing the metered proxy and 401ing on the
# placeholder. launch.sh must drop it before exec.
#
# Observed AT EXEC, not by grepping the script: a stub harness binary records what
# it actually inherited. A grep would pass on a `unset` placed after the exec, or
# inside a branch that never runs.
hatch_stub="$TMP/hatchbin"
mkdir -p "$hatch_stub"
for bin in pi opencode openclaw hermes grok cline; do
  cat > "$hatch_stub/$bin" <<EOF
#!/bin/sh
if [ "\$1" = auth ]; then exit 0; fi
printf '%s' "\${OPENROUTER_API_KEY-<UNSET>}" > "$TMP/inherited_\$(basename "\$0")"
exit 0
EOF
  chmod +x "$hatch_stub/$bin"
done
cp "$STUB/tribes-agent-token" "$hatch_stub/tribes-agent-token"
# Shadow curl so this section is hermetic. grok/launch.sh waits on real egress
# (up to 30 attempts against api.x.ai) and every launch.sh fetches the skills
# bundle; on an offline runner that is ~90s of timeouts per invocation, and it
# would make these checks depend on the network to reach the exec they assert on.
printf '#!/bin/sh\nexit 0\n' > "$hatch_stub/curl"
chmod +x "$hatch_stub/curl"

PLACEHOLDER="sk-or-v1-zipbox-openrouter-00000000000000000000000000"
USER_KEY="sk-or-v1-the-users-own-real-byo-key-do-not-touch-it-0000000"

# (a) POSITIVE — proxy-routed box: the placeholder must NOT survive to the harness.
for h in pi opencode openclaw hermes grok cline; do
  home="$TMP/hatch/$h"; mkdir -p "$home"
  rm -f "$TMP/inherited_$h"
  HOME="$home" PATH="$hatch_stub:$STUB:$PATH" \
    API_BASE_URL="https://api.example" \
    TRIBES_LLM_MODEL="m" TRIBES_THEME="dark" \
    OPENROUTER_API_KEY="$PLACEHOLDER" \
    sh "$REPO/$h/launch.sh" >/dev/null 2>&1 || true
  got="$(cat "$TMP/inherited_$h" 2>/dev/null || echo '<NOEXEC>')"
  if [ "$got" = "<UNSET>" ]; then
    pass "$h: proxy box — placeholder OPENROUTER_API_KEY dropped before exec (#2255)"
  else
    fail "$h: proxy box — harness still inherited OPENROUTER_API_KEY ($got): direct-provider hatch OPEN"
  fi
done

# (b) NEGATIVE — BYO / external box: the user's OWN key must be untouched.
# This is the by-construction case: SandboxBootEnv writes TRIBES_LLM_MODEL only
# for proxy-mode, non-byoKey, non-'external' boxes, so on BYO/external the var is
# absent and the unset branch must not run. If someone "simplifies" the guard away
# (or makes the unset unconditional), this fails — which is the whole point.
for h in pi opencode openclaw hermes grok cline; do
  home="$TMP/hatch-byo/$h"; mkdir -p "$home"
  rm -f "$TMP/inherited_$h"
  ( unset TRIBES_LLM_MODEL
    HOME="$home" PATH="$hatch_stub:$STUB:$PATH" \
      API_BASE_URL="https://api.example" \
      TRIBES_THEME="dark" \
      OPENROUTER_API_KEY="$USER_KEY" \
      sh "$REPO/$h/launch.sh" ) >/dev/null 2>&1 || true
  got="$(cat "$TMP/inherited_$h" 2>/dev/null || echo '<NOEXEC>')"
  if [ "$got" = "$USER_KEY" ]; then
    pass "$h: BYO/external — the user's own OPENROUTER_API_KEY is preserved"
  else
    fail "$h: BYO/external — user's OPENROUTER_API_KEY was clobbered (got: $got)"
  fi
done

# opencode additionally disables the provider in its seed config: opencode
# registers ANY provider with a present env var, and the seed is what the TUI
# reads. Env-unset alone would leave a box that re-exports the key (a user, a
# skill) able to pick OpenRouter again.
if grep -q '"disabled_providers"' "$REPO/opencode/.config/opencode/opencode.json" &&
   grep -q 'openrouter' "$REPO/opencode/.config/opencode/opencode.json"; then
  pass "opencode: seed config disables the openrouter provider (#2255)"
else
  fail "opencode: seed config no longer disables the openrouter provider"
fi

# The BYO fallback config that bootstrap.sh writes when there is no proxy env must
# NOT carry the disable — a BYO user's own OpenRouter key has to keep working.
if sed -n '/^  cat > "\$CFG" <<.EOF./,/^EOF$/p' "$REPO/opencode/bootstrap.sh" | grep -q 'disabled_providers'; then
  fail "opencode: the BYO fallback config disables openrouter — breaks BYO OpenRouter users"
else
  pass "opencode: BYO fallback config leaves openrouter enabled"
fi

# Constraint: never a blanket process-wide proxy. The forwarder catalog is a
# CONNECT allowlist that 403s every non-catalog authority, so exporting
# HTTP(S)_PROXY would break github/npm/apt/pypi on every box.
for h in pi opencode openclaw hermes grok cline claude codex; do
  if grep -qE '^[[:space:]]*export[[:space:]]+(HTTPS?_PROXY|https?_proxy)' "$REPO/$h/launch.sh" "$REPO/$h/bootstrap.sh" 2>/dev/null; then
    fail "$h: exports a process-wide HTTP(S)_PROXY — would 403 github/npm/apt via the CONNECT allowlist"
  else
    pass "$h: no process-wide HTTP(S)_PROXY export"
  fi
done

if [ "$fails" -ne 0 ]; then
  printf '\n%d check(s) failed\n' "$fails"
  exit 1
fi
printf '\nall token-refresh checks passed\n'
