#!/bin/sh
# Cline harness bootstrap — runs ONCE on first boot, as root, cwd /root/workspace, sh.
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
REF="${HOST_HARNESS_REF:-main}"
# Cache the PLACEHOLDER-BEARING primer + the renderer outside the workspace, then
# render. Bootstrap runs ONCE and its sed consumes the placeholders, so stamping
# them here alone froze the wrong values for the life of the disk: the guest's
# hostname is the boot slug (a claim never renames the VM), and a box bootstrapped
# before its identity row is bound has no TRIBES_IDENTITY_* and froze "none".
# launch.sh re-runs the renderer every launch so both self-heal.
mkdir -p /opt/tribes 2>/dev/null || true
curl -fsSL "$RAW_BASE/$REF/AGENTS.md" -o /opt/tribes/AGENTS.md.tmpl 2>/dev/null || true
curl -fsSL "$RAW_BASE/$REF/render-primer.sh" -o /opt/tribes/render-primer.sh 2>/dev/null || true
chmod +x /opt/tribes/render-primer.sh 2>/dev/null || true
sh /opt/tribes/render-primer.sh 2>/dev/null || true

# --- proxy-routed config: see launch.sh -------------------------------------
# The `cline auth openai-compatible ...` command that writes cline's provider
# file (~/.cline/data/settings/providers.json) is deliberately in launch.sh, NOT
# here: it must re-run on EVERY boot so a RESTORE picks up the re-minted token
# (running it once here would leave a restored box authed with the revoked key).

# --- safety net -------------------------------------------------------------
# Belt-and-suspenders: no file under /root/workspace may survive with a raw
# __TRIBES_* placeholder. cline has no committed seed config (auth is a runtime
# command), so this is a no-op guard. AGENTS.md only carries __HOST__, so it is
# not matched.
# NEVER delete *.sh — bootstrap.sh/launch.sh legitimately contain __TRIBES_ in
# their sed patterns/fallbacks; only NON-script files with a raw placeholder are
# broken config and get removed.
grep -rl "__TRIBES_" /root/workspace 2>/dev/null | while IFS= read -r f; do
  case "$f" in *.sh) ;; *) rm -f "$f" ;; esac
done

# --- shared agent skills (single source of truth, refreshed at boot) --------
# Install the published skill set read-only under /root/skills and wire the native
# (claude/pi) or AGENTS.md loaders. Runs after all config writes; fully
# tolerant, so it never blocks or fails the boot.
curl -fsSL --max-time 20 "$RAW_BASE/${TRIBES_HARNESS_REF:-main}/install-skills.sh" | sh || true
