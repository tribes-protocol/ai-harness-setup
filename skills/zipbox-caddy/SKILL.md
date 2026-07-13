---
name: zipbox-caddy
description: Safely add or remove HTTPS reverse-proxy sites in this sandbox's in-VM Caddy with the baked tribes-caddy CLI — never hand-edit the Caddyfile, because a bad config kills all browser access to the machine.
allowed-tools: bash read
---

# Caddy web server

**Danger first: Caddy is the only thing standing between the browser and this
machine.** Inside this VM, Caddy terminates TLS on the sandbox's apex hostname
and reverse-proxies it to `127.0.0.1:8080`, which is the xterm.js web-terminal
bridge — the terminal you are looking at in the browser. If Caddy dies, or you
hand it an invalid config, **browser access to this machine is gone**: the web
terminal goes dark and any site you were serving stops answering. Only **SSH**
survives an unhealthy Caddy. Treat every change to it as load-bearing.

## Why you cannot `reload` or `stop` Caddy here

Caddy is supervised by **runit**, not systemd, and it runs with `admin off`.
That means the usual levers do **not** work:

- `caddy reload` — no admin endpoint, so it fails.
- `caddy stop` — same; and even if it stopped, runit would just respawn it.

The **only** way to change Caddy's behaviour is **edit-then-restart**. A restart
briefly drops the web-terminal websocket (~1s); the browser reconnects on its
own, so a healthy restart looks like a momentary blip, not an outage.

## Never hand-edit the Caddyfile — use `tribes-caddy`

Do **not** open `/etc/caddy/Caddyfile` in an editor. A typo there is exactly how
you lose the browser. Use the baked `tribes-caddy` CLI, which writes a
**candidate** config, **validates** it, swaps it in **atomically**,
**health-polls** the web terminal after the restart, and **auto-rolls-back** to
the previous config if anything is wrong. A **last-known-good** config is kept
and restored automatically, so a bad change cannot brick the box. Its command
surface is frozen; use it verbatim.

> The CLI is `tribes-caddy`, not `zipbox-caddy`: one rootfs serves both zipbox
> and web/ata sandboxes, so the infra binaries stay product-agnostic (same
> reason the daemon is still called `sandboxd`). The skill carries the product
> identity; the binary does not.

```
tribes-caddy list
tribes-caddy add <host> <upstream>
tribes-caddy rm <host>
tribes-caddy validate
tribes-caddy restart
```

## Adding a site (create the DNS record first)

```
tribes-caddy add app.hish.zipbox.ai 127.0.0.1:3000
```

`add <host> <upstream>` creates an HTTPS site for `<host>` that reverse-proxies
to a local `<upstream>` (e.g. `127.0.0.1:3000`) and lets Caddy obtain a
certificate for it.

**Create the DNS record before you add the Caddy site.** Caddy asks a public CA
(ACME) for a certificate the moment the site loads, and issuance **fails on a
name that does not resolve** — every failed attempt is a wasted issuance you can
get rate-limited on. Point the name at this VM first with the `zipbox-dns` skill
(`zipbox-dns/SKILL.md`), then run `tribes-caddy add`.

## Removing a site and checking state

```
tribes-caddy list                     # every site Caddy currently serves
tribes-caddy rm app.hish.zipbox.ai    # remove a site (restart + health-poll)
tribes-caddy validate                 # dry-run: is the current config valid?
tribes-caddy restart                  # apply after a validated change
```

## Guardrails

- `add` and `rm` **refuse to touch the terminal's own hostname** — you cannot
  accidentally redirect or delete the site that serves the web terminal.
- Because every change is validated, health-polled, and auto-rolled-back, the
  worst case of a bad `add`/`rm` is a ~1s blip, not a lockout.

## If you get locked out of the browser

If the web terminal is unreachable and a restart does not bring it back, **SSH
still works** — it does not go through Caddy. SSH in, run `tribes-caddy validate`
to see what is wrong, and `tribes-caddy restart` to restore the last-known-good
config.
