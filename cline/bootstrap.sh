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
curl -fsSL "$RAW_BASE/main/AGENTS.md" -o /root/workspace/AGENTS.md 2>/dev/null || true
host="${HOSTNAME:-$(hostname 2>/dev/null || true)}"
[ -n "$host" ] && [ -e /root/workspace/AGENTS.md ] && sed -i "s|__HOST__|$host|g" /root/workspace/AGENTS.md

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

# --- shared agent skills (single source of truth, installed at boot) --------
# Install the skill set read-only under /root/skills and wire the native
# (claude/pi) or AGENTS.md loaders. Drive-first (#1914): the shared read-only
# /opt/harnesses drive bakes the pinned catalog AND this installer, so a stock
# boot runs the baked copy and needs no network for skills. The installer is
# fetched only when the drive predates skills (old image, dev backend) or a
# pinned TRIBES_HARNESS_REF (QA) must exercise that branch's own installer.
# Runs after all config writes; fully tolerant, so it never blocks or fails
# the boot.
if [ -z "${TRIBES_HARNESS_REF:-}" ] && [ -f /opt/harnesses/skills/install-skills.sh ]; then
  sh /opt/harnesses/skills/install-skills.sh || true
else
  curl -fsSL --max-time 20 "$RAW_BASE/${TRIBES_HARNESS_REF:-main}/install-skills.sh" | sh || true
fi
