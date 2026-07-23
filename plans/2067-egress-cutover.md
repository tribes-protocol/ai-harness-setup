# 2067 — harness egress billing cutover plan

**Upstream base:** `c59aa7f6b137ed7693b4a14b1d3a3932cd1e4e57` (`main`)  
**Branch:** `fix/p27-2067-egress-billing-v2`  
**Terminal issue:** `tribes-protocol/terminal#2067`

## Destination

Every platform-funded harness call uses the provider placeholder already supplied by
the terminal control plane and reaches the provider through the selected egress mode:

- MITM mode transparently intercepts the provider hostname.
- HTTP-proxy mode exports `HTTPS_PROXY` and `HTTP_PROXY` from
  `ZIPBOX_EGRESS_PROXY_URL`.

No harness mints an LLM bearer, calls `${API_BASE_URL}/llm/proxy`, or drops the
platform-supplied placeholder. BYO/external launches keep the user's key and do not
force the platform proxy.

## Harness map

| Harness | Current legacy consumer | Cutover |
| --- | --- | --- |
| claude | bootstrap and launch set `/llm/proxy` plus minted auth token | Use OpenRouter-compatible provider endpoint/key/model through egress; preserve Claude wire compatibility only if its client supports the endpoint without a terminal adapter. |
| pi | bootstrap and launch write `/llm/proxy`; launch later removes placeholder | Write `https://openrouter.ai/api/v1`, retain placeholder, export proxy vars in proxy mode. |
| codex | bootstrap writes `/llm/proxy`; launch requires minted token | Write direct OpenRouter endpoint and placeholder through egress. |
| grok | launch points model discovery at `/llm/proxy` and removes placeholder | Point to OpenRouter and retain placeholder through egress. |
| hermes | bootstrap writes `/llm/proxy`; launch removes placeholder | Write OpenRouter endpoint and retain placeholder through egress. |
| openclaw | bootstrap writes `/llm/proxy`; launch removes placeholder | Write OpenRouter endpoint and retain placeholder through egress. |
| opencode | bootstrap writes `/llm/proxy`; launch removes placeholder | Write OpenRouter endpoint and retain placeholder through egress. |
| cline | launch passes `/llm/proxy`; later removes placeholder | Pass OpenRouter endpoint/key and retain placeholder through egress. |

Cursor has no legacy proxy consumer and remains unchanged. Any bootstrap template
placeholder named `__TRIBES_PROXY__` will be renamed to describe the provider endpoint.

## Implementation order

1. Replace the token/API-base guard with a billing-mode signal based on the presence of
   `TRIBES_LLM_MODEL` plus the platform placeholder. Do not invoke
   `tribes-agent-token` for LLM setup.
2. Add one shared shell pattern to each affected launcher:
   - platform mode: keep `OPENROUTER_API_KEY`, select the configured model, set the
     provider endpoint, and export `HTTPS_PROXY`/`HTTP_PROXY` only when
     `ZIPBOX_EGRESS_PROXY_URL` is present;
   - BYO/external mode: preserve existing user credentials and endpoint behavior.
3. Remove every `/llm/proxy`, LLM token-refresh, and placeholder-removal branch.
4. Update `CONTRACT.md`, `AGENTS.md`, and `skills/zipbox-egress/SKILL.md` to state the
   sole-path contract.
5. Replace token-refresh tests with cutover regressions and keep primer/shared-skill
   tests green.

## Mutation-sensitive proof

- Repository search fails if `/llm/proxy` returns outside this historical plan.
- Each affected harness test fails if it invokes `tribes-agent-token` for LLM setup.
- Platform-mode fixtures fail if the placeholder is unset, replaced, or sent without
  the configured MITM/HTTP-proxy path.
- Proxy-mode fixtures fail if `HTTPS_PROXY` and `HTTP_PROXY` are not set to
  `ZIPBOX_EGRESS_PROXY_URL`.
- MITM-mode fixtures fail if proxy variables are fabricated when the URL is absent.
- BYO/external fixtures fail if a user key or user endpoint is overwritten.
- Bootstrap and launch fixtures cover fresh install and subsequent launch.
- A catalog/provider guard proves all platform harnesses select the supported
  OpenRouter endpoint without a local model-price table.

## Verification and release boundary

Run all repository shell tests serially. Confirm zero live `/llm/proxy` references and
zero LLM use of `tribes-agent-token`. Commit and push only this release branch, then
open a PR to `main` for human/root review. Do not merge or push `main`. Terminal release
artifacts must record the immutable external base, plan SHA, implementation head, PR,
and CI result; until the PR is merged, terminal must label the external cutover
`NOT SHIPPED`.
