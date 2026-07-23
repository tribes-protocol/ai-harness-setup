#!/bin/sh
# Pi's live model catalog runs before the launcher's global proxy exports. Prove
# that this one request selects the explicit proxy safely when present, remains
# direct in transparent-MITM mode, and always uses OpenRouter's Bearer scheme.
set -u

REPO="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
LAUNCH="$REPO/pi/launch.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

TOKEN="pi-token;touch $TMP/token-injection"
PROXY_URL="http://proxy.invalid:15808;touch $TMP/proxy-injection"
CATALOG_URL="https://openrouter.ai/api/v1/models"
FALLBACK_MODEL="openai/fallback-model"
fails=0

pass() {
  printf 'ok   - %s\n' "$1"
}

fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}

contains() {
  grep -Fq -- "$2" "$1"
}

mkdir -p "$TMP/bin"

cat > "$TMP/bin/curl" <<'EOF'
#!/bin/sh
set -u

catalog=no
proxy=none
proxy_count=0
bearer=none
auth_count=0
placeholder=no

while [ "$#" -gt 0 ]; do
  case "$1" in
    --proxy)
      proxy_count=$((proxy_count + 1))
      shift
      if [ "${1:-}" = "$EXPECT_PROXY_URL" ]; then
        proxy=exact
      else
        proxy=wrong
      fi
      ;;
    -H)
      shift
      auth_count=$((auth_count + 1))
      if [ "${1:-}" = "Authorization: Bearer $EXPECT_TOKEN" ]; then
        bearer=exact
      else
        bearer=wrong
      fi
      case "${1:-}" in
        "Authorization: Placeholder "*) placeholder=yes ;;
      esac
      ;;
    "$EXPECT_CATALOG_URL")
      catalog=yes
      ;;
  esac
  shift
done

if [ "$catalog" = yes ]; then
  printf 'catalog proxy=%s proxy_count=%s bearer=%s auth_count=%s placeholder=%s\n' \
    "$proxy" "$proxy_count" "$bearer" "$auth_count" "$placeholder" >> "$CURL_LOG"
  case "$CATALOG_MODE" in
    success)
      printf '%s\n' '{"data":[{"id":"live/one"},{"id":"live/two"}]}'
      ;;
    empty)
      ;;
    fail)
      exit 22
      ;;
    *)
      exit 64
      ;;
  esac
fi
EOF

cat > "$TMP/bin/pi" <<'EOF'
#!/bin/sh
printf '%s\n' 'pi exec' >> "$EXEC_LOG"
EOF

chmod +x "$TMP/bin/curl" "$TMP/bin/pi"

