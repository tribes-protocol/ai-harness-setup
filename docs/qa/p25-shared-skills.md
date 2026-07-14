# P25 shared skills staging check

Run this check only in staging on disposable sandboxes created after the
ai-harness shared-skills change is merged. Browser setup installs Chromium and
system packages into the sandbox on first use. Do not run the check in a
production sandbox or one that contains needed work.

## Preconditions

- Use a newly created, post-bake sandbox rather than a restored older sandbox.
- Create one Claude harness and one Codex or Pi harness.
- After the trading-harness sync lands, create one ATA harness as the inheritance
  check.
- Keep the sandbox API credential private. Do not print shell tracing, request
  headers, cookies, browser storage, or saved browser state.

## Catalog, permissions, and discovery

1. List the direct children of `/root/skills`. The zipbox catalog must be exactly
   `zipbox-browser`, `zipbox-caddy`, `zipbox-dns`, `zipbox-email`, and
   `zipbox-websearch`; each directory must contain `SKILL.md`.
2. Inspect numeric modes. `/root/skills` and every directory below each
   `zipbox-*` entry must be `0555`; every shared file must be `0444`.
3. On Claude, confirm `~/.claude/skills` resolves to `/root/skills`. On a harness
   with an existing real skills directory, confirm every `zipbox-*` entry is a
   symlink to its matching `/root/skills/<slug>` directory and pre-existing
   non-zipbox skills remain present.
4. Exit and relaunch each harness twice. Confirm the catalog, modes, and symlink
   targets do not change; no `zipbox-*` duplicate or stale legacy
   `~/.agent-skills` copy appears; the marker-fenced `## Skills` block in the
   workspace `AGENTS.md` appears once.

## Web search exercise

Ask the fresh Codex or Claude agent to use `zipbox-websearch` to find the current
official documentation page for Playwright CLI and return the page title and
source URL. It must use the sandbox-authenticated search endpoint, return ranked
results, cite the selected URL, and avoid printing the bearer credential.

Repeat with one known public documentation URL and ask the agent to extract its
readable text. Empty output, an auth failure after one retry, or a missing source
URL is a failure.

## Browser exercise

Ask the same agent to use `zipbox-browser` to open a JavaScript-rendered public
page, wait for a stable page element, capture a snapshot, read the page title,
and close the named session. First use may install Playwright CLI, Chromium, and
required Linux packages. The agent must remain headless, use a desktop-like user
agent and viewport, avoid CAPTCHA or access-control bypass, and close the session
when done.

## Trading inheritance

After the downstream trading sync merges, repeat the catalog check in a new ATA
sandbox. The five shared `zipbox-*` skills must be present without removing or
renaming any trading-only skill. `zipbox-websearch` and `zipbox-browser` must use
the same shared content and the ATA client skill paths must not contain divergent
copies.
