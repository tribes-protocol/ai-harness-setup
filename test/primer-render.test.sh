#!/bin/sh
# Regression test for the FROZEN PRIMER bug.
#
# bootstrap.sh runs ONCE and its sed CONSUMES the AGENTS.md placeholders, so every
# value it stamped is frozen for the life of the disk. Two ways that was wrong:
#
#   1. __HOST__  — the guest's OS hostname is the BOOT SLUG (the baked warm-pool
#      name). A claim adds the chosen name as a DNS alias + vhost and does NOT
#      reboot the VM, so `hostname` never becomes the claimed public name. A box
#      bootstrapped in the warm pool froze a primer reading "you are live at
#      <pool-slug>". AGENTS.md is auto-loaded into the agent's context, so the
#      agent was fed a WRONG public URL by default (observed: a box answering
#      "dapper-bison.machina.wtf" when it was actually kobo-h5-ai1.machina.wtf).
#   2. identity — a box bootstrapped BEFORE its agent_identities row was bound had
#      no TRIBES_IDENTITY_* in env, so email/EVM/SOL froze as "none" permanently.
#
# render-primer.sh runs on EVERY launch from the untouched template with the live
# env, so both self-heal. This test simulates a RESTORED/ALREADY-BOOTSTRAPPED disk
# (primer already rendered with the wrong values) and asserts the next launch
# repairs it, and that the repair is stable across repeats (restore-safe).
#
# POSIX sh. Run: sh test/primer-render.test.sh
set -u

REPO="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

RENDER="$REPO/render-primer.sh"
CLAIMED="kobo-h5-ai1.machina.wtf"
POOL_SLUG="dapper-bison"
EMAIL="kobo@machina.wtf"
EVM="0xe447200a5152b14f49956d02859e20c57d6f1de6"
SOL="SoLidentityAddress1111111111111111111111111"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() { printf 'FAIL - %s\n' "$1"; fails=$((fails + 1)); }

# A workspace whose primer is ALREADY rendered (placeholders consumed) with the
# wrong values — exactly what bootstrap.sh left behind on the observed box.
setup() {
  ws="$TMP/ws"; rm -rf "$ws"; mkdir -p "$ws"
  tmpl="$TMP/AGENTS.md.tmpl"
  cp "$REPO/AGENTS.md" "$tmpl"
  sed -e "s|__HOST__|$POOL_SLUG.machina.wtf|g" -e "s|__EMAIL__|none|g" \
      -e "s|__EVM__|none|g" -e "s|__SOL__|none|g" "$tmpl" > "$ws/AGENTS.md"
}

render() {
  TRIBES_WORKSPACE="$ws" TRIBES_PRIMER_TEMPLATE="$tmpl" \
  TRIBES_PUBLIC_HOST="${1-}" TRIBES_IDENTITY_EMAIL="${2-}" \
  TRIBES_IDENTITY_EVM_ADDRESS="${3-}" TRIBES_IDENTITY_SOL_ADDRESS="${4-}" \
  HOSTNAME="$POOL_SLUG" sh "$RENDER"
}

# 1. The headline bug: a frozen pool-slug primer heals to the CLAIMED public host.
setup
grep -q "$POOL_SLUG" "$ws/AGENTS.md" || fail "fixture should start stale"
render "$CLAIMED" "$EMAIL" "$EVM" "$SOL"
if grep -q "$CLAIMED" "$ws/AGENTS.md" && ! grep -q "$POOL_SLUG" "$ws/AGENTS.md"; then
  pass "stale boot-slug host self-heals to the claimed public host"
else
  fail "stale boot-slug host self-heals to the claimed public host"
fi

# 2. The sibling bug: frozen "none" identity values heal once the row is bound.
if grep -q "$EMAIL" "$ws/AGENTS.md" && grep -q "$EVM" "$ws/AGENTS.md" &&
   grep -q "$SOL" "$ws/AGENTS.md" && ! grep -q 'none' "$ws/AGENTS.md"; then
  pass 'frozen "none" identity self-heals to the bound identity'
else
  fail 'frozen "none" identity self-heals to the bound identity'
fi

# 3. No placeholder survives a render — the agent must never read a raw __TOKEN__.
if grep -q '__HOST__\|__EMAIL__\|__EVM__\|__SOL__' "$ws/AGENTS.md"; then
  fail "no placeholder survives the render"
else
  pass "no placeholder survives the render"
fi

# 4. Restore-safety: re-rendering repeatedly is stable (renders from the pristine
#    template, never from its own already-substituted output).
before="$(cat "$ws/AGENTS.md")"
render "$CLAIMED" "$EMAIL" "$EVM" "$SOL"
if [ "$before" = "$(cat "$ws/AGENTS.md")" ]; then
  pass "re-render is idempotent (survives restore / repeated launches)"
else
  fail "re-render is idempotent (survives restore / repeated launches)"
fi

# 5. The claimed host WINS over the guest's boot-slug hostname. This is the seam
#    with the control plane: TRIBES_PUBLIC_HOST is the authoritative FQDN the
#    monorepo emits, and it must never be overridden by the VM's own hostname.
setup
render "$CLAIMED" "$EMAIL" "$EVM" "$SOL"
if grep -q "Public URL:.*$CLAIMED" "$ws/AGENTS.md"; then
  pass "TRIBES_PUBLIC_HOST (control plane) beats the guest hostname"
else
  fail "TRIBES_PUBLIC_HOST (control plane) beats the guest hostname"
fi

# 6. Absent TRIBES_PUBLIC_HOST, fall back to the hostname rather than emitting an
#    empty URL — a degraded primer still beats a broken one.
setup
render "" "$EMAIL" "$EVM" "$SOL"
if grep -q "$POOL_SLUG" "$ws/AGENTS.md" && ! grep -q '__HOST__' "$ws/AGENTS.md"; then
  pass "falls back to the guest hostname when the control plane sends no host"
else
  fail "falls back to the guest hostname when the control plane sends no host"
fi

# 7. A missing/unreadable template must NOT truncate an existing primer.
setup
TRIBES_WORKSPACE="$ws" TRIBES_PRIMER_TEMPLATE="$TMP/nope.tmpl" \
  TRIBES_HARNESS_REPO="http://127.0.0.1:9" sh "$RENDER"
if [ -s "$ws/AGENTS.md" ]; then
  pass "a missing template leaves the existing primer intact"
else
  fail "a missing template leaves the existing primer intact"
fi

[ "$fails" -eq 0 ] || { printf '\n%s test(s) failed\n' "$fails"; exit 1; }
printf '\nall primer-render tests passed\n'
