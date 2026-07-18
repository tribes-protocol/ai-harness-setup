#!/bin/sh
# Render the agent primer (AGENTS.md, + CLAUDE.md for harnesses that read it)
# from the pristine template, substituting the box's CURRENT identity.
#
# Why this exists as its own script, called from BOTH bootstrap.sh and launch.sh:
# bootstrap.sh runs ONCE, and its sed CONSUMES the placeholders — so anything it
# stamped is frozen for the life of the disk. That is wrong for every value here:
#
#   - __HOST__  the guest's OS hostname is the BOOT SLUG (the baked warm-pool
#               name). A claim adds the chosen name as a DNS alias + vhost and
#               does NOT reboot the VM, so `hostname` NEVER becomes the claimed
#               public name. A box bootstrapped in the warm pool therefore froze
#               a primer saying "you are live at <pool-slug>" — and since the
#               agent auto-loads AGENTS.md, it was fed a WRONG public URL by
#               default. The control plane passes the real one as
#               TRIBES_PUBLIC_HOST once the name is claimed.
#   - identity  a box bootstrapped BEFORE its agent_identities row is bound has
#               no TRIBES_IDENTITY_* in env, so the once-only sed froze "none"
#               for email/EVM/SOL permanently.
#
# Running this every launch (the same restore-safety pattern launch.sh already
# uses for the proxy token) re-renders from the untouched template with the live
# env, so a stale or "none" primer SELF-HEALS on the next launch and the values
# survive restore. Idempotent: it always renders from the template, never from
# the already-substituted output.
#
# POSIX sh. Never fails the caller: a fetch/render problem leaves the existing
# primer in place rather than truncating it or aborting boot.
set -u

WORKSPACE="${TRIBES_WORKSPACE:-/root/workspace}"
# The pristine, placeholder-bearing copy. Kept outside the workspace so the user
# never sees it and an agent editing AGENTS.md can't corrupt the render source.
TEMPLATE="${TRIBES_PRIMER_TEMPLATE:-/opt/tribes/AGENTS.md.tmpl}"

# --- obtain the template ----------------------------------------------------
# Cached copy first (offline-safe, and keeps launch off the network on the
# interactive boot path); fetch only when it's missing.
if [ ! -s "$TEMPLATE" ]; then
  RAW_BASE="$(echo "${TRIBES_HARNESS_REPO:-https://github.com/tribes-protocol/ai-harness-setup}" | sed 's#//github\.com#//raw.githubusercontent.com#')"
  REF="${HOST_HARNESS_REF:-main}"
  mkdir -p "$(dirname "$TEMPLATE")" 2>/dev/null || true
  curl -fsSL "$RAW_BASE/$REF/AGENTS.md" -o "$TEMPLATE.part" 2>/dev/null &&
    [ -s "$TEMPLATE.part" ] && mv "$TEMPLATE.part" "$TEMPLATE" || rm -f "$TEMPLATE.part"
fi
[ -s "$TEMPLATE" ] || exit 0

# --- resolve the current values --------------------------------------------
# TRIBES_PUBLIC_HOST is the claimed public FQDN from the control plane and is the
# ONLY authoritative source; $HOSTNAME/`hostname` are the boot slug and are just a
# last-resort fallback so a box still gets a plausible primer if the var is absent.
host="${TRIBES_PUBLIC_HOST:-${HOSTNAME:-$(hostname 2>/dev/null || true)}}"
email="${TRIBES_IDENTITY_EMAIL:-none}"
evm="${TRIBES_IDENTITY_EVM_ADDRESS:-none}"
sol="${TRIBES_IDENTITY_SOL_ADDRESS:-none}"

# --- render -----------------------------------------------------------------
# Render to a temp file and move into place, so a failure never leaves a
# half-written primer. `|` delimiters + these values (hostnames, emails, 0x/base58
# addresses) carry no `|`, matching the substitution bootstrap.sh already used.
out="$WORKSPACE/.AGENTS.md.rendering"
sed -e "s|__HOST__|$host|g" \
    -e "s|__EMAIL__|$email|g" \
    -e "s|__EVM__|$evm|g" \
    -e "s|__SOL__|$sol|g" \
    "$TEMPLATE" > "$out" 2>/dev/null || { rm -f "$out"; exit 0; }
[ -s "$out" ] || { rm -f "$out"; exit 0; }
mv "$out" "$WORKSPACE/AGENTS.md"

# Harnesses that read CLAUDE.md get the same primer (bootstrap.sh did this too).
if [ "${TRIBES_PRIMER_ALSO_CLAUDE_MD:-0}" = "1" ]; then
  cp "$WORKSPACE/AGENTS.md" "$WORKSPACE/CLAUDE.md" 2>/dev/null || true
fi

exit 0
