#!/bin/sh
# Regression test for the stale-on-disk proxy bearer bug.
#
# The /llm/proxy bearer is a short-lived ES256 JWT minted IN-VM by
# `tribes-agent-token` from the sandbox's P-256 agent key. That key is stable
# across a pause/restore, so nothing on the control plane re-mints or revokes
# anything. A token baked into a config file ONCE (in bootstrap.sh) still goes
# stale two ways: it EXPIRES (~7-day TTL), and a PAUSE -> RESTORE boots an
# archived disk still holding the PREVIOUS boot's older JWT. Either way the proxy
# 401s. launch.sh runs on EVERY boot, so it must re-mint and re-apply the token.
#
# This test simulates a RESTORED disk: the harness config already holds an OLD
# JWT. It runs each file-based harness's launch.sh with a stubbed
# `tribes-agent-token` (minting the NEW JWT) and a stubbed harness binary, then
# asserts the harness will read the NEW token, never the OLD (stale) one.
#
# It also asserts the keyless BYO branch: when `tribes-agent-token` mints nothing
# (an external/BYO box with no agent key), launch.sh must leave no proxy creds on
# disk so the harness falls back to the user's own credentials.
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

# `tribes-agent-token` is how every launch.sh now obtains the proxy bearer
# (`token="$(tribes-agent-token 2>/dev/null || true)"`). Without this stub the
# command is missing from PATH, $token is empty, and EVERY proxy guard
# short-circuits — the test would measure its own missing stub, not the harness.
# It mints whatever $TMP/minted_token holds; emptying that file simulates a
# keyless BYO box (prints nothing, exits 1).
printf '%s' "$NEW" > "$TMP/minted_token"
cat > "$STUB/tribes-agent-token" <<EOF
#!/bin/sh
[ -s "$TMP/minted_token" ] || exit 1
printf '%s' "\$(cat "$TMP/minted_token")"
EOF
chmod +x "$STUB/tribes-agent-token"

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
    API_BASE_URL="https://api.example" \
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
  API_BASE_URL="https://api.example" \
  TRIBES_LLM_MODEL="m" \
  sh "$TMP/cline-launch.sh" >/dev/null 2>&1 || true
if [ -f "$TMP/cline_apikey" ] && [ "$(cat "$TMP/cline_apikey")" = "$NEW" ]; then
  pass "cline: launch.sh re-auths with the live key"
else
  fail "cline: launch.sh did not re-auth with the live key on restore"
fi

# env-based harnesses (codex/grok) mint + export a fresh bearer each launch, so
# they are restore-safe by construction for the LAUNCHED harness — guard that
# they still do. claude also still exports (belt-and-suspenders for the launched
# harness — see run_file_harness above for its file-based half, which is what
# fixes manual/exit-shell auth).
#
# Assert the CURRENT mechanism (an in-VM `tribes-agent-token` mint), not the
# retired TRIBES_API_KEY variable. Deliberately NOT an old|new alternation: that
# would let a harness silently keep the retired injected key and still pass.
for h in claude codex grok; do
  if grep -q 'tribes-agent-token' "$REPO/$h/launch.sh"; then
    pass "$h: launch.sh mints + exports a fresh bearer (env-based, restore-safe)"
  else
    fail "$h: launch.sh no longer mints the bearer via tribes-agent-token"
  fi
done

# The retired variable must not linger in any proxy-capable entrypoint: a harness
# still reading TRIBES_API_KEY would present a key the control plane no longer sets.
for h in claude cline codex grok hermes openclaw opencode pi; do
  for entrypoint in bootstrap.sh launch.sh; do
    if grep -q 'TRIBES_API_KEY' "$REPO/$h/$entrypoint"; then
      fail "$h: $entrypoint still references the retired TRIBES_API_KEY"
    else
      pass "$h: $entrypoint is free of the retired TRIBES_API_KEY"
    fi
  done
done

# --- keyless BYO: tribes-agent-token mints NOTHING ---------------------------
# Every launch.sh guards its proxy wiring on a non-empty $token so an external /
# BYO box (no P-256 agent key, so nothing to mint from) falls back to the user's
# OWN credentials. Nothing exercised that branch: a bug that wrote an EMPTY
# bearer — `"apiKey": ""`, or `cline auth --apikey ''` — would break BYO boxes
# while every positive check above still passed. Assert no proxy creds land on
# disk when the mint fails.
: > "$TMP/minted_token"

