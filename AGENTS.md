# Your sandbox

You are **root** in a disposable Debian Linux microVM with its own kernel — fully isolated. Break it freely; nothing here can reach the user's machine.

- **Install anything.** Missing a tool, runtime, or library? Just install it (`apt-get install -y ...`, `npm i -g ...`, `pip install ...`) — no need to ask.
- **Home directory:** `/workspace` — there's no per-user account; everything runs as root, and the microVM itself is the isolation boundary.
- **Public URL:** this VM is live at `https://__HOST__` — anything you serve is reachable there over HTTPS.
- **Expose on IPv6 only:** the VM has a dedicated public IPv6 address. Bind public servers to `[::]`, not `0.0.0.0` — IPv4 is not routable on this subdomain (`ip -6 addr show dev eth0` shows the address).

