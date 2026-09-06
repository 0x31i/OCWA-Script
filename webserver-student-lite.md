# overclock Web Server (OCWA): Student Lite Guide
### overclock Security | Offensive Track | The map, not the turn-by-turn

> **What this is.** The high-level narrative of the engagement: phase by phase, what to accomplish
> and which tools to reach for, with just enough to point you at the water so you work out the how
> yourself. For the exact commands, real output, and the full reasoning behind every move, use the
> **Student Walkthrough**, or the **Hybrid** page, which folds both together and hides the detail
> until you are stuck.

**Target:** `192.168.148.100` (Debian web server) | **Attacker:** Kali Linux | **Related host:** the Server 2019 box (`192.168.148.101`) | **25 flags**

> **The golden rule.** This is the internet-facing entry point, and nothing is a free `grep`. The chain is
> **web -> web shell (www-data) -> ssh user (user1) -> root**, and each rung reuses what the last leaked.
> A plain `grep -r FLAG{` finds only **decoys**. Real flags are **JWTs** you decode (`eyJ…`), **base64**
> blobs (`RkxBR3t…`), rows in a **database** you query, an **API** you call, or **crypto** you crack.
> The creds you loot here **open the Windows server too.**

---

## Setup & mindset
- Attack from **Kali**: `nmap`, `nxc`, `hydra`, `gobuster`, `sqlmap`, `curl`, `jq`, `openssl`, `burpsuite`.
  Plus **`d3coder`** — a one-file JWT/base64 decoder that ships with the lab:
  `curl -sL https://raw.githubusercontent.com/0x31i/d3coder/main/d3coder -o /tmp/d3coder && sudo install -m 755 /tmp/d3coder /usr/local/bin/d3coder`
- **The rule: nothing is a free grep.** Learn to recognise and decode:
  - **`eyJ...`** = a **JWT**: copy the token and decode it — `d3coder '<tok>'` (or by hand
    `echo '<tok>' | cut -d. -f2 | basenc --base64url -d`, or `jwt_tool`, or **jwt.io** — but never paste real client tokens online). Read the `flag` claim.
  - base64 blobs (`d3coder`); an `.enc` file (`openssl`); a `.cnf`/`.pgpass` (a **database** cred); a leaked
    key (an **API** or another **user**).
  - A plain `grep FLAG{` finds only **decoys**. The real flag is always one hop away.
- This box is the **entry point**. A credential here logs into the Windows server.

## Switches to try (your enumeration toolbox)
Learn what each *switch* gathers, then aim it at the right target. This is the heart of the lite guide.

**`curl` (your main web tool):**
| Switch | What it does |
|--------|--------------|
| `-s` | quiet (no progress bar) |
| `-d "a=b&c=d"` | POST form data (login attempts) |
| `-c cookies` / `-b cookies` | save / send cookies (keep a logged-in session) |
| `-o /dev/null -w "%{http_code}"` | show just the HTTP status (spot redirects) |
| `-i` / `-I` | include / only headers |
| `\| grep '<!--'` | filter to HTML comments (where secrets hide) |

**Post-foothold Linux enumeration (as `user1`):**
| Tool / switch | What it gathers |
|---------------|-----------------|
| `grep -roE 'eyJ[A-Za-z0-9._-]+' <path>` | find JWTs anywhere (home, logs, backups, configs) |
| `d3coder '<token>'` | decode a found JWT/base64/cookie — read the payload's `flag` claim |
| `sudo -l` | what you may run as root (look for a GTFOBins entry) |
| `id` | your groups (is `docker` there? that is root) |
| `find / -perm -4000 2>/dev/null` | SUID binaries |
| `ss -ltnp` | localhost-bound services (the internal API) |
| `cat /etc/*-release`, `uname -a` | OS/kernel (privesc research) |
| `mysql -e "..."` / `psql -c "..."` | query databases where flags live |

