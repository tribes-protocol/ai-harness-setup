---
name: zipbox-dns
description: Manage DNS records under this sandbox's own public hostname with the baked tribes-dns CLI — expose subdomains and set, list, or delete A/AAAA/CNAME/TXT records below the apex.
allowed-tools: bash read
---

# DNS management

This sandbox owns one apex hostname: `<slug>.<domain>` (for example
`hish.zipbox.ai`). You may create DNS records **strictly below** that apex —
`mail.hish.zipbox.ai`, `_dmarc.hish.zipbox.ai`, `api.hish.zipbox.ai` — but you
may **never** create or overwrite a record on the apex itself. The apex is
managed by the platform; it is what points the browser and SSH at this VM, and
clobbering it takes the machine offline.

Everything here is driven by the baked `tribes-dns` CLI. Do not try to edit a
zone file, call a DNS provider API, or reach for an editor — the only supported
surface is the CLI below. Its command surface is frozen; use it verbatim.

> The CLI is `tribes-dns`, not `zipbox-dns`: one rootfs serves both zipbox and
> web/ata sandboxes, so the infra binaries stay product-agnostic (same reason
> the daemon is still called `sandboxd`). The skill carries the product
> identity; the binary does not.

## The `tribes-dns` CLI

```
tribes-dns list
tribes-dns expose <label>
tribes-dns set <name> A                     [--ttl N]
tribes-dns set <name> AAAA                  [--ttl N]
tribes-dns set <name> CNAME <target>        [--ttl N]
tribes-dns set <name> TXT <content>         [--ttl N]
tribes-dns delete <name> <type> [content]
```

`<name>` / `<label>` is the part **below** the apex (e.g. `mail`), and the CLI
appends the apex for you — you never type the full FQDN and you can never aim a
record at the apex by accident.

## `expose` is the right default — it self-heals

```
tribes-dns expose mail        # creates mail.<apex> as a CNAME -> <apex>
```

`expose` creates a **CNAME pointing at your apex**, not a literal address, and
it stays the recommended default. A CNAME to the apex inherits both of the
apex's records at once: its `AAAA` (straight to this VM over IPv6) and its `A`
(the current host's IPv4, which that host's HAProxy suffix-routes back to this
VM by SNI/Host) — so one record gives you dual-stack for free.

It also **self-heals**. A restore, or a tier upgrade, re-places the VM onto a
different host with a new public IPv6 and a new host IPv4 — the platform
re-points the apex record for you, and a CNAME to the apex follows that change
automatically. A literal `A`/`AAAA` record you set by hand does not: it freezes
whatever address it was given, silently **rots** the moment the VM moves, and
you own noticing and re-pointing it.

## Why address records exist at all

Reach for a literal `A` or `AAAA` record only when you hit **RFC 1034: a CNAME
cannot coexist with any other record at the same name.** The moment a name
needs both an address and a TXT record — an `_acme-challenge` TXT for a
DNS-01 certificate, a vendor domain-verification token on the same hostname —
CNAME is impossible there, and `A`/`AAAA` is the only way to give that name an
address at all. That's the *only* reason to use them; everything else should
go through `expose`.

Corollary: running `expose <label>` on a name that already has a TXT record
will fail with a conflict — a CNAME must be alone at its name.

## Setting other record types

```
tribes-dns set api        AAAA               # server fills in this sandbox's IPv6
tribes-dns set legacy     A                   # server fills in the host's current IPv4
tribes-dns set www        CNAME hish.zipbox.ai
tribes-dns set _dmarc     TXT   "v=DMARC1; p=none; rua=mailto:you@example.com"
tribes-dns set _acme-challenge TXT "<token-from-your-cert-tool>"
```

Allowed record types: **A, AAAA, CNAME, TXT**.

- `A` / `AAAA` take **no content argument** — the server derives the address
  (this sandbox's guest IPv6 for `AAAA`, its host's current IPv4 for `A`).
  Passing an explicit address is rejected.
- `CNAME` must target **your own apex** — the same thing `expose` does for
  you, which is why `expose` is simpler and preferred.
- `TXT` content is free-form. Underscore labels are supported (`_dmarc`,
  `_acme-challenge`, `s1._domainkey`).

Use `--ttl N` on any of them to override the default TTL.

## Listing and deleting

```
tribes-dns list                       # every record under your apex
tribes-dns delete www CNAME           # delete by name + type
tribes-dns delete api AAAA 2a01:4f9:fff1:26::1   # disambiguate by content
```

Pass the optional `content` to `delete` when a name+type has more than one
record and you want to remove just one of them.

## Quotas and lifecycle

- **30 records** maximum under your apex.
- **10 mutations per minute** (`expose` / `set` / `delete` all count).
- Records **survive** archive and restore — they travel with the sandbox to
  its next host.
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
