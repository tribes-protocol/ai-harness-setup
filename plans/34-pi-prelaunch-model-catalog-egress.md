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