**Other tools:** `nmap -sV` (services), `printf 'user1\nadmin\ndeveloper\nbackup\n' > users.txt` +
`printf 'password123\nPassword1\nadmin\nletmein\nwelcome\n' > passwords.txt` then
`hydra -L users.txt -P passwords.txt ssh://ip -t 4 -V` (ssh brute),
`openssl enc -aes-128-cbc -d -pass pass:<guess>` (crack the encrypted flag), `d3coder '<token>'`
(decode a JWT and read the `flag` claim — plain `base64 -d` fails on base64url, so use d3coder or `basenc --base64url -d`), `strings <binary>` (readable text in a binary).

---

## Phase 1: Reconnaissance

> **The thinking.** We are at the very front of the chain with no foothold, so this phase answers one
> question: what is actually exposed and how do we talk to it. A port scan is reconnaissance, not attack:
> each open port is a capability the box advertises, and naming the service behind it tells us how we will
> eventually turn access into a foothold. We fingerprint ports and versions first because everything
> downstream (which port to attack, what the banner leaks, whether the databases are even reachable)
> depends on knowing the surface before we touch it. The tradeoff is speed versus stealth, and in a lab we
> favor a fast, full read of the two open ports rather than a quiet one. This is the map that makes every
> later move deliberate instead of a guess.

**Goal.** Map the surface (a web app + ssh) and grab free intel.
**Try.** A service scan (`nmap -sV <target>`), and just *connect* to ssh without logging in. Only 22 and 80
are exposed; the databases and the internal API are localhost-bound (an internal-recon lesson for later).

### FLAG 1: SSH banner (Easy)

**Goal.** The ssh service is chatty before you authenticate. Read what it overshares.
**Try.** Connect to ssh without offering an auth method (`ssh -o PreferredAuthentications=none nobody@<target>`).
The **banner** prints a flag before it rejects you.

---

## Phase 2: Web application attack

> **The thinking.** Port 80 is our only real way in since ssh wants a key or password we do not have yet,
> so the whole chain now hinges on defeating the web app. This phase answers whether the login portal can
> be turned into authenticated access, first by reading what the developers leaked, then by turning
> username enumeration and a discoverable password into a real session. We do the cheap, low-noise reads
> (source comments, differential errors) before anything heavier because they routinely hand you the
> credential for free. The discipline here is escalation of effort: read what the app volunteers before you
> reach for sqlmap or a brute-force, because a leaked comment or a chatty error message is faster, quieter,
> and often all you need.

**Goal.** Break the front door with source review + OSINT.
**Try.** Browse to `http://192.168.148.100/`; it redirects to `login.php` (the overclock portal). Read the
page source, use the leaked email/domain as an OSINT lead, and use the login form's differential errors to
enumerate a valid user, then log in.

### FLAG 2: Login page source (Easy)

**Goal.** Developers leave comments in the HTML. Read them.
**Try.** `curl -s .../login.php | grep -i "<!--"`. There is a flag in a comment, and an **email/domain**
(that is your OSINT lead for the next flag).

### FLAG 3: OSINT to authenticated homepage (Medium)

**Goal.** Turn the leaked domain into a live session, then read the homepage.
**Try.** The comment leaked a company domain; pivot it into breach data to find a password. Install and run
`breach-parse` (`git clone https://github.com/hmaverickadams/breach-parse.git /opt/breach-parse`, then
`./breach-parse.sh @chchcheckit.com results`) against the leaked domain to recover `brandon:sipsip1` (a local
`grep` of a leaked-DB corpus, or HaveIBeenPwned/DeHashed, work too). The login form also leaks valid usernames via
**differential errors** ("password incorrect for user X" vs "user does not exist"). You have the cred, so it's a
*login, not a brute-force*: easiest is the **browser login form** as `brandon:sipsip1` (it carries the anti-CSRF
`user_token` for you) — the homepage then shows the flag. Scripting it means scraping `user_token` first; actually
brute-forcing a CSRF form is a **Burp Intruder** job (session macro), not curl.

---

## Phase 3: Web shell foothold

