# #31 — retired `TRIBES_API_KEY` reference sweep plan

Planning bind: `ai-harness-setup@c59aa7f6b137ed7693b4a14b1d3a3932cd1e4e57`
Terminal census bind:
`terminal@2e74384a97d33337d85c2f2d21dfba4c4e1e0449`

## Scope and safety boundary

This is a plan only. No implementation, credential read, environment read, secret-history search,
key rotation, key revocation, harness cutover, rebake, production action, issue/board change, or CI
action occurred.

The census records only tracked path, reference name, occurrence count, and semantic category. It
does not record matching lines or values. `TRIBES_API_KEY` is a reference name in this artifact,
never a credential value.

The issue premise is narrower than a global deletion. The LLM use is retired in favor of
`tribes-agent-token`, but terminal still contains non-LLM agent API, DNS/caddy, guest-runtime,
wallet, and validation contracts. A filename match is not permission to delete a producer or
consumer.

## Frozen external repository population

Filename-first tracked-source census: **2 files / 6 reference-name occurrences**.

| path                                | occurrences | semantic category                               | planned disposition                                                                             |
| ----------------------------------- | ----------: | ----------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| `CONTRACT.md`                       |           1 | intentional retired-mechanism explanation       | retain; it prevents readers from treating the reference as current                              |
| `test/launch-token-refresh.test.sh` |           5 | live negative enforcement plus test explanation | later expand the negative enforcement; retain the literal only as the forbidden name under test |

No tracked harness `bootstrap.sh`, `launch.sh`, config seed, or skill file matches. That zero is over
the complete 49-blob tracked tree at the bind, not a sample.

## Frozen terminal repository population

Filename-first tracked-source census: **44 files / 176 reference-name occurrences** at the terminal
bind. Terminal is evidence-only in this plan; none of these files may be edited from this branch.

### Live runtime and tooling contracts — 13 files

| path                                                  | category                            |
| ----------------------------------------------------- | ----------------------------------- |
| `apps/api/src/common/env.ts`                          | API environment contract            |
| `apps/api/src/utils/SandboxBootEnv.ts`                | guest boot environment producer     |
| `apps/microvmd/src/common/vmBridgeEnv.ts`             | guest runtime persistence/consumer  |
| `apps/microvmd/src/services/DialogAgent.ts`           | embedded Dialog agent contract      |
| `apps/wallet-cli/src/common/Env.ts`                   | wallet CLI environment contract     |
| `packages/sandboxd-validate/src/RunHarness.ts`        | validation harness runtime          |
| `packages/sandboxd-validate/src/SkillsE2E.ts`         | validation skill runtime            |
| `packages/sandboxd-validate/src/types/Validate.ts`    | validation wire/type contract       |
| `packages/sandboxing/src/db/schema/Sandboxes.ts`      | persisted sandbox schema            |
| `packages/sandboxing/src/shared/types/Sandbox.ts`     | shared boot/runtime type contract   |
| `packages/sandboxing/src/stores/SandboxFleetStore.ts` | persisted sandbox producer/consumer |
| `scripts/sandbox-agent-shell.sh`                      | guest harness dispatcher            |
| `scripts/sandbox-agent-token.js`                      | guest agent bearer fallback/minter  |

These are not classified as obsolete. A later terminal lane must trace each reference to an exact
LLM or non-LLM producer/consumer before proposing an edit.

### Tests, fixtures, and source guards — 14 files

| path                                                             | category                  |
| ---------------------------------------------------------------- | ------------------------- |
| `apps/api/test/fixtures/HarnessBootEnvGates.ts`                  | fixture contract          |
| `apps/api/test/fixtures/harnessGatesSelfTest/alpha/bootstrap.sh` | negative/positive fixture |
| `apps/api/test/fixtures/harnessGatesSelfTest/alpha/launch.sh`    | negative/positive fixture |
| `apps/api/test/fixtures/harnessGatesSelfTest/beta/launch.sh`     | negative/positive fixture |
| `apps/api/test/fixtures/harnessGatesSelfTest/delta/bootstrap.sh` | negative/positive fixture |
| `apps/api/test/fixtures/harnessGatesSelfTest/delta/launch.sh`    | negative/positive fixture |
| `apps/api/test/utils/SandboxBootEnv.test.ts`                     | boot-env regression       |
| `apps/api/test/utils/SandboxBootEnvContract.test.ts`             | boot-env source contract  |
| `apps/microvmd/test/common/vmBridgeEnv.test.ts`                  | guest-runtime regression  |
| `apps/sandboxd/test/FirecrackerBackendRestoreAgentKey.test.ts`   | restore regression        |
| `apps/sandboxd/test/SandboxAgentTokenCli.test.ts`                | bearer CLI regression     |
| `packages/sandboxd-validate/test/SkillsE2E.test.ts`              | validation regression     |
| `packages/sandboxing/test/SandboxFleetStoreAgentKey.test.ts`     | persistence regression    |
| `scripts/extract-harness-boot-gates.sh`                          | source-contract extractor |

Tests may intentionally name a forbidden or compatibility reference. A later terminal change must
preserve negative coverage rather than deleting the test literal to make a census green.

### Historical, decision, QA, and release records — 17 files

