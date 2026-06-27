#!/bin/sh
# Cline harness bootstrap — runs ONCE on first boot, as root, cwd /workspace, sh.
#
# WHY NO COMMITTED SEED CONFIG (cline is the contract's documented exception):
# Every other harness commits a real, version-controlled config file with
# __TRIBES_*__ placeholders that bootstrap.sh seds. Cline has none — its
# provider config is produced by the `cline auth openai-compatible ...` CLI
# command, which writes cline's OWN provider file (~/.cline/data/settings/
# providers.json) at runtime from the live proxy/token/model. That command
# needs the `cline` binary plus runtime creds, so it is inherently runtime and
# there is no static file to commit (no heredoc to convert to a seed file).
#
# Installs the Cline CLI ONLY. The `cline auth` command that writes the provider
# file is NOT here — it lives in launch.sh and runs EVERY boot, so a PAUSE ->
# RESTORE re-auths with the freshly re-minted TRIBES_API_KEY (the token a restore
# re-mints would otherwise stay the stale, revoked one baked at first boot). Cline
# has no env-based proxy config and no theme support (hardcoded palette).
set -e

# --- install ----------------------------------------------------------------
command -v cline >/dev/null 2>&1 ||
  npm install -g --no-fund --no-audit cline@latest

# --- seed the shared agent primer -------------------------------------------
# Seed the shared agent primer from the repo root (single source of truth).
RAW_BASE="$(echo "${TRIBES_HARNESS_REPO:-https://github.com/tribes-protocol/ai-harness-setup}" | sed 's#//github\.com#//raw.githubusercontent.com#')"
curl -fsSL "$RAW_BASE/main/AGENTS.md" -o /workspace/AGENTS.md 2>/dev/null || true
host="${HOSTNAME:-$(hostname 2>/dev/null || true)}"
[ -n "$host" ] && [ -e /workspace/AGENTS.md ] && sed -i "s|__HOST__|$host|g" /workspace/AGENTS.md

# --- proxy-routed config: see launch.sh -------------------------------------
# The `cline auth openai-compatible ...` command that writes cline's provider
# file (~/.cline/data/settings/providers.json) is deliberately in launch.sh, NOT
# here: it must re-run on EVERY boot so a RESTORE picks up the re-minted token
# (running it once here would leave a restored box authed with the revoked key).

# --- safety net -------------------------------------------------------------
# Belt-and-suspenders: no file under /workspace may survive with a raw
# __TRIBES_* placeholder. cline has no committed seed config (auth is a runtime
# command), so this is a no-op guard. AGENTS.md only carries __HOST__, so it is
# not matched.
# NEVER delete *.sh — bootstrap.sh/launch.sh legitimately contain __TRIBES_ in
# their sed patterns/fallbacks; only NON-script files with a raw placeholder are
# broken config and get removed.
grep -rl "__TRIBES_" /workspace 2>/dev/null | while IFS= read -r f; do
  case "$f" in *.sh) ;; *) rm -f "$f" ;; esac
done