> **The thinking.** An authenticated session lets us browse the app but not run commands, so the next rung
> is trading web access for code execution on the server. This phase answers whether the upload feature can
> be abused to plant a PHP shell, which is the difference between poking at pages and owning a process on
> the box. We accept that the shell only gets us www-data, a deliberately weak account, because code
> execution as anyone is the beachhead everything else is built on. Everything from here (looting secrets,
> brute-forcing to a real user, escalating to root) requires this single toehold, so getting *any* command
> to run on the server is the pivot that changes the entire character of the engagement.

**Goal.** Turn the web app into code execution.
**Try.** The **file-upload** feature is not picky. Upload a small PHP web shell (bypass the image filter with
a Content-Type trick in Burp, a double extension, or a magic-byte polyglot). Trigger it with
`curl ".../shell.php?cmd=id"`. Expect `uid=33(www-data)`, then upgrade to a reverse shell.

---

## Phase 4: Lateral movement to ssh

> **The thinking.** www-data is a shared, low-privilege account that cannot read most secrets and gets you
> noticed, so the question now is how to become a real interactive user. The web app already handed us
> valid usernames and the box advertises weak passwords, so a small, throttled ssh brute is the cheapest
> way to trade code execution for a proper login. We keep the thread count low on purpose because the lab
> locks you out if you hammer it, and a clean shell as a real user is worth the extra patience.

**Goal.** Upgrade `www-data` to a real user.
**Try.** **Brute-force ssh** with a small wordlist (`-t 4` / low speed so the lab does not drop you): `hydra`
(`hydra -L users.txt -P passwords.txt ssh://ip -t 4 -V`) or **Metasploit** (`auxiliary/scanner/ssh/ssh_login`,
which even opens a session on a hit). You will land a real user (`user1`), your foothold. `ssh` in.

---

## Phase 5: Looting the box (functional secrets)

> **The thinking.** Now that we have a real user shell we systematically sweep the box, because the middle
> of the chain is where reused creds, tokens, and keys accumulate. This phase answers where the functional
> loot lives and, just as important, teaches the reflex that a plain grep only finds decoys: the real flags
> sit inside JWTs, databases, an internal API, encrypted blobs, and archives. We do this before escalating
> because much of what we harvest here (the cross-host Windows creds, an ssh key to another account, service
> keys) is what makes the later steps and the pivot possible.

The flags are **functional loot**, not plaintext tokens. As `user1`, sweep the box.