run_case() {
  case_name="$1"
  launch_path="$2"
  catalog_mode="$3"
  egress_mode="$4"
  funding_mode="$5"
  case_dir="$TMP/$case_name"
  home_dir="$case_dir/home"

  mkdir -p "$home_dir/.pi/agent"
  if [ "$funding_mode" = platform ]; then
    printf '%s\n' '{"seed":"platform"}' > "$home_dir/.pi/agent/models.json"
  else
    printf '%s\n' '{"user":"untouched"}' > "$home_dir/.pi/agent/models.json"
  fi
  cp "$home_dir/.pi/agent/models.json" "$case_dir/models.before"
  : > "$case_dir/curl.log"
  : > "$case_dir/exec.log"

  if [ "$funding_mode" = platform ] && [ "$egress_mode" = explicit ]; then
    env -i \
      "HOME=$home_dir" \
      "PATH=$TMP/bin:/usr/bin:/bin" \
      "TRIBES_HARNESS_REF=test" \
      "TRIBES_HARNESS_REPO=https://example.invalid/harness" \
      "CATALOG_MODE=$catalog_mode" \
      "EXPECT_TOKEN=$TOKEN" \
      "EXPECT_PROXY_URL=$PROXY_URL" \
      "EXPECT_CATALOG_URL=$CATALOG_URL" \
      "CURL_LOG=$case_dir/curl.log" \
      "EXEC_LOG=$case_dir/exec.log" \
      "TRIBES_LLM_MODEL=$FALLBACK_MODEL" \
      "OPENROUTER_API_KEY=$TOKEN" \
      "ZIPBOX_EGRESS_PROXY_URL=$PROXY_URL" \
      sh "$launch_path" > "$case_dir/output" 2>&1
  elif [ "$funding_mode" = platform ]; then
    env -i \
      "HOME=$home_dir" \
      "PATH=$TMP/bin:/usr/bin:/bin" \
      "TRIBES_HARNESS_REF=test" \
      "TRIBES_HARNESS_REPO=https://example.invalid/harness" \
      "CATALOG_MODE=$catalog_mode" \
      "EXPECT_TOKEN=$TOKEN" \
      "EXPECT_PROXY_URL=$PROXY_URL" \
      "EXPECT_CATALOG_URL=$CATALOG_URL" \
      "CURL_LOG=$case_dir/curl.log" \
      "EXEC_LOG=$case_dir/exec.log" \
      "TRIBES_LLM_MODEL=$FALLBACK_MODEL" \
      "OPENROUTER_API_KEY=$TOKEN" \
      sh "$launch_path" > "$case_dir/output" 2>&1
  else
    env -i \
      "HOME=$home_dir" \
      "PATH=$TMP/bin:/usr/bin:/bin" \
      "TRIBES_HARNESS_REF=test" \
      "TRIBES_HARNESS_REPO=https://example.invalid/harness" \
      "CATALOG_MODE=$catalog_mode" \
      "EXPECT_TOKEN=$TOKEN" \
      "EXPECT_PROXY_URL=$PROXY_URL" \
      "EXPECT_CATALOG_URL=$CATALOG_URL" \
      "CURL_LOG=$case_dir/curl.log" \
      "EXEC_LOG=$case_dir/exec.log" \
      "OPENROUTER_API_KEY=$TOKEN" \
      sh "$launch_path" > "$case_dir/output" 2>&1
  fi
  rc=$?

  if [ "$rc" -eq 0 ]; then
    pass "$case_name launcher exits through Pi"
  else
    fail "$case_name launcher exits through Pi"
  fi

  if contains "$case_dir/output" "$TOKEN" ||
    contains "$case_dir/output" "$PROXY_URL" ||
    contains "$case_dir/curl.log" "$TOKEN" ||
    contains "$case_dir/curl.log" "$PROXY_URL"; then
    fail "$case_name keeps token and proxy URL out of output"
  else
    pass "$case_name keeps token and proxy URL out of output"
  fi

  if [ -e "$TMP/token-injection" ] || [ -e "$TMP/proxy-injection" ]; then
    fail "$case_name evaluates an environment value as shell syntax"
  else
    pass "$case_name quotes environment-provided curl arguments"
  fi

  LAST_CASE="$case_dir"
}

assert_live_models() {
  models="$1/home/.pi/agent/models.json"
  if contains "$models" '"id": "live/one"' &&
    contains "$models" '"id": "live/two"' &&
    ! contains "$models" "$FALLBACK_MODEL"; then
    pass "$2 consumes the live catalog"
  else
    fail "$2 consumes the live catalog"
  fi
}

assert_fallback_model() {
  models="$1/home/.pi/agent/models.json"
  if contains "$models" "\"id\": \"$FALLBACK_MODEL\"" &&
    ! contains "$models" 'live/one' &&
    ! contains "$models" 'live/two'; then
    pass "$2 retains the configured fallback"
  else
    fail "$2 retains the configured fallback"
  fi
}

# Explicit-proxy success: one exact request-local proxy and one exact Bearer
# header are required, and the returned catalog replaces the seeded model.
run_case explicit-success "$LAUNCH" success explicit platform
if contains "$LAST_CASE/curl.log" \
  'catalog proxy=exact proxy_count=1 bearer=exact auth_count=1 placeholder=no'; then
  pass "explicit mode sends one exact proxy and Bearer header"
else
  fail "explicit mode sends one exact proxy and Bearer header"
fi
assert_live_models "$LAST_CASE" "explicit mode"

