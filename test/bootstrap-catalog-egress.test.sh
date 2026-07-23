#!/bin/sh
# Exercise the exact OpenClaw/OpenCode platform-config blocks without running
# package installation or touching their absolute bootstrap paths.
set -u

REPO="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

TOKEN="bootstrap-token;touch $TMP/token-injection"
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
chmod +x "$TMP/bin/curl"

extract_config_block() {
  extract_harness="$1"
  extract_source="$2"
  extract_output="$3"

  case "$extract_harness" in
    openclaw)
      start='^token="\${OPENROUTER_API_KEY:-}"'
      ;;
    opencode)
      start='^CFG="\$HOME/.config/opencode/opencode.json"'
      ;;
    *)
      return 64
      ;;
  esac

  awk -v start="$start" '
    $0 ~ start { capture=1 }
    capture { print }
    capture && /^fi$/ { exit }
  ' "$extract_source" > "$extract_output"
  [ -s "$extract_output" ] && nice -n 15 sh -n "$extract_output"
}

seed_config() {
  harness="$1"
  home_dir="$2"
  case "$harness" in
    openclaw)
      mkdir -p "$home_dir/.openclaw"
      cp "$REPO/openclaw/.openclaw/openclaw.json" \
        "$home_dir/.openclaw/openclaw.json"
      LAST_CFG="$home_dir/.openclaw/openclaw.json"
      ;;
    opencode)
      mkdir -p "$home_dir/.config/opencode"
      cp "$REPO/opencode/.config/opencode/opencode.json" \
        "$home_dir/.config/opencode/opencode.json"
      LAST_CFG="$home_dir/.config/opencode/opencode.json"
      ;;
  esac
}

run_case() {
  harness="$1"
  case_name="$2"
  snippet="$3"
  catalog_mode="$4"
  egress_mode="$5"
  funding_mode="$6"
  case_dir="$TMP/$harness-$case_name"
  home_dir="$case_dir/home"

  mkdir -p "$case_dir"
  seed_config "$harness" "$home_dir"
  cfg="$LAST_CFG"
  : > "$case_dir/curl.log"

  if [ "$funding_mode" = platform ] && [ "$egress_mode" = explicit ]; then
    env -i \
      "HOME=$home_dir" \
      "PATH=$TMP/bin:/usr/bin:/bin" \
      "CATALOG_MODE=$catalog_mode" \
      "EXPECT_TOKEN=$TOKEN" \
      "EXPECT_PROXY_URL=$PROXY_URL" \
      "EXPECT_CATALOG_URL=$CATALOG_URL" \
      "CURL_LOG=$case_dir/curl.log" \
      "TRIBES_LLM_MODEL=$FALLBACK_MODEL" \
      "OPENROUTER_API_KEY=$TOKEN" \
      "ZIPBOX_EGRESS_PROXY_URL=$PROXY_URL" \
      nice -n 15 sh "$snippet" > "$case_dir/output" 2>&1
  elif [ "$funding_mode" = platform ]; then
    env -i \
      "HOME=$home_dir" \
      "PATH=$TMP/bin:/usr/bin:/bin" \
      "CATALOG_MODE=$catalog_mode" \
      "EXPECT_TOKEN=$TOKEN" \
      "EXPECT_PROXY_URL=$PROXY_URL" \
      "EXPECT_CATALOG_URL=$CATALOG_URL" \
      "CURL_LOG=$case_dir/curl.log" \
      "TRIBES_LLM_MODEL=$FALLBACK_MODEL" \
      "OPENROUTER_API_KEY=$TOKEN" \
      nice -n 15 sh "$snippet" > "$case_dir/output" 2>&1
  else
    env -i \
      "HOME=$home_dir" \
      "PATH=$TMP/bin:/usr/bin:/bin" \
      "CATALOG_MODE=$catalog_mode" \
      "EXPECT_TOKEN=$TOKEN" \
      "EXPECT_PROXY_URL=$PROXY_URL" \
      "EXPECT_CATALOG_URL=$CATALOG_URL" \
      "CURL_LOG=$case_dir/curl.log" \
      "OPENROUTER_API_KEY=$TOKEN" \
      nice -n 15 sh "$snippet" > "$case_dir/output" 2>&1
  fi
  rc=$?

  if [ "$rc" -eq 0 ]; then
    pass "$harness $case_name config block succeeds"
  else
    fail "$harness $case_name config block succeeds"
  fi
  if contains "$case_dir/output" "$TOKEN" ||
    contains "$case_dir/output" "$PROXY_URL" ||
    contains "$case_dir/curl.log" "$TOKEN" ||
    contains "$case_dir/curl.log" "$PROXY_URL"; then
    fail "$harness $case_name keeps secrets out of output"
  else
    pass "$harness $case_name keeps secrets out of output"
  fi
  if [ -e "$TMP/token-injection" ] || [ -e "$TMP/proxy-injection" ]; then
    fail "$harness $case_name evaluates an environment value as shell syntax"
  else
    pass "$harness $case_name quotes environment-provided curl arguments"
  fi

  LAST_CASE="$case_dir"
  LAST_CFG="$cfg"
}