| path                                                         | category                                         |
| ------------------------------------------------------------ | ------------------------------------------------ |
| `apps/zipbox/docs/test-suite/D2242-harness-token-refresh.md` | decision/test record                             |
| `apps/zipbox/docs/test-suite/S10-agent-subdomains.md`        | permanent QA record                              |
| `apps/zipbox/docs/test-suite/S3-lifecycle-smoke.md`          | permanent QA record                              |
| `apps/zipbox/docs/test-suite/S8-regression-sweep.md`         | permanent regression record                      |
| `apps/zipbox/docs/test-suite/per-release-delta.md`           | release QA record                                |
| `plans/2067-egress-billing-rearchitecture.md`                | forward plan with historical/current distinction |
| `plans/2421-ppu-egress-reopen.md`                            | investigation record                             |
| `plans/2469-harness-contract-test.md`                        | source-contract plan                             |
| `plans/archive-unarchive-state-restore.html`                 | historical evidence artifact                     |
| `plans/qa-evidence/STAGE6-EVIDENCE-DESIGN.md`                | QA evidence design                               |
| `plans/ready-bodies-20260720T152318Z.md`                     | issue-body snapshot                              |
| `plans/release-config.md`                                    | release configuration record                     |
| `plans/sandbox-token-freshness.html`                         | historical evidence artifact                     |
| `release-testing/squashing-july8-bugs-like-a-boss.md`        | release test record                              |
| `releases/20260713-lets-go-july-13-CHANGELOG.md`             | immutable release history                        |
| `releases/20260717-lets-go-july-13-QA-CERT-OVERLAY.md`       | certification history                            |
| `takeover-sandboxd-nested-virtualization.md`                 | handoff/history record                           |

Historical records must not be rewritten to pretend the old mechanism never existed. Forward
instructions may be corrected only when they imply that the retired LLM use remains current.

## Later implementation lanes

### E1 — external negative-invariant expansion

One-file edit population: `test/launch-token-refresh.test.sh`.

Expand the current three-launcher absence assertion to all eight proxy-capable harnesses—Claude,
Cline, Codex, Grok, Hermes, OpenClaw, OpenCode, and Pi—and cover both `bootstrap.sh` and
`launch.sh`. Keep Cursor outside this population because its current contract is native/BYO and it
does not use the metered LLM proxy.

Safe stop: if any harness file matches, classify the use before editing it. Do not delete,
substitute, print, rotate, or revoke a credential.

### T1 — terminal producer/consumer classification

Separate terminal branch and worktree. Trace all 13 live files and their 14 tests by consumer:

- retired LLM-only;
- current non-LLM `/agent/*`, DNS/caddy, wallet, or validation use;
- compatibility fallback with an explicit removal gate;
- negative test/reference only.

Safe stop: an unclassified runtime reference blocks removal. Issue #31 prose does not override
current source behavior.

### T2 — terminal surgical cleanup

Only after T1, edit proven retired LLM-only references and their directly coupled tests. Keep
non-LLM and negative-test references. External and terminal changes remain separate commits and
reviews.

### T3 — terminal documentation/accounting

Correct forward instructions after source behavior is known. Preserve historical/changelog facts.
Do not add release accounting until a terminal implementation plan proves a behavior or
certification change.

## Tests and acceptance

External implementation acceptance:

1. filename-only census still has exactly two intentional files;
2. the test enforces absence across all 16 proxy-capable bootstrap/launch files;
3. removing any harness from the enforced population fails;
4. inserting the retired reference name into any enforced harness file fails;
5. `sh test/launch-token-refresh.test.sh` passes;
6. `sh test/primer-render.test.sh` passes;
7. `sh test/shared-skills-install.test.sh` passes;
8. `sh test/skills-contract.test.sh` passes;
9. `sh test/skills-drive-install.test.sh` passes.

Terminal acceptance belongs to its later plan: exact 44-file population accounting, consumer
classification, focused tests for every edited producer/consumer, and a final allowlist of only
intentional historical, compatibility, and negative-test references.

## Rollout and rollback

The external change is test enforcement only. It does not change harness runtime behavior and
requires no rebake, key operation, or production action. Roll back by reverting that isolated test
commit.

Push and CI may run only on the isolated P27 work branch
`fix/p27-31-tribes-api-key-sweep` and an explicitly approved release branch. Never push or merge
directly to external `main`; a later landing requires the repository's reviewed PR/release flow.
Terminal accounting must cite the exact landed external commit, not a branch name.

Any later terminal cleanup ships through terminal's own review, test, and release accounting. A
terminal rollback reverts only its cleanup commits; it never restores or changes a key value.

## Owner-only terminal questions

If terminal accounting is authorized, add only these unresolved decisions to terminal
`QUESTIONS.md`:

1. Does the credential owner require rotation of any static agent key after reference cleanup?
2. Does the credential owner require revocation of any existing static key or minted JWT?

No source evidence can answer those operational decisions. Cleanup does not itself authorize
rotation or revocation. The intended terminal accounting path is `/root/Developer/terminal/QUESTIONS.md`;
all other terminal release-accounting paths remain undecided until T1/T2 establish an actual
behavior change.