# Catalog failure remains non-fatal and retains the existing single-model fallback.
run_case explicit-failure "$LAUNCH" fail explicit platform
if contains "$LAST_CASE/curl.log" \
  'catalog proxy=exact proxy_count=1 bearer=exact auth_count=1 placeholder=no'; then
  pass "explicit failure still uses the supported egress request"
else
  fail "explicit failure still uses the supported egress request"
fi
assert_fallback_model "$LAST_CASE" "explicit failure"

# Transparent MITM has no explicit proxy argument but uses the same valid header.
run_case mitm-success "$LAUNCH" success direct platform
if contains "$LAST_CASE/curl.log" \
  'catalog proxy=none proxy_count=0 bearer=exact auth_count=1 placeholder=no'; then
  pass "MITM mode stays direct and sends one Bearer header"
else
  fail "MITM mode stays direct and sends one Bearer header"
fi
assert_live_models "$LAST_CASE" "MITM mode"

run_case mitm-failure "$LAUNCH" empty direct platform
if contains "$LAST_CASE/curl.log" \
  'catalog proxy=none proxy_count=0 bearer=exact auth_count=1 placeholder=no'; then
  pass "MITM empty catalog stays on the supported direct request"
else
  fail "MITM empty catalog stays on the supported direct request"
fi
assert_fallback_model "$LAST_CASE" "MITM empty catalog"

# BYO/external has no platform model signal: no catalog request and no rewrite.
run_case byo-external "$LAUNCH" success direct byo
if [ ! -s "$LAST_CASE/curl.log" ]; then
  pass "BYO/external skips the platform catalog"
else
  fail "BYO/external skips the platform catalog"
fi
if cmp "$LAST_CASE/models.before" "$LAST_CASE/home/.pi/agent/models.json" >/dev/null; then
  pass "BYO/external preserves the user's Pi configuration"
else
  fail "BYO/external preserves the user's Pi configuration"
fi

# Independent proxy mutation: remove only the request-scoped proxy insertion.
PROXY_MUTANT="$TMP/pi-launch-no-request-proxy.sh"
sed 's/set -- "$@" --proxy "$ZIPBOX_EGRESS_PROXY_URL"/set -- "$@"/' \
  "$LAUNCH" > "$PROXY_MUTANT"
if cmp -s "$LAUNCH" "$PROXY_MUTANT"; then
  fail "proxy mutation did not change the launcher fixture"
else
  run_case proxy-mutation "$PROXY_MUTANT" success explicit platform
  if contains "$LAST_CASE/curl.log" \
    'catalog proxy=exact proxy_count=1 bearer=exact auth_count=1 placeholder=no'; then
    fail "proxy mutation is rejected"
  elif contains "$LAST_CASE/curl.log" \
    'catalog proxy=none proxy_count=0 bearer=exact auth_count=1 placeholder=no'; then
    pass "proxy mutation is rejected"
  else
    fail "proxy mutation exercises only the request-scoped proxy defect"
  fi
fi

# Independent scheme mutation: restore the invalid Placeholder authorization.
HEADER_MUTANT="$TMP/pi-launch-placeholder-header.sh"
sed 's/Authorization: Bearer \$token/Authorization: Placeholder $token/' \
  "$LAUNCH" > "$HEADER_MUTANT"
if cmp -s "$LAUNCH" "$HEADER_MUTANT"; then
  fail "header mutation did not change the launcher fixture"
else
  run_case header-mutation "$HEADER_MUTANT" success explicit platform
  if contains "$LAST_CASE/curl.log" \
    'catalog proxy=exact proxy_count=1 bearer=exact auth_count=1 placeholder=no'; then
    fail "authorization-scheme mutation is rejected"
  elif contains "$LAST_CASE/curl.log" \
    'catalog proxy=exact proxy_count=1 bearer=wrong auth_count=1 placeholder=yes'; then
    pass "authorization-scheme mutation is rejected"
  else
    fail "header mutation exercises only the authorization-scheme defect"
  fi
fi

if [ "$fails" -ne 0 ]; then
  printf '\n%s check(s) failed\n' "$fails"
  exit 1
fi
printf '\nall Pi catalog egress checks passed\n'