# Two shapes, because the `[ -n "$token" ] && [ -f "$CFG" ]` guard has two halves
# and the absent-config half alone would pass no matter what the mint returned:
#
#   (a) BYO box — bootstrap.sh removed the config, so `-f` is false. launch.sh
#       must not RESURRECT it with proxy creds.
#   (b) keyed box whose mint transiently FAILS (tribes-agent-token exits 1 — key
#       unreadable, keyd hiccup). The config still holds a working token, so
#       `-f` is TRUE and only the `-n "$token"` half stops the write. launch.sh
#       must leave it UNTOUCHED — blanking it to `"apiKey": ""` would brick a
#       box that was fine a boot ago.
keyless_file_harness() {
  h="$1"; cfgrel="$2"

  # (a) config absent
  home="$TMP/$h/byo-home"
  mkdir -p "$home"
  HOME="$home" PATH="$STUB:$PATH" \
    API_BASE_URL="https://api.example" \
    TRIBES_LLM_MODEL="m" TRIBES_THEME="dark" \
    sh "$REPO/$h/launch.sh" >/dev/null 2>&1 || true

  if [ -e "$home/$cfgrel" ]; then
    fail "$h: keyless BYO — launch.sh resurrected a proxy config with no minted token"
    return
  fi
  if grep -rqs "api.example/llm/proxy" "$home"; then
    fail "$h: keyless BYO — launch.sh left proxy creds on disk"
    return
  fi

  # (b) config present, mint fails
  home="$TMP/$h/mintfail-home"
  mkdir -p "$home/$(dirname "$cfgrel")"
  sed "s|__TRIBES_TOKEN__|$OLD|g" "$REPO/$h/$cfgrel" > "$home/$cfgrel"
  HOME="$home" PATH="$STUB:$PATH" \
    API_BASE_URL="https://api.example" \
    TRIBES_LLM_MODEL="m" TRIBES_THEME="dark" \
    sh "$REPO/$h/launch.sh" >/dev/null 2>&1 || true

  # Assert the CREDENTIAL specifically, not the whole file: some launch.sh's
  # legitimately rewrite unrelated lines every boot (hermes re-applies the theme
  # `skin:`), so a byte-identity check would false-fail on correct code.
  if ! grep -q "$OLD" "$home/$cfgrel"; then
    fail "$h: keyless BYO — launch.sh clobbered the working token on a failed mint"
  elif grep -qE '(api_key|apiKey)"?: *""' "$home/$cfgrel"; then
    fail "$h: keyless BYO — launch.sh wrote an EMPTY credential on a failed mint"
  else
    pass "$h: keyless BYO — no proxy creds written, working token left intact"
  fi
}

keyless_file_harness pi       ".pi/agent/models.json"
keyless_file_harness opencode ".config/opencode/opencode.json"
keyless_file_harness openclaw ".openclaw/openclaw.json"
keyless_file_harness hermes   ".hermes/config.yaml"
keyless_file_harness claude   ".claude/settings.json"

# cline: on a keyless box launch.sh must NOT run `cline auth --apikey` at all —
# authing with an empty string would clobber the user's own provider config.
rm -f "$TMP/cline_apikey"
byows="$TMP/cline/byo-workspace"; mkdir -p "$byows"
sed "s|/root/workspace|$byows|g" "$REPO/cline/launch.sh" > "$TMP/cline-launch-byo.sh"
PATH="$STUB:$PATH" \
  API_BASE_URL="https://api.example" \
  TRIBES_LLM_MODEL="m" \
  sh "$TMP/cline-launch-byo.sh" >/dev/null 2>&1 || true
if [ -e "$TMP/cline_apikey" ]; then
  fail "cline: keyless BYO — launch.sh ran \`cline auth --apikey\` with no minted token"
else
  pass "cline: keyless BYO — no auth call, the user's own provider config survives"
fi

# env-based harnesses: the export must be SKIPPED, not exported empty (an empty
# OPENAI_API_KEY/ANTHROPIC_AUTH_TOKEN shadows the user's own credential).
for h in claude codex grok; do
  if grep -qE '\[ -n "\$token" \]|if \[ -n "\$token" \]' "$REPO/$h/launch.sh"; then
    pass "$h: keyless BYO — the bearer export is guarded on a non-empty mint"
  else
    fail "$h: keyless BYO — launch.sh exports the bearer unguarded (empty on a BYO box)"
  fi
done

printf '%s' "$NEW" > "$TMP/minted_token"

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
  # A BYO box has no agent key, so tribes-agent-token mints NOTHING. Empty the
  # stub's token file for this block (and restore it after) — otherwise the
  # shared $STUB would hand bootstrap.sh a live JWT and this check would
  # silently exercise the KEYED path instead of the BYO one it exists to guard.
  : > "$TMP/minted_token"
  ( unset TRIBES_LLM_MODEL API_BASE_URL
    HOME="$home" PATH="$curlstub:$STUB:$PATH" sh "$TMP/claude-byo/bootstrap.sh" ) >/dev/null 2>&1 || true
  printf '%s' "$NEW" > "$TMP/minted_token"
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
