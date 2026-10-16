# University Mail Bridge

A small, self-hosted bridge that adds OAuth 2.0 to plain **IMAP/SMTP** for
**Microsoft 365** mailboxes — so a mail client whose own app your university's
tenant won't approve (e.g. Spark) can still reach your inbox.

It wraps [email-oauth2-proxy](https://github.com/simonrob/email-oauth2-proxy)
in a container. Your client speaks ordinary IMAP/SMTP with a password; the
bridge holds the OAuth token and signs in to Microsoft for you.

Most universities run on Microsoft 365, so one bridge can serve **several
university accounts at once** — just add a section per address.

```
 mail client  ──IMAP/SMTP+password──▶  bridge (this repo)  ──OAuth2──▶  Microsoft 365
 (e.g. Spark)        over TLS            on your VPS                     outlook.office365.com
```

---

## Why this exists

Some tenants require admin approval for third-party mail apps. The bridge signs
in with the public **Thunderbird** client ID and asks only for IMAP + SMTP
scopes, which a tenant may allow where it blocked a broader app. Your own
password, MFA and sign-in rules still apply exactly as normal.

> **Read before you deploy.** Sign-ins will appear in your tenant as
> *Thunderbird*. The officially supported route is asking your university's IT
> to approve your mail app. Whether running this is acceptable under your
> institution's IT policy is your decision — check that policy first. Use it
> only for mailboxes you own.

---

## Requirements

- A VPS with a public IP and Docker + the Compose plugin.
- A domain name (e.g. `mail.example.com`) with an **A/AAAA record** pointing at
  the VPS.
- A TLS certificate for that name (a cloud client will reject a self-signed
  one). Let's Encrypt is free — see below.
- Open inbound ports **993** and **465** on the VPS firewall/security group.

---

## Setup

### 1. Get the code onto the VPS

```bash
git clone https://github.com/Kevin-66/university-mail-bridge.git
cd university-mail-bridge
```

### 2. TLS certificate

Obtain a certificate for your domain and copy the two files into `data/certs/`:

```bash
# Example with certbot in standalone mode (stop anything on :80 first):
sudo certbot certonly --standalone -d mail.example.com

sudo cp /etc/letsencrypt/live/mail.example.com/fullchain.pem data/certs/fullchain.pem
sudo cp /etc/letsencrypt/live/mail.example.com/privkey.pem   data/certs/privkey.pem
sudo chown "$USER" data/certs/*.pem
```

The proxy reads the certificate on every new connection, so when you renew it,
just copy the new files over `data/certs/` — no restart needed. (`data/certs/`
is git-ignored; your key never leaves the VPS.)

### 3. Configure your accounts

Edit `data/emailproxy.config`:

- Replace the example `[account-one@example.com]` / `[account-two@example.com]`
  headers with your real addresses.
- Add or remove account sections to taste — one per mailbox. Keep them all on
  the same ports; the proxy routes by the login username.

Nothing else needs changing for a standard Microsoft 365 account.

### 4. Start it

```bash
docker compose up -d --build
docker compose logs -f bridge      # watch it come up
```

### 5. Authorize each account (one-time)

Because the VPS is headless, the browser redirect comes back through an SSH
tunnel. In one terminal:

```bash
ssh -L 8080:localhost:8080 you@your-vps
```

In another terminal **on the VPS**, run the helper once per address:

```bash
./authorize.sh
```

It asks for the address and a **bridge password** (make one up — not your
university password). It then prints a Microsoft sign-in URL; open it in your
browser (while the tunnel is up), sign in, and the helper confirms your inbox is
reachable. The token is saved, encrypted with that password, in
`data/tokens.cache`, and refreshes itself from then on.

### 6. Point your mail client at the bridge

Add each account as a **manual IMAP** account:

| Setting            | Value                              |
| ------------------ | ---------------------------------- |
| Email / username   | your full address                  |
| Password           | the **bridge password** from step 5 |
| IMAP server        | `mail.example.com`, port **993**, SSL/TLS |
| SMTP server        | `mail.example.com`, port **465**, SSL/TLS |

---

## Security notes

- This endpoint, given a valid **address + bridge password**, grants access to
  that mailbox. Use a long, random bridge password per account.
- The saved token is **encrypted at rest** with that password, which is never
  stored. A leak of `data/tokens.cache` alone does not expose a mailbox without
  the password.
- Always serve over real TLS (done via `data/certs/`). Never expose the ports
  without it.
- Consider `fail2ban` and firewalling on the VPS. Port `8080` is bound to the
  VPS loopback only (reachable via the SSH tunnel), never published publicly.
- The `9e5f94bc-…` client ID is Thunderbird's public ID — see "Why this exists".

### Encrypting data at rest (optional)

What is already encrypted on disk, and what is not:

| On disk in `data/`     | At rest                                              |
| ---------------------- | --------------------------------------------------- |
| `tokens.cache`         | **Encrypted** — per-account bridge password (PBKDF2 → Fernet) |
| `certs/privkey.pem`    | Plaintext — the service must read it to start       |
| `emailproxy.config`    | Plaintext — holds no secrets (public client ID only) |

To encrypt **everything** in `data/` (including the TLS key) against disk or
snapshot theft, use the bundled `secure-data.sh`, which wraps the directory in
[gocryptfs](https://github.com/rfjakob/gocryptfs). While locked, only ciphertext
(`data.enc/`) exists on disk; `data/` is an empty mountpoint.

```bash
sudo apt install gocryptfs
echo user_allow_other | sudo tee -a /etc/fuse.conf   # needed for the container bind-mount

./secure-data.sh init          # one-time: set a passphrase, import your config/certs
docker compose up -d
```

After a VPS reboot the bridge stays **down until you unlock it** — that is the
price of real at-rest encryption, since the key cannot also live on the same
disk:

```bash
./secure-data.sh unlock && docker compose up -d
```

If you would rather the bridge always come back on its own, skip this and rely
on the token encryption above plus `chmod 600 data/certs/privkey.pem`.

---

## Updating

Images install the latest `emailproxy` at build time, so updating is a rebuild:

```bash
docker compose build --pull --no-cache
docker compose up -d
```

---

## Files

| Path                     | Purpose                                             |
| ------------------------ | --------------------------------------------------- |
| `docker-compose.yml`     | Service, ports, the single `./data` volume          |
| `Dockerfile`             | Python + `emailproxy` (+ `prompt_toolkit`)          |
| `data/emailproxy.config` | Servers, accounts, cert paths — **edit this**       |
| `data/certs/`            | Your `fullchain.pem` + `privkey.pem` (git-ignored)  |
| `authorize.sh`           | One-time per-account sign-in helper                 |
| `data/authorize.py`      | Trigger used by `authorize.sh`                      |
| `secure-data.sh`         | Optional gocryptfs at-rest encryption for `data/`   |

Built on [email-oauth2-proxy](https://github.com/simonrob/email-oauth2-proxy)
by Simon Robinson (Apache-2.0).