assert_live_models() {
  if contains "$LAST_CFG" 'live/one' &&
    contains "$LAST_CFG" 'live/two'; then
    pass "$1 consumes the live catalog"
  else
    fail "$1 consumes the live catalog"
  fi
}

assert_fallback_model() {
  if contains "$LAST_CFG" "$FALLBACK_MODEL" &&
    ! contains "$LAST_CFG" 'live/one' &&
    ! contains "$LAST_CFG" 'live/two'; then
    pass "$1 retains its configured fallback"
  else
    fail "$1 retains its configured fallback"
  fi
}

for harness in openclaw opencode; do
  bootstrap_source="$REPO/$harness/bootstrap.sh"
  snippet="$TMP/$harness-config.sh"
  extract_config_block "$harness" "$bootstrap_source" "$snippet" ||
    fail "$harness config block extraction"

  run_case "$harness" explicit-success "$snippet" success explicit platform
  if contains "$LAST_CASE/curl.log" \
    'catalog proxy=exact proxy_count=1 bearer=exact auth_count=1 placeholder=no'; then
    pass "$harness explicit mode sends one exact proxy and Bearer header"
  else
    fail "$harness explicit mode sends one exact proxy and Bearer header"
  fi
  assert_live_models "$harness explicit mode"

  run_case "$harness" explicit-failure "$snippet" fail explicit platform
  assert_fallback_model "$harness explicit failure"

  run_case "$harness" mitm-success "$snippet" success direct platform
  if contains "$LAST_CASE/curl.log" \
    'catalog proxy=none proxy_count=0 bearer=exact auth_count=1 placeholder=no'; then
    pass "$harness MITM mode stays direct with one Bearer header"
  else
    fail "$harness MITM mode stays direct with one Bearer header"
  fi
  assert_live_models "$harness MITM mode"

  run_case "$harness" mitm-empty "$snippet" empty direct platform
  assert_fallback_model "$harness MITM empty catalog"

  run_case "$harness" byo-external "$snippet" success direct byo
  if [ ! -s "$LAST_CASE/curl.log" ]; then
    pass "$harness BYO/external skips the platform catalog"
  else
    fail "$harness BYO/external skips the platform catalog"
  fi
  if [ "$harness" = openclaw ] && [ ! -e "$LAST_CFG" ]; then
    pass "openclaw BYO/external removes the platform seed"
  elif [ "$harness" = opencode ] &&
    contains "$LAST_CFG" '"permission": "allow"' &&
    ! contains "$LAST_CFG" '__TRIBES_' &&
    ! contains "$LAST_CFG" '"provider"'; then
    pass "opencode BYO/external retains only its minimal config"
  else
    fail "$harness BYO/external preserves existing bootstrap behavior"
  fi

  proxy_mutant="$TMP/$harness-bootstrap-no-request-proxy.sh"
  proxy_snippet="$TMP/$harness-config-no-request-proxy.sh"
  sed 's/set -- "$@" --proxy "$ZIPBOX_EGRESS_PROXY_URL"/set -- "$@"/' \
    "$bootstrap_source" > "$proxy_mutant"
  if cmp -s "$bootstrap_source" "$proxy_mutant"; then
    fail "$harness proxy mutation did not change the source fixture"
  else
    extract_config_block "$harness" "$proxy_mutant" "$proxy_snippet" ||
      fail "$harness proxy-mutant extraction"
    run_case "$harness" proxy-mutation "$proxy_snippet" success explicit platform
    if contains "$LAST_CASE/curl.log" \
      'catalog proxy=none proxy_count=0 bearer=exact auth_count=1 placeholder=no'; then
      pass "$harness missing-proxy mutation is rejected"
    else
      fail "$harness proxy mutation exercises only the scoped-proxy defect"
    fi
  fi

  header_mutant="$TMP/$harness-bootstrap-placeholder-header.sh"
  header_snippet="$TMP/$harness-config-placeholder-header.sh"
  sed 's/Authorization: Bearer \$token/Authorization: Placeholder $token/' \
    "$bootstrap_source" > "$header_mutant"
  if cmp -s "$bootstrap_source" "$header_mutant"; then
    fail "$harness header mutation did not change the source fixture"
  else
    extract_config_block "$harness" "$header_mutant" "$header_snippet" ||
      fail "$harness header-mutant extraction"
    run_case "$harness" header-mutation "$header_snippet" success explicit platform
    if contains "$LAST_CASE/curl.log" \
      'catalog proxy=exact proxy_count=1 bearer=wrong auth_count=1 placeholder=yes'; then
      pass "$harness wrong-scheme mutation is rejected"
    else
      marker="$(cat "$LAST_CASE/curl.log")"
      fail "$harness header mutation exercises only the scheme defect ($marker)"
    fi
  fi
done

if [ "$fails" -ne 0 ]; then
  printf '\n%s check(s) failed\n' "$fails"
  exit 1
fi
printf '\nall bootstrap catalog egress checks passed\n'
