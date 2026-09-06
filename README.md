# OCWA-Script: OVERCLOCK Lab (Debian web server)

Automated setup for the **OCWA** web-application box, one target in the **OVERCLOCK**
offensive-security lab (the NGS x GCU Hacknet project). These scripts stand up a
vulnerable Debian web server (OCWA, a custom flavor of DVWA) plus a layered
host-compromise chain with **25 capture-the-flag objectives**.

> **This box is intentionally insecure.** Build it only on an isolated VM with no
> route to a production network or the public internet. You are responsible for how
> and where you run it.

---

## What you will practice

A full web-to-root chain, from the application down to the host:

- **Web application:** OCWA (DVWA-style) vulnerabilities; source-comment leaks,
  weak login, embedded and encoded secrets.
- **Credential recovery on-host:** `~/.netrc`, `~/.git-credentials`, `~/.ssh`
  key looting, world-readable cron scripts, log-file tokens, service `.env` files,
  legacy password backups, base64-in-binary (`strings`), AES-128-CBC weak passphrase.
- **Database access:** PostgreSQL customer data, MySQL `internal.secrets`
  (monitoring key, Rails `secret_key_base`).
- **Privilege escalation to root:** looted SSH key → `svc_backup`, `docker` group
  → host root, root-only sudoers drop-in, localhost API keys, `/root/root.txt`.

**Flags:** 25 total: 8 Easy, 11 Medium, 6 Hard.

---

## Requirements

| | |
|---|---|
| **Target VM** | Debian 13 (server), fresh install, **snapshot it first** |
| **Resources** | 2+ vCPU, 2 GB+ RAM, 20 GB disk |
| **Privilege** | Run the installer as **root** |
| **Attacker box** | Kali Linux (or any pentest distro) on the same isolated host-only network |
| **Networking** | Host-only / internal network. **No internet, no production LAN.** |

---

## Build it

The web app itself lives in the companion repo **OCWA**; these scripts install it
and layer the host-compromise chain on top.

```bash
# as root on the fresh Debian VM
chmod +x Debian-Setup.sh Install-OCWA.sh
./Debian-Setup.sh          # provisions the box, seeds the flags, installs OCWA
```

`Install-OCWA.sh` is the app-only installer (clone + database + Apache/PHP config)
if you want just the web application; `Debian-Setup.sh` is the full lab build.

### Flags and the build seed (important)

Flags look like `FLAG{CODENAME12345678}` and are **derived, never written to the
box**; the installer emits no plaintext answer key:

```
flag   = FLAG{ codename + 8 digits }
digits = HMAC_SHA256( seed , "ocwa::<key>" )   (folded to 8 digits)
```

The installer reads the seed from **`OC_FLAG_SEED`**:

- **Home / practice (recommended): do nothing.** With no seed set, the installer
  generates a random one and prints it. Save it if you want to verify your answers.
- **Reproducible personal build:** `export OC_FLAG_SEED="my-personal-seed"` before
  running.

Your home-built flags **will not match the official graded lab**, which uses a
private course seed. The box is fully playable; the official answers are not
computable from this public installer.

---

## How to play

| File | Use it when |
|---|---|
| `webserver-student-lite.md` | **Hints only**, no answers. |
| `ocwa-hybrid.md` | Hint **plus** a per-flag collapsible reveal. |
| `webserver-student-walkthrough.md` | Full step-by-step walkthrough. |
| `webserver-student-walkthrough-wiki.md` | Same content, wiki/portal formatting. |

Flag values in the student writeups are **masked** (`FLAG{S******8}`); submit the
real ones recovered from your own box.

---

## Troubleshooting

- **Provision looks incomplete:** the installer is best-effort (`set -e` is
  intentionally off); rebuild from the clean snapshot if the flag env
  (`/root/.oc_flags.env`) or database seeding did not complete.
- **Reset the flags:** roll back to the snapshot and rebuild with a different
  `OC_FLAG_SEED`.

---

## License / use

For authorized training and education only. Do not deploy on any system or network
you do not own or have explicit permission to test.
