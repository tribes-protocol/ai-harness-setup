---
name: zipbox-dns
description: Manage DNS records under this sandbox's own public hostname with the baked tribes-dns CLI — expose subdomains and set, list, or delete A/AAAA/CNAME/NS/TXT/MX/SRV records below the apex.
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
tribes-dns set <name> <type> <content> [--ttl N] [--priority N]
tribes-dns set <name> SRV --data '<priority> <weight> <port> <target>'
tribes-dns delete <name> <type> [content]
```

`<name>` / `<label>` is the part **below** the apex (e.g. `mail`), and the CLI
appends the apex for you — you never type the full FQDN and you can never aim a
record at the apex by accident.

## `expose` is the right default — it self-heals

```
tribes-dns expose mail        # creates mail.<apex> as a CNAME -> <apex>
```

`expose` creates a **CNAME pointing at your apex**, not a literal address. Prefer
it for anything that should live at your VM. When the sandbox is paused and later
restored onto a **different host**, the VM gets a **new public IPv6** — a CNAME
to the apex follows that change automatically, because the apex record is
re-pointed by the platform. A literal `A`/`AAAA` record you set by hand freezes
the old address: it will **silently rot** after a restore and you own noticing
and re-pointing it. Only set a literal address record when it points at
something that is genuinely not this VM.

## Setting other record types

```
tribes-dns set www   CNAME hish.zipbox.ai
tribes-dns set api    AAAA  2a01:4f9:fff1:26::1
tribes-dns set legacy A     203.0.113.10
tribes-dns set @mx    MX    mailhost.example.com --priority 10
tribes-dns set _dmarc TXT   "v=DMARC1; p=none; rua=mailto:you@example.com"
tribes-dns set _sip._tcp SRV --data '10 60 5060 sip.example.com'
```

Allowed record types: **A, AAAA, CNAME, NS, TXT, MX, SRV**. `MX` takes
`--priority`; `SRV` takes `--data '<priority> <weight> <port> <target>'`. Use
`--ttl N` to override the default TTL.

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
- Records are **preserved** across stop, archive, and restore — they travel with
  the sandbox.
- Records are **deleted** when the sandbox is destroyed.

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
