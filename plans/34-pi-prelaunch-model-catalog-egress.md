# 34 — Pi pre-launch model-catalog egress plan

**Upstream base:** `e80f82573dba307e0ea83f50de07117519da30cc` (`main`)  
**Branch:** `fix/p27-pi-prelaunch-proxy-v1`  
**External issue:** `tribes-protocol/ai-harness-setup#34`  
**Terminal release blocker:** `tribes-protocol/terminal#2603`  
**Project 27 item:** `PVTI_lADOBZZXps4Bdfe2zgz40uA`

## Destination

Pi's per-launch OpenRouter model-catalog request must use the platform's supported
egress path and header shape before it rewrites `models.json`:

- In explicit-proxy mode, the catalog curl uses
  `ZIPBOX_EGRESS_PROXY_URL` for that request only.
- In transparent-MITM or no-proxy mode, the same request remains direct.
- In both modes, the OpenRouter placeholder appears exactly once in an
  `Authorization: Bearer <placeholder>` header so the injector preserves a valid
  upstream authorization scheme.
- A failed or empty catalog still falls back to `TRIBES_LLM_MODEL`.
- BYO/external launches remain outside the platform-funded catalog branch.

The later launcher-wide `HTTP_PROXY`/`HTTPS_PROXY` exports remain unchanged; this
fix does not route unrelated launcher traffic through the allowlisted tollbooth.

## Assumptions and scope

- `TRIBES_LLM_MODEL`, a non-empty `OPENROUTER_API_KEY`, and an existing Pi
  `models.json` remain the by-construction platform-funded guard.
- `ZIPBOX_EGRESS_PROXY_URL` is present only in explicit-proxy mode and absent in
  transparent-MITM/BYO/external mode, per `CONTRACT.md` and the
  `zipbox-egress` skill.
- OpenRouter's `/api/v1/models` endpoint requires the `Bearer` authorization
  scheme; both platform injectors replace the placeholder token without changing
  that scheme.
- Scope is limited to `pi/launch.sh`, deterministic regression coverage, and this
  plan. Other launchers are audited for the same authenticated pre-export request
  pattern and changed only if the audit proves a parallel release blocker.

## Implementation

1. Build the Pi catalog curl argument list without evaluating environment values
   as shell syntax.
2. Add a request-scoped `--proxy "$ZIPBOX_EGRESS_PROXY_URL"` only when the URL is
   non-empty.
3. Change the catalog authorization header to
   `Authorization: Bearer $token`.
4. Preserve the existing parsing, atomic file replacement, failure fallback,
   platform guard, late proxy exports, and final `exec pi`.

## Deterministic and mutation-sensitive proof

Use a temporary `HOME`, seeded `.pi/agent/models.json`, and stubbed `curl`, `pi`,
and primer renderer so tests make no network calls and expose no credentials.

- Explicit-proxy success must observe the exact request-scoped proxy argument and
  exact Bearer header, and consume multiple live catalog models in `models.json`.
- Removing the request-scoped proxy argument must fail independently.
- Restoring the invalid `Placeholder` scheme must fail independently.
- Explicit-proxy catalog failure or empty output must retain the single configured
  fallback model.
- MITM/no-proxy success must use the exact Bearer header with no proxy argument and
  consume the live catalog.
- BYO/external fixtures must not call the catalog or rewrite the user's Pi config.
- Captured stdout/stderr and test diagnostics must not contain the token or proxy
  URL.
- All repository shell tests, shell syntax checks, and available lint/format
  checks run serially at low CPU priority.

Audit all nine launcher directories for authenticated provider requests that occur
before their explicit-proxy exports. Record the result in the implementation PR;
do not broaden this patch for unauthenticated probes, config-only headers, or
intentional GitHub installer fetches.

## Security and rollback

Environment-provided token and proxy values are passed as quoted curl arguments,
never evaluated, persisted to logs, or echoed. The placeholder remains stored only
where Pi already stores its generated provider configuration. The request remains
time-bounded and keeps the existing silent catalog fallback.

Rollback is a revert of the implementation commit. That restores the previous
catalog behavior without changing bootstrap output, BYO/external configuration, or
launcher-wide networking.

## Board, PR, and release boundary

Push and read back this plan-only commit before source edits. After implementation,
push the exact clean head, open a PR to external `main`, assign `hishboy`, link
issue #34 for closure on merge, add the PR to Project 27 in **In review**, and keep
#34 **In progress** until the PR is merged. Do not merge from this worker.

Report the exact plan SHA, implementation head/base, PR node/project item, and CI
receipts to the release coordinator. Terminal #2603 may advance its immutable
delivery pins only after root merges the external PR and supplies an exact
descendant-of-`e80f825` merge SHA. This work records no live QA or certification
PASS.

## Scope amendment — OpenClaw and OpenCode bootstrap catalogs

After the recoverable Pi implementation checkpoint
`81e5f78647e4959562ec34b3f86fc0f51c6c7057`, the release coordinator expanded
#34 to cover the two equivalent one-shot catalog defects found during the
nine-launcher audit:

- `openclaw/bootstrap.sh` sends its authenticated OpenRouter `/models` request
  with the invalid `Placeholder` authorization scheme and no request-scoped
  explicit proxy.
- `opencode/bootstrap.sh` has the same invalid scheme and missing
  request-scoped explicit proxy.

These bootstraps must use the same safe argument construction as Pi: an exact
`Authorization: Bearer $token` header in both egress modes and an exact
`--proxy "$ZIPBOX_EGRESS_PROXY_URL"` argument only when the explicit proxy URL is
present. They must not export a global proxy or route primer, package, skill, or
other bootstrap traffic through the provider allowlist.

Preserve each harness's existing catalog parsing and configured-model fallback.
Transparent-MITM remains direct. BYO/external guards and their existing config
cleanup/minimal-config behavior remain unchanged. Token and proxy values remain
quoted arguments and must not appear in stdout, stderr, or test diagnostics.

Add deterministic production-snippet fixtures for OpenClaw and OpenCode using a
temporary `HOME`, committed seed configs, and a stubbed catalog curl. Cover
explicit-proxy success and failure, MITM success and empty/failure fallback,
BYO/external behavior, exact generated catalog consumption, and secret-free
output. Add independent mutations that remove only the request-scoped proxy and
restore only the invalid authorization scheme; each mutation must be exercised
and rejected for both bootstraps. Keep the existing Pi mode/fallback/BYO/security
and independent-mutation proof green, wire all new coverage into CI, and rerun
the full serial low-priority shell suite.

## CI correction amendment — portable production-block extraction

PR #35 run `30041341760` proved the product changes and Pi suite green, then
failed the new bootstrap suite before exercising either production block.
Ubuntu's `awk` warns that `\$` is not a portable string escape and treats it as a
plain dollar sign; the resulting regular-expression start marker matches
neither bootstrap. The local awk implementation accepted that escape, so this is
a deterministic cross-implementation test-fixture defect.

Replace the two regex start markers with exact literal prefixes and select them
using `index($0, start) == 1`. Do not change product code or weaken any mode,
fallback, BYO, secret-output, or semantic-mutation assertion. First reproduce the
failed extraction with the CI-compatible awk behavior where available, then run
both catalog suites plus the full serial low-priority shell gates. Push and read
back this plan-only amendment before editing the test fixture.