**JWT flags.** These are bearer tokens (`eyJ…`), and each hides in a *different* realistic leak site, so read
each on its own terms instead of one blind grep: `~/.bash_history` (a pasted `curl` token), `~/.git-credentials`
(git helper cache) and `~/.netrc` (an API "password" that's really a JWT), `/var/log/oc.log` (an issued service
token) and `/var/log/webapp/app.log` (a DEBUG session token), a "legacy passwords" backup (a "rotate after
migration" token), `/tmp/.hidden/` (re-dropped by a systemd unit), and a service `.env`. Find them with
`grep -rIlE 'eyJ...'`, then copy each token and decode it with `d3coder '<token>'` (or `jwt_tool`, or by hand
`… | cut -d. -f2 | basenc --base64url -d`) and read the `flag` claim. Ignore the obvious `FLAG{DECOY}` strings.

**Flag 12: network credentials (the cross-host key).** Read the secrets directory. A file literally named
`network_credentials.txt` holds a base64 flag **and Windows creds** (save those; they drive the pivot).

**Database flags.** The creds leak, the flags live in the DB. A Postgres flag lives in a *customer record*
(find the leaked pg cred in a backup script and `psql`). Two MySQL flags live in `internal.secrets`, reached
via a world-readable `.cnf` that auto-loads a cred (so `mysql -e "SELECT ..."` just works, no password
prompt: that is the vuln).

**Internal API flags.** Something listens on `127.0.0.1:8899` (find it with `ss -ltn`). It answers only with
a valid `?key=`. Two keys leak in the environment (a `/etc/profile.d/` script, a systemd service). `curl` it.

**SUID / config / archive / crypto flags.** A **SUID** binary (`find / -perm -4000`) that prints its own flag
(runs as root, so it reads as `user1`); a base64 line in a world-readable cron script; a base64 blob in the
"vulnerable binary" (`strings`); and an `openssl`-encrypted file whose passphrase is a *very common* one.
**Note:** the flag in `/etc/sudoers.d/oc_flag` is `440 root:root`, so a plain `cat` as `user1` returns
`Permission denied`, and **Flag 19 is deferred to Phase 6** (collect it after you escalate).

**Flag 23: an ssh key inside an archive lets you become another user.** A backup archive hides an ssh key. Use
it to become another user and read their flag.

---

## Phase 6: Privilege escalation to root

> **The thinking.** We hold a real user but the last flags and full control of the box live behind root, so
> this final rung answers how our unprivileged account crosses that line. You **enumerate every vector and let
> the box tell you** (`id`, `sudo -l`, SUID sweep, cron) rather than fixating on one, the lab ships **five**
> independent paths, so a student learns there is rarely a single way up.

**Goal.** Escalate to root, where the last flags live. Five independent paths ship on purpose; pick the cleanest.
**Try.** Enumerate: `id` (docker group?), `sudo -l` (GTFOBins entry?), `find / -perm -4000 -type f 2>/dev/null`
(SUID `find`, `backup_tool`, `/opt/oc/vulnerable_binary`?), `ls -la /etc/crontab /opt/scripts/` (writable root
cron?). Then exploit one:
> - **sudo GTFOBins:** `sudo vim -c ':!/bin/bash'`
> - **SUID find:** `find . -exec /bin/sh -p \; -quit`
> - **docker group:** `docker run -v /:/mnt --rm alpine cat /mnt/root/.docker_flag` (Flag 24), mounting `/` = root
> - **world-writable root cron** `/opt/scripts/cleanup.sh`: append a reverse shell, wait one tick
>
> Once root, collect the root-only flags (unreadable until now): `/etc/sudoers.d/oc_flag` (**Flag 19**),
> `/root/.docker_flag` (Flag 24), `/root/root.txt` (Flag 25, the final flag).

---

## Cross-host pivot

> **The thinking.** The crown jewel is not a file on this box, it is what these credentials unlock. Remember
> Flag 12's `network_credentials.txt`? Those Windows creds (`user1 / Password123!`) work on the Server 2019
> box. OCWA is the entry point into the wider network, and this chain, one host handing you the next, is the
> real objective.

**Goal.** Test what these creds unlock elsewhere.
**Try.** The Windows creds from `network_credentials.txt` authenticate on the **Server 2019 box**
(`nxc smb 192.168.148.101 -u user1 -p 'Password123!' --local-auth`). This web server was the way in; the pivot
is the objective.

---

## Flag checklist

*(Censored. Confirm each with your own decode.)*

| Flag | | Flag | | Flag |
|------|---|------|---|------|
| Flag 2 `FLAG{A******2}` | | Flag 18 `FLAG{S******4}` | | Flag 16 `FLAG{D******3}` |
| Flag 3 `FLAG{D******5}` | | Flag 19 `FLAG{S******6}` | | Flag 17 `FLAG{V******8}` |
| Flag 1 `FLAG{D******7}` | | Flag 20 `FLAG{L******9}` | | Flag 10 `FLAG{B******2}` |
| Flag 11 `FLAG{H******3}` | | Flag 23 `FLAG{T******2}` | | Flag 24 `FLAG{G******0}` |
| Flag 12 `FLAG{H******1}` | | Flag 5 `FLAG{M******1}` | | Flag 21 `FLAG{N******6}` |
| Flag 8 `FLAG{R******2}` | | Flag 14 `FLAG{M******0}` | | Flag 22 `FLAG{H******8}` |
| Flag 4 `FLAG{H******5}` | | Flag 15 `FLAG{G******8}` | | Flag 25 `FLAG{R******3}` |
| Flag 9 `FLAG{N******0}` | | Flag 13 `FLAG{L******6}` | | Flag 6 `FLAG{F******6}` |
| Flag 7 `FLAG{G******9}` | | | | |

> **Decoys.** `FLAG{DECOY_*}` are planted in obvious spots (`/etc/environment`, `database.yml`,
> `oc.log`, `old_passwords.txt`). The answer key rejects them. If you got it without decoding/querying,
> it is fake.
