#!/bin/sh
# OpenClaw harness launch — runs on EVERY launch, as root, cwd /root/workspace, sh.
# OpenClaw config is entirely FILE-based (exec-approvals.json + openclaw.json,
# written by bootstrap.sh) — there is no env-based config and no theme knob.

# --- restore-safety: refresh the proxy token from the LIVE env --------------
# The bearer is a short-lived ES256 JWT minted in-VM by tribes-agent-token (signed
# with the P-256 agent key). bootstrap.sh baked one into openclaw.json (apiKey) on
# first boot; it goes stale (expiry, or a PAUSE -> RESTORE onto a disk holding the
# previous boot's token), so re-mint and re-point the on-disk apiKey every launch.
# Match the apiKey field value so the swap works for any prior token (a JWT has no
# sed-special chars). No-op on a cold boot; skipped on a keyless BYO/unset box
# (file removed, or no mintable key). Config paths are $HOME-relative — the
# dispatcher decides HOME (old: workspace, new: /root).
# --- re-render the agent primer (restore-safety, like the token refresh) -----
# bootstrap.sh's sed CONSUMED the primer placeholders, freezing whatever the box
# knew at first boot: the boot-slug hostname (a claim adds a DNS alias and never
# renames the VM) and "none" identity values if the agent_identities row wasn't
# bound yet. AGENTS.md is auto-loaded into the agent's context, so a frozen primer
# feeds it a WRONG public URL by default. Re-render from the untouched template
# with this launch's live env so both self-heal and survive restore.
sh /opt/tribes/render-primer.sh 2>/dev/null || true

CFG="$HOME/.openclaw/openclaw.json"
token="$(tribes-agent-token 2>/dev/null || true)"
if [ -n "$token" ] && [ -f "$CFG" ]; then
  sed -i "s|\"apiKey\": \"[^\"]*\"|\"apiKey\": \"$token\"|" "$CFG"
fi

# --- BYO onboarding ----------------------------------------------------------
# In BYO mode bootstrap.sh deleted the proxy-seeded openclaw.json, and
# `openclaw tui --local` then boots a normal-looking TUI on a default model
# with NO credentials — no auth guidance, every message fails. On the first
# BYO boot run `openclaw onboard` (interactive onboarding for credentials,
# gateway, and workspace) so the user lands in setup; the /opt/tribes marker
# keeps later relaunches out of the wizard (rerun anytime: `openclaw onboard`).
if [ ! -f "$CFG" ] && [ ! -e /opt/tribes/.openclaw-onboard-offered ]; then
  mkdir -p /opt/tribes && : > /opt/tribes/.openclaw-onboard-offered
  openclaw onboard || true
fi

# --- shared agent skills: refresh to the latest published set every launch ---
# This is the mechanism that makes template-based sandboxes pick up newly
# published skills without any repo change. Tolerant + tight timeout; a slow or
# failed fetch leaves the launch (and any prior install) unaffected.
SKILLS_RAW_BASE="$(echo "${TRIBES_HARNESS_REPO:-https://github.com/tribes-protocol/ai-harness-setup}" | sed 's#//github\.com#//raw.githubusercontent.com#')"
curl -fsSL --max-time 10 "$SKILLS_RAW_BASE/${TRIBES_HARNESS_REF:-main}/install-skills.sh" | sh || true

# `tui --local` opens the local agent TUI directly against the pre-seeded config.
exec openclaw tui --local
