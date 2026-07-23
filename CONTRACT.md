# Harness contract

## Provider-funded LLM routing

The terminal control plane supplies these values to a pay-per-use harness:

- `TRIBES_LLM_MODEL`: the selected OpenRouter model.
- `OPENROUTER_API_KEY`: a public placeholder, never the real provider key.
- `ZIPBOX_EGRESS_PROXY_URL`: present only for explicit HTTP-proxy mode.

Harnesses call OpenRouter directly:

- OpenAI-compatible clients use `https://openrouter.ai/api/v1`.
- Claude Code uses OpenRouter's Anthropic-compatible
  `https://openrouter.ai/api` endpoint.

The host terminates TLS, swaps the placeholder for the real key, meters the provider
response, and charges the owning wallet. In MITM mode interception is transparent. In
HTTP-proxy mode launchers export:

```sh
export HTTPS_PROXY="$ZIPBOX_EGRESS_PROXY_URL"
export HTTP_PROXY="$ZIPBOX_EGRESS_PROXY_URL"
```

No LLM harness calls a terminal API adapter or mints a terminal bearer. The
`tribes-agent-token` command remains available for unrelated `/agent/*` APIs.

## Platform versus BYO

`TRIBES_LLM_MODEL` plus `OPENROUTER_API_KEY` identifies the platform-funded path.
Harnesses configure their provider only when both are present. They must preserve the
placeholder and must not replace or unset it.

When those values are absent, the harness leaves user credentials and endpoints alone.
`ZIPBOX_EGRESS_PROXY_URL` is also absent for BYO/external launches, so launchers do not
force a user request through the platform proxy.

## File-based harnesses

Committed seed configs use these placeholders:

- `__TRIBES_PROXY__`: the applicable OpenRouter base URL.
- `__TRIBES_TOKEN__`: `OPENROUTER_API_KEY`.
- `__TRIBES_MODEL__`: `TRIBES_LLM_MODEL`.
- `__TRIBES_MODELS__`: a valid provider model map/list.

Bootstrap fills them on first boot. Launch refreshes any file-based key from the live
placeholder so restore never revives stale configuration. A raw `__TRIBES_*` value must
not survive in a non-script runtime file.

## Egress scope

The explicit proxy allowlists catalog provider authorities. Do not export it globally
for unrelated bootstrap/package traffic; launcher exports affect only the harness
process after setup work has completed. MITM mode has no proxy URL and must not
fabricate one.

## Release rules

- Harness changes land on a release branch through a PR; never push `main`.
- Tests must prove zero live legacy LLM-adapter references and zero LLM use of
  `tribes-agent-token`.
- BYO behavior, primer rendering, shared-skill installation, and auto-approval remain
  unchanged.
