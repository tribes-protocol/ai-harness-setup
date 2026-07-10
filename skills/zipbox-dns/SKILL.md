---
name: zipbox-dns
description: Manage DNS records under this sandbox's own public hostname with the baked tribes-dns CLI — expose subdomains and set, list, or delete server-pinned A/AAAA records below the apex.
allowed-tools: bash read
---

# DNS management

This sandbox owns one apex hostname: `<slug>.<domain>` (for example
`hish.zipbox.ai`). You may create DNS records **strictly below** that apex —
`api.hish.zipbox.ai`, `app.hish.zipbox.ai` — but you may **never** create or
overwrite a record on the apex itself. The apex is managed by the platform; it
is what points the browser and SSH at this VM, and clobbering it takes the
machine offline.

Everything here is driven by the baked `tribes-dns` CLI. Do not try to edit a
zone file, call a DNS provider API, or reach for an editor — the only supported
surface is the CLI below. Its command surface is frozen; use it verbatim.

> The CLI is `tribes-dns`, not `zipbox-dns`: one rootfs serves both zipbox and
> web/ata sandboxes, so the infra binaries stay product-agnostic (same reason
> the daemon is still called `sandboxd`). The skill carries the product
> identity; the binary does not.

## Only A and AAAA — and the server pins their content

You can set exactly two record types, and **you never supply the address**:

- `A` → the serving host's public **IPv4**. The server derives it; that host's
  HAProxy suffix-routes the traffic back to this VM by SNI/Host.
- `AAAA` → this sandbox's own guest **IPv6**. The server derives it; it points
  straight at this VM.

Every other record type is **refused**: `CNAME`, `TXT`, and `MX`/`NS`/`SRV` are
all rejected. There is no CNAME-to-apex, and there is no free-form TXT. If you
need a name to answer over both IPv4 and IPv6, set both an `A` and an `AAAA`
(that is exactly what `expose` does for you).

## The `tribes-dns` CLI

```
tribes-dns list
tribes-dns expose <label>
tribes-dns set <label> A
tribes-dns set <label> AAAA
tribes-dns delete <label> A
tribes-dns delete <label> AAAA
```

`<label>` is the part **below** the apex (e.g. `api`), and the CLI appends the
apex for you — you never type the full FQDN and you can never aim a record at
the apex by accident. Neither `set A` nor `set AAAA` takes an address argument;
passing one is rejected, because the server pins the content.

## `expose` is the right default — it creates both

```
tribes-dns expose api          # creates BOTH api.<apex> A and api.<apex> AAAA
```

`expose <label>` is dual-stack in one shot: it creates an `A` **and** an `AAAA`
for `<label>.<apex>`, so the name answers over IPv4 (via the host's HAProxy) and
IPv6 (straight to this VM) at once. Reach for `set <label> A` / `set <label>
AAAA` only when you deliberately want a single-stack name; otherwise `expose` is
the simpler default.

## Setting and deleting individual records

```
tribes-dns set api AAAA          # server fills in this sandbox's guest IPv6
tribes-dns set legacy A          # server fills in the host's current IPv4
tribes-dns delete api AAAA       # delete by label + type
tribes-dns delete legacy A
```

Allowed record types: **A, AAAA** — nothing else.

## Listing

```
tribes-dns list                  # every record under your apex
```

## Address records do not self-heal — re-expose after a restore

An `A`/`AAAA` record freezes the address the server pinned **at the moment you
set it**. A restore, or a tier upgrade, re-places the VM onto a different host
with a new public IPv6 and a new host IPv4 — and your literal records do not
follow that move. They silently **rot** until you re-point them.

So after any restore or host-move, **re-run `expose <label>`** (or `set`) for
every name you created here to re-pin it to the new addresses. There is no
self-healing record type anymore; re-exposing is the recovery step.

## Quotas and lifecycle

- **30 records** maximum under your apex.
- **10 mutations per minute** (`expose` / `set` / `delete` all count).
- Records **survive** archive and restore — but their pinned addresses go stale
  across a host-move, so re-run `expose` after a restore (see above).
- Records are **deleted** when the sandbox is **destroyed or stopped** — a
  stopped sandbox releases its name for reuse, so treat "stop" like "destroy"
  for anything you've set here.

## Serving a web app on a subdomain

DNS only makes a name resolve; it does not put a web server behind it. To
terminate TLS and reverse-proxy a subdomain to a local port, create the DNS
record here first, then add the site with the Caddy CLI — see the
`zipbox-caddy` skill (`zipbox-caddy/SKILL.md`). Creating DNS **before** the Caddy
site matters: Caddy's ACME issuance fails on a name that does not yet resolve.

## If the CLI is missing

Older sandboxes may not have DNS self-service. Degrade gracefully:

```
command -v tribes-dns || echo "this sandbox predates DNS self-service"
```
</content>
</invoke>
