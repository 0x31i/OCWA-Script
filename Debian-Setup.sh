#!/bin/bash

# ===============================================
# Vulnerable Debian v13.1 OC Setup Script
# Purpose: Educational Penetration Testing Lab
# Author: 0x31i
# Version: 2.0 - Modified
# ===============================================

# NOTE: `set -e` intentionally NOT enabled. This installer is best-effort: each
# package/flag step guards its own failures, and one non-critical non-zero must
# never abort the provision before the flags env (/root/.oc_flags.env) and the
# database seeding run near the end of the script.

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Please run as root${NC}"
    exit 1
fi

echo -e "${BLUE}===============================================${NC}"
echo -e "${BLUE}    Vulnerable Debian OC Setup Script${NC}"
echo -e "${BLUE}    Educational Purpose Only - v2.0${NC}"
echo -e "${BLUE}===============================================${NC}"

# ===============================================
# Build dependencies (required for several flags)
#   - gcc/build-essential : compile Flag 'N2' vulnerable_binary
#   - binutils            : provides `strings` used to solve it
#   - docker.io           : Flag 'G3' docker daemon.json + docker-group privesc
# These are best-effort: on an air-gapped build host apt will fail; we warn
# loudly rather than abort so the rest of the lab still builds.
# ===============================================
echo -e "${GREEN}[+] Installing build dependencies (gcc / binutils / docker)...${NC}"
export DEBIAN_FRONTEND=noninteractive

# On a freshly-booted cloud image, cloud-init / unattended-upgrades hold the
# dpkg lock for the first minute or two. Wait for it to clear so these installs
# do not fail and get mis-reported as "offline" (which then silently skips the
# postgresql/docker/gcc flag packages).
echo -e "${GREEN}[+] Waiting for boot-time apt/dpkg activity to finish...${NC}"
_aptwait=0
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    [ "$_aptwait" -ge 300 ] && { echo -e "${YELLOW}[!] apt still locked after 300s - continuing anyway${NC}"; break; }
    sleep 3; _aptwait=$((_aptwait + 3))
done

# DPkg::Lock::Timeout makes apt itself wait for the lock instead of failing.
APT_OPTS="-o DPkg::Lock::Timeout=300"
apt-get $APT_OPTS update -y 2>/dev/null || echo -e "${YELLOW}[!] apt-get update failed (offline?) - continuing${NC}"
for pkg in build-essential binutils docker.io postgresql; do
    if apt-get $APT_OPTS install -y "$pkg" 2>/dev/null; then
        echo -e "${GREEN}  [+] $pkg installed${NC}"
    else
        echo -e "${RED}  [!] Could not install $pkg (offline?) - dependent flag may be skipped${NC}"
    fi
done

# Create directory structure
echo -e "${GREEN}[+] Creating OC directory structure...${NC}"
mkdir -p /opt/oc/{flags,scripts,exploits,configs}
mkdir -p /var/oc/{backup,logs,data}
mkdir -p /home/user1/{documents,downloads,scripts}
mkdir -p /opt/secrets
mkdir -p /opt/scripts
mkdir -p /opt/webapp/config
mkdir -p /opt/development/project
mkdir -p /var/backups/system
mkdir -p /var/log/webapp
mkdir -p /var/spool/cron/atjobs
mkdir -p /tmp/.hidden

# ---------------------------------------------------------------------------
# FLAG SEED — the single source of truth for every flag on this box.
#   * Change this ONE value to ROTATE all flags (they regenerate deterministically).
#   * Keep it IDENTICAL across the three lab build scripts (win10 / server / OCWA).
#   * This build script NEVER emits the plaintext answers. Generate the instructor
#     answer key OFF-box with Generate-AnswerKey.py (admin-only, NOT distributed).
# ---------------------------------------------------------------------------
OC_FLAG_SEED="${OC_FLAG_SEED:-}"
if [ -z "$OC_FLAG_SEED" ]; then
    # No seed supplied: generate a random one so a home lab "just works".
    # The OFFICIAL graded box is built by exporting the secret course seed first.
    OC_FLAG_SEED="$(openssl rand -hex 16)"
    echo "[i] No OC_FLAG_SEED set -- generated a random lab seed: $OC_FLAG_SEED"
    echo "    Save it if you want to regenerate your own answer key later."
fi

echo -e "${GREEN}[+] Generating OC flags...${NC}"

# Consistent 8-digit id, KEYED and SEED-derived: HMAC-SHA256(OC_FLAG_SEED, key) ->
# 8 digits. Same math as the Windows scripts + Generate-AnswerKey.py, so one seed
# governs all boxes and one off-box generator reproduces every value.
gen_flag_id() {
    local key="$1"
    local h
    h=$(printf '%s' "$key" | openssl dgst -sha256 -hmac "$OC_FLAG_SEED" -r | cut -d' ' -f1)
    printf '%08d' "$(( 16#${h:8:8} % 100000000 ))"
}

# Generate flag IDs (obfuscated)
declare -A FLAG_IDS
FLAG_IDS["H1"]=$(gen_flag_id "wizard1")
FLAG_IDS["H2"]=$(gen_flag_id "genius2")
FLAG_IDS["R1"]=$(gen_flag_id "keeper3")
FLAG_IDS["D1"]=$(gen_flag_id "phoenix4")
FLAG_IDS["H3"]=$(gen_flag_id "giant5")
FLAG_IDS["N1"]=$(gen_flag_id "brave6")
FLAG_IDS["L1"]=$(gen_flag_id "moon7")
FLAG_IDS["G1"]=$(gen_flag_id "seeker8")
FLAG_IDS["F1"]=$(gen_flag_id "twin9")
FLAG_IDS["G2"]=$(gen_flag_id "joker10")
FLAG_IDS["S1"]=$(gen_flag_id "prince11")
FLAG_IDS["S2"]=$(gen_flag_id "dog12")
FLAG_IDS["L2"]=$(gen_flag_id "wolf13")
FLAG_IDS["T1"]=$(gen_flag_id "morph14")
FLAG_IDS["M1"]=$(gen_flag_id "eye15")
FLAG_IDS["M2"]=$(gen_flag_id "cat16")
FLAG_IDS["D2"]=$(gen_flag_id "dragon17")
FLAG_IDS["V1"]=$(gen_flag_id "dark18")
FLAG_IDS["B1"]=$(gen_flag_id "curse19")
FLAG_IDS["G3"]=$(gen_flag_id "elder20")
FLAG_IDS["N2"]=$(gen_flag_id "snake21")
FLAG_IDS["H4"]=$(gen_flag_id "soul22")
FLAG_IDS["R2"]=$(gen_flag_id "riddle23")

# Map to actual names (obfuscated storage)
declare -A FLAG_NAMES
FLAG_NAMES["H1"]="HARRY"
FLAG_NAMES["H2"]="HERMIONE"
FLAG_NAMES["R1"]="RON"
FLAG_NAMES["D1"]="DUMBLEDORE"
FLAG_NAMES["H3"]="HAGRID"
FLAG_NAMES["N1"]="NEVILLE"
FLAG_NAMES["L1"]="LUNA"
FLAG_NAMES["G1"]="GINNY"
FLAG_NAMES["F1"]="FRED"
FLAG_NAMES["G2"]="GEORGE"
FLAG_NAMES["S1"]="SNAPE"
FLAG_NAMES["S2"]="SIRIUS"
FLAG_NAMES["L2"]="LUPIN"
FLAG_NAMES["T1"]="TONKS"
FLAG_NAMES["M1"]="MOODY"
FLAG_NAMES["M2"]="MCGONAGALL"
FLAG_NAMES["D2"]="DRACO"
FLAG_NAMES["V1"]="VOLDEMORT"
FLAG_NAMES["B1"]="BELLATRIX"
FLAG_NAMES["G3"]="GRINDELWALD"
FLAG_NAMES["N2"]="NAGINI"
FLAG_NAMES["H4"]="HORCRUX"
FLAG_NAMES["R2"]="RIDDLE"

# Build flags dynamically
build_flag() {
    local key="$1"
    echo "FLAG{${FLAG_NAMES[$key]}${FLAG_IDS[$key]}}"
}

# --- flag-hardening helpers (grep-proofing) ----------------------------------
# GOAL: a naive `grep -rIa 'FLAG{' /` must find NOTHING at a student's current
# privilege level. build_flag still returns the PLAINTEXT value (used only by
# the root-only answer-key report). At rest, encode/gate every flag except the
# warm-up. base64 = easy tier (recognize + decode); hex = one step up. GATE and
# DERIVE flags change perms/logic at their own site, not here.
enc_b64() { printf '%s' "$(build_flag "$1")" | base64; }
enc_hex() { printf '%s' "$(build_flag "$1")" | od -An -v -tx1 | tr -d ' \n'; }
# base64url (JWT-style: +/ -> -_ , strip padding)
b64url() { base64 -w0 2>/dev/null | tr '+/' '-_' | tr -d '='; }
# jwt_flag KEY [sub]: emit a realistic HS256 JWT whose payload carries the flag.
# A grep for FLAG{ misses it (base64url); the student decodes the middle segment
# (real skill). Tokens leaking in logs/history/git is a top real-world finding.
jwt_flag() {
    local key="$1" sub="${2:-oc-service}" flag h p hb pb sig
    flag="$(build_flag "$key")"
    h='{"alg":"HS256","typ":"JWT"}'
    p="{\"sub\":\"${sub}\",\"iat\":1710000000,\"scope\":\"internal\",\"flag\":\"${flag}\"}"
    hb=$(printf '%s' "$h" | b64url); pb=$(printf '%s' "$p" | b64url)
    sig=$(printf '%s' "${hb}.${pb}" | openssl dgst -sha256 -hmac 'oc-signing-key' -binary | b64url)
    printf '%s.%s.%s' "$hb" "$pb" "$sig"
}

# ===============================================
# VULNERABILITY 1: Weak User Accounts
# ===============================================
echo -e "${YELLOW}[*] Setting up weak user accounts...${NC}"

# Create vulnerable users with weak passwords
useradd -m -s /bin/bash user1 2>/dev/null || true
echo "user1:password123" | chpasswd

useradd -m -s /bin/bash developer 2>/dev/null || true
echo "developer:dev123" | chpasswd

useradd -m -s /bin/bash admin_backup 2>/dev/null || true
echo "admin_backup:admin" | chpasswd

# Plant EASY flag in user description
usermod -c "John Reyes,IT Support" user1
# H1 (FUNCTIONAL): a JWT bearer token leaks in user1's shell history (a curl to
# the internal API). grep(FLAG) misses it; decode the JWT payload to recover it.
cat > /home/user1/.bash_history << HIST
ls -la
cat /etc/hostname
curl -s -H "Authorization: Bearer $(jwt_flag 'H1' 'user1')" http://127.0.0.1:8899/whoami
sudo -l
exit
HIST
chown user1:user1 /home/user1/.bash_history
chmod 600 /home/user1/.bash_history

# ===============================================
# VULNERABILITY 2: Credential Leakage (NEW)
# ===============================================
echo -e "${YELLOW}[*] Creating credential leakage files...${NC}"

# Create network credentials file with EASY flag
cat > /opt/secrets/network_credentials.txt << EOF
========================================
INTERNAL NETWORK CREDENTIALS
========================================
Generated: 2024-01-15
Last Updated: 2024-09-01

** Windows Server 2019 Server Credentials **
Host: 192.168.148.101
Domain: OVERCLOCK.LOCAL
Username: user1
Password: Password123!
Notes: Primary DC, handles authentication

** Windows 10 Workstation Credentials #1 **
Host: 192.168.148.102
Username: jsmith
Password: Welcome1
Notes: Finance department workstation

** Windows 10 Workstation Credentials #2 **
Host: 192.168.148.102
Username: mjones
Password: Password1
Notes: HR department workstation

$(enc_b64 'H2')

[WARNING: This file should be encrypted!]
========================================
EOF
chmod 644 /opt/secrets/network_credentials.txt

# Create another credentials file in backup location
cat > /var/backups/system/old_passwords.txt << EOF
Legacy System Passwords (Before Migration)
==========================================
MySQL root: admin123
PostgreSQL: postgres/postgres
Redis: nopassword
MongoDB: admin/admin
FTP: ftpuser/ftppass

# CI/CD API token (rotate after migration): $(jwt_flag 'R1' 'ci-legacy')
EOF
chmod 644 /var/backups/system/old_passwords.txt

# ===============================================
# VULNERABILITY 3: SUID Binaries
# ===============================================
echo -e "${YELLOW}[*] Setting up vulnerable SUID binaries...${NC}"

# Vulnerable SUID-root binary (MEDIUM flag). NOTE: a SUID *bash script* does NOT
# work -- the Linux kernel ignores the setuid bit on interpreted scripts -- so this
# must be a compiled binary. The SNAPE flag is stored in a root-only (0600) file;
# the SUID binary reads it as root, and also backs up any file the caller names
# (classic SUID arbitrary-read privesc). This makes the writeup's "SUID -> root" real.
mkdir -p /root/.oc_backup
build_flag 'S1' > /root/.oc_backup/system.flag
chown root:root /root/.oc_backup/system.flag
chmod 600 /root/.oc_backup/system.flag        # only root (or the SUID tool) can read it
command -v gcc >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 install -y gcc >/dev/null 2>&1
cat > /tmp/backup_tool.c << 'CEOF'
#include <stdio.h>
#include <unistd.h>
#include <string.h>
static void dump(const char *p){
    FILE *f = fopen(p, "r");
    if (!f) { puts("File not found"); return; }
    char b[4096]; size_t n;
    while ((n = fread(b, 1, sizeof b, f)) > 0) fwrite(b, 1, n, stdout);
    fclose(f);
}
int main(void){
    setgid(0); setuid(0);                 /* run as root (SUID) */
    puts("Backup Tool v1.0");
    dump("/root/.oc_backup/system.flag"); putchar('\n');   /* the protected flag */
    printf("Enter file to backup: "); fflush(stdout);
    char path[512];
    if (fgets(path, sizeof path, stdin)) {
        path[strcspn(path, "\n")] = 0;
        if (path[0]) dump(path);          /* back up any file, as root */
    }
    return 0;
}
CEOF
gcc -O2 -o /usr/local/bin/backup_tool /tmp/backup_tool.c 2>/dev/null && rm -f /tmp/backup_tool.c
chown root:root /usr/local/bin/backup_tool
chmod 4755 /usr/local/bin/backup_tool        # genuine SUID-root (rwsr-xr-x)

# Make find SUID (classic privesc)
chmod u+s /usr/bin/find 2>/dev/null || true

# ===============================================
# VULNERABILITY 4: Sudo Misconfigurations
# ===============================================
echo -e "${YELLOW}[*] Setting up sudo misconfigurations...${NC}"

# Add vulnerable sudoers entries
echo "user1 ALL=(ALL) NOPASSWD: /usr/bin/vim" >> /etc/sudoers
echo "developer ALL=(ALL) NOPASSWD: /usr/bin/python3" >> /etc/sudoers
echo "admin_backup ALL=(ALL) NOPASSWD: /bin/less" >> /etc/sudoers

# Create sudoers.d file with MEDIUM flag
echo "# $(enc_b64 'S2')" > /etc/sudoers.d/oc_flag
chmod 440 /etc/sudoers.d/oc_flag

# ===============================================
# VULNERABILITY 5: Cron Jobs
# ===============================================
echo -e "${YELLOW}[*] Setting up vulnerable cron jobs...${NC}"

# Create world-writable cron script
cat > /opt/scripts/cleanup.sh << EOF
#!/bin/bash
# System cleanup script
echo "Cleaning temporary files..."
rm -rf /tmp/*.tmp 2>/dev/null
echo "$(enc_b64 'L2')"
EOF
chmod 777 /opt/scripts/cleanup.sh

# Add cron job
echo "*/5 * * * * root /opt/scripts/cleanup.sh > /var/log/cleanup.log 2>&1" >> /etc/crontab

# The crontab entry above is INERT unless the cron daemon is installed AND running.
# Minimal Debian images ship without it, which silently kills the cleanup.sh -> root
# privesc. Install cron and enable it so the world-writable script actually fires as root.
command -v cron >/dev/null 2>&1 || DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 install -y cron >/dev/null 2>&1
systemctl enable --now cron >/dev/null 2>&1 || service cron start >/dev/null 2>&1

# ===============================================
# VULNERABILITY 6: SSH Misconfigurations
# ===============================================
echo -e "${YELLOW}[*] Configuring SSH vulnerabilities...${NC}"

# Enable password authentication
sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config

# Allow many concurrent pre-auth connections so the walkthrough's default
# `hydra ... ssh://` brute force (which opens ~16 parallel sessions) is not
# throttled/dropped by sshd. Without this, students must lower hydra to -t 2.
sed -i 's/^#\?MaxStartups.*/MaxStartups 100:30:200/' /etc/ssh/sshd_config
grep -q '^MaxStartups' /etc/ssh/sshd_config || echo 'MaxStartups 100:30:200' >> /etc/ssh/sshd_config
sed -i 's/^#\?MaxSessions.*/MaxSessions 50/' /etc/ssh/sshd_config
grep -q '^MaxSessions' /etc/ssh/sshd_config || echo 'MaxSessions 50' >> /etc/ssh/sshd_config

# Add SSH banner with EASY flag
echo "$(build_flag 'D1')" > /etc/ssh/banner
echo "Welcome to OC Server" >> /etc/ssh/banner
# root-only: the flag is delivered ONLY via the SSH pre-auth banner (ssh <host>),
# not by `cat` — a low-priv shell can't read the source file.
chmod 600 /etc/ssh/banner
sed -i 's/^#Banner.*/Banner \/etc\/ssh\/banner/' /etc/ssh/sshd_config

# Create SSH key with MEDIUM flag
mkdir -p /home/developer/.ssh
# (T1 is now a FUNCTIONAL leaked SSH key in the backup archive -- see below.)
echo "# authorized_keys backup (empty)" > /home/developer/.ssh/authorized_keys.backup
chmod 644 /home/developer/.ssh/authorized_keys.backup
chown -R developer:developer /home/developer/.ssh

# ===============================================
# VULNERABILITY 7: Hidden Files in System
# ===============================================
echo -e "${YELLOW}[*] Creating hidden files with flags...${NC}"

# Create hidden files in various system directories
# H3 (FUNCTIONAL): hardcoded git credentials in a dev's home -- the "password"
# is a JWT. Decode it to recover the flag. (Committed git creds = top finding.)
cat > /home/user1/.git-credentials << GITEOF
https://ci-bot:$(jwt_flag 'H3' 'ci-bot')@git.internal.oc
GITEOF
chown user1:user1 /home/user1/.git-credentials
chmod 600 /home/user1/.git-credentials

# Hidden file in home directory
# M1 (FUNCTIONAL): a .netrc whose API "password" is actually a JWT.
cat > /home/user1/.netrc << NETEOF
machine api.oc.internal
login user1
password $(jwt_flag 'M1' 'user1')
NETEOF
chown user1:user1 /home/user1/.netrc
chmod 600 /home/user1/.netrc

# Hidden directory with flag.
# NOTE: /tmp is tmpfs on the production host, so anything written here is wiped
# on reboot. Write it now (so the lab works immediately after setup) AND install
# a systemd oneshot that recreates it on every boot, keeping the student-facing
# path (/tmp/.hidden/secret.txt) identical while making the flag persistent.
FLAG_N1_VALUE="$(jwt_flag 'N1' 'web-session')"
mkdir -p /tmp/.hidden
echo "$FLAG_N1_VALUE" > /tmp/.hidden/secret.txt
chmod 755 /tmp/.hidden
chmod 644 /tmp/.hidden/secret.txt

cat > /etc/systemd/system/oc-hidden-flag.service << EOF
[Unit]
Description=Recreate OC hidden flag in tmpfs /tmp after reboot
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'mkdir -p /tmp/.hidden && echo "$FLAG_N1_VALUE" > /tmp/.hidden/secret.txt && chmod 755 /tmp/.hidden && chmod 644 /tmp/.hidden/secret.txt'

[Install]
WantedBy=multi-user.target
EOF
systemctl enable oc-hidden-flag.service 2>/dev/null || true

# ===============================================
# VULNERABILITY 8: Services and Processes
# ===============================================
echo -e "${YELLOW}[*] Setting up vulnerable services...${NC}"

# Create vulnerable service with HARD flag
cat > /etc/systemd/system/oc-monitor.service << EOF
[Unit]
Description=OC Monitoring Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/oc
ExecStart=/opt/oc/monitor.sh
Restart=always
Environment="OC_MONITOR_KEY=$(printf '%s' "$(build_flag 'V1')" | sha256sum | cut -c1-32)"

[Install]
WantedBy=multi-user.target
EOF

# --- Internal API (FUNCTIONAL loot for V1 + D2): a root-only service on
# 127.0.0.1:8899 returns a secret ONLY for a valid API key. Keys leak via the
# service unit (V1, `systemctl cat oc-monitor`) and a shell profile (D2). The
# flags live ONLY in the 700-root API script and are served over HTTP -> no
# plaintext FLAG{ any student can read. Realistic (internal API + leaked key)
# and functional (a real HTTP service).
mkdir -p /opt/oc/.internal
cat > /opt/oc/.internal/api.py << PYEOF
#!/usr/bin/env python3
import http.server, urllib.parse
SECRETS = {
    "$(printf '%s' "$(build_flag 'V1')" | sha256sum | cut -c1-32)": "$(build_flag 'V1')",
    "$(printf '%s' "$(build_flag 'D2')" | sha256sum | cut -c1-32)": "$(build_flag 'D2')",
}
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        key = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query).get("key", [""])[0]
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers()
        if key in SECRETS:
            self.wfile.write(('{"status":"ok","secret":"%s"}\n' % SECRETS[key]).encode())
        else:
            self.wfile.write(b'{"status":"unauthorized","hint":"valid X-API-Key / ?key= required"}\n')
    def log_message(self, *a):
        return
http.server.HTTPServer(("127.0.0.1", 8899), H).serve_forever()
PYEOF
chmod 700 /opt/oc/.internal
chmod 700 /opt/oc/.internal/api.py

cat > /opt/oc/monitor.sh << 'EOF'
#!/bin/bash
# OC internal monitoring endpoint (loopback only).
exec /usr/bin/python3 /opt/oc/.internal/api.py
EOF
chmod 755 /opt/oc/monitor.sh
# Actually START the API (the unit used to just hold a flag in its env; now it
# serves the internal API and MUST run for V1/D2 to be reachable).
systemctl daemon-reload 2>/dev/null || true
systemctl enable --now oc-monitor.service 2>/dev/null || true

# ===============================================
# VULNERABILITY 9: Database Configurations
# ===============================================
echo -e "${YELLOW}[*] Setting up database vulnerabilities...${NC}"

# Create MySQL configuration with weak credentials
mkdir -p /etc/mysql/conf.d
cat > /etc/mysql/conf.d/oc.cnf << EOF
# OC MySQL Configuration -- read-only reporting account (client default).
# NOTE: this file is world-readable and is auto-loaded by the mysql client, so
# any local user inherits these creds -> SELECT from the internal DB. (M2 flag
# lives in internal.secrets, seeded by Install-OCWA -- not in this file.)
[client]
user=oc_user
password=weakpass123
EOF
chmod 644 /etc/mysql/conf.d/oc.cnf 2>/dev/null || true

# --- L1 (REALISTIC + FUNCTIONAL): a leftover, world-readable DB-backup script
# hardcodes a WORKING Postgres credential (a genuinely common finding). Using it,
# the student connects and SELECTs a "customer" PII record whose notes field is
# the flag. Weakness = secret in a readable script; consequence = DB access + PII.
# Grep-proof: the flag lives in Postgres data (dir is 700 postgres), not any text
# file a low-priv shell can read. No plaintext FLAG{ on disk for the student.
if command -v psql >/dev/null 2>&1; then
    systemctl enable --now postgresql 2>/dev/null || true
    # wait briefly for the cluster socket
    for _i in 1 2 3 4 5; do sudo -u postgres psql -tAc 'SELECT 1' >/dev/null 2>&1 && break; sleep 1; done
    PG_APP_PW='Pg_App_S3cret!'
    L1_VALUE="$(build_flag 'L1')"
    sudo -u postgres psql -v ON_ERROR_STOP=0 >/dev/null 2>&1 <<SQL || true
DO \$\$ BEGIN IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname='oc_app') THEN CREATE ROLE oc_app LOGIN PASSWORD '${PG_APP_PW}'; END IF; END \$\$;
SELECT 'CREATE DATABASE ocdb OWNER oc_app' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='ocdb')\gexec
SQL
    sudo -u postgres psql -d ocdb -v ON_ERROR_STOP=0 >/dev/null 2>&1 <<SQL || true
CREATE TABLE IF NOT EXISTS customers (id serial PRIMARY KEY, name text, email text, notes text);
INSERT INTO customers (name,email,notes)
  SELECT 'Internal Audit','audit@chchcheckit.com','${L1_VALUE}'
  WHERE NOT EXISTS (SELECT 1 FROM customers WHERE notes LIKE 'FLAG{%');
INSERT INTO customers (name,email,notes)
  SELECT 'Alice Reyes','areyes@chchcheckit.com','VIP account'
  WHERE NOT EXISTS (SELECT 1 FROM customers WHERE name='Alice Reyes');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO oc_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO oc_app;
SQL
    mkdir -p /opt/oc/scripts
    cat > /opt/oc/scripts/pg_backup.sh << EOF
#!/bin/bash
# Nightly customer-DB backup (left in place by a former admin).
# TODO: move this credential into the vault -- do NOT ship to prod.
export PGPASSWORD='${PG_APP_PW}'
pg_dump -h 127.0.0.1 -U oc_app ocdb > "/var/backups/ocdb_\$(date +%F).sql"
EOF
    chmod 644 /opt/oc/scripts/pg_backup.sh
    echo -e "${GREEN}  [+] L1 functional Postgres loot planted (ocdb.customers + readable backup script)${NC}"
else
    echo -e "${RED}  [!] postgres unavailable - L1 functional flag skipped${NC}"
fi

# ===============================================
# VULNERABILITY 10: Kernel and System Files
# ===============================================
echo -e "${YELLOW}[*] Setting up kernel/system vulnerabilities...${NC}"

# Create kernel module loading configuration
# B1 (FUNCTIONAL): a service token leaks in a world-readable worker config.
mkdir -p /opt/oc/configs
cat > /opt/oc/configs/service.env << SVCEOF
# OC background worker config
WORKER_CONCURRENCY=4
SERVICE_TOKEN=$(jwt_flag 'B1' 'worker')
SVCEOF
chmod 644 /opt/oc/configs/service.env
echo "# kernel module tuning" > /etc/modprobe.d/oc.conf
echo "options dummy numdummies=2" >> /etc/modprobe.d/oc.conf
chmod 644 /etc/modprobe.d/oc.conf

# ===============================================
# VULNERABILITY 11: Docker Misconfigurations
# ===============================================
echo -e "${YELLOW}[*] Setting up Docker vulnerabilities...${NC}"

# Add users to docker group (docker.io is installed at the top of this script).
# The docker group grants effective root, which is the intended privesc path, so
# the daemon must be enabled and running for it to be exploitable.
if command -v docker &> /dev/null; then
    usermod -aG docker user1 2>/dev/null || true
    usermod -aG docker developer 2>/dev/null || true

    # daemon.json only HINTS — the flag is NOT here (grep-proof). The reward is a
    # root-only file, reachable only via the docker-group -> root escape, e.g.
    #   docker run -v /:/mnt --rm alpine cat /mnt/root/.docker_flag
    # NOTE: dockerd REJECTS unknown keys (a "comment" key crash-loops the daemon and
    # made this flag unreachable). Carry the hint in the valid "labels" option instead.
    mkdir -p /etc/docker
    echo '{"debug": true, "labels": ["oc.audit=on", "oc.hint=secrets-relocated-to-root-store"]}' > /etc/docker/daemon.json
    chmod 644 /etc/docker/daemon.json
    echo "$(build_flag 'G3')" > /root/.docker_flag
    chmod 600 /root/.docker_flag

    # Make the docker-group privesc real: enable + start the daemon.
    systemctl enable --now docker 2>/dev/null || true

    # Pre-pull the alpine image so the documented docker-group escape
    #   docker run -v /:/mnt --rm alpine cat /mnt/root/.docker_flag
    # works reliably even if Docker Hub is slow/unreachable at exploit time.
    sleep 3
    docker pull alpine 2>/dev/null || echo -e "${YELLOW}  [!] could not pre-pull alpine now (Flag G3 docker path needs it cached or Hub access)${NC}"
else
    echo -e "${RED}  [!] docker not installed - Flag 'G3' (/etc/docker/daemon.json) skipped${NC}"
fi

# ===============================================
# VULNERABILITY 12: Application Configuration Files
# ===============================================
echo -e "${YELLOW}[*] Setting up application configuration vulnerabilities...${NC}"

# Create application config in /opt
mkdir -p /opt/webapp/config
cat > /opt/webapp/config/database.yml << EOF
production:
  adapter: mysql2
  encoding: utf8
  database: webapp_prod
  username: webapp_user
  password: SecretPass123
  host: localhost
  # secret_key_base + reporting creds stored in the internal DB (see ops runbook)
EOF
chmod 644 /opt/webapp/config/database.yml

# ===============================================
# VULNERABILITY 13: Log Files
# ===============================================
echo -e "${YELLOW}[*] Setting up log file vulnerabilities...${NC}"

# Create world-readable log with sensitive info
echo "System initialized at $(date)" > /var/log/oc.log
echo "Admin password changed to: P@ssw0rd123" >> /var/log/oc.log
echo "$(date '+%Y-%m-%d %H:%M:%S') oc-auth[1123]: issued service token to svc-auth: $(jwt_flag 'F1' 'svc-auth')" >> /var/log/oc.log
chmod 644 /var/log/oc.log

# Create application log
mkdir -p /var/log/webapp
echo "[$(date)] Database connection established" > /var/log/webapp/app.log
echo "[$(date)] User 'admin' logged in successfully" >> /var/log/webapp/app.log
echo "[$(date)] DEBUG session_jwt=$(jwt_flag 'G2' 'web-user') user=brandon path=/account" >> /var/log/webapp/app.log
chmod 644 /var/log/webapp/app.log

# ===============================================
# VULNERABILITY 14: Environment Variables
# ===============================================
echo -e "${YELLOW}[*] Setting up environment variable vulnerabilities...${NC}"

# Add flag to environment
# D2 (FUNCTIONAL): a real internal-API key leaks in a shell profile. Using it
# against the 127.0.0.1:8899 internal API returns the secret. The sk-... line is
# a STALE decoy key the API rejects (teaches "verify your creds").
echo "# OC internal API key (rotate quarterly)" >> /etc/profile.d/oc.sh
echo "export OC_API_KEY='$(printf '%s' "$(build_flag 'D2')" | sha256sum | cut -c1-32)'" >> /etc/profile.d/oc.sh
echo "export API_KEY='sk-1234567890abcdef'" >> /etc/profile.d/oc.sh
chmod 644 /etc/profile.d/oc.sh

# ===============================================
# VULNERABILITY 15: Binary Exploitation
# ===============================================
echo -e "${YELLOW}[*] Creating vulnerable binaries...${NC}"

# Create vulnerable C program with HARD flag
cat > /tmp/vuln.c << EOF
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

void secret_function() {
    system("echo '$(enc_b64 'N2')' | base64 -d");
}

void vulnerable_function(char *input) {
    char buffer[64];
    strcpy(buffer, input);
    printf("You entered: %s\n", buffer);
}

int main(int argc, char *argv[]) {
    if (argc != 2) {
        printf("Usage: %s <input>\n", argv[0]);
        return 1;
    }
    vulnerable_function(argv[1]);
    return 0;
}
EOF

# Compile the SUID buffer-overflow challenge. The original swallowed all errors
# with `2>/dev/null || true`, so on a host without gcc the binary silently never
# appeared (Flag 'N2' missing). gcc/binutils are installed at the top of this
# script; verify the result and warn loudly instead of failing silently.
if command -v gcc >/dev/null 2>&1; then
    if gcc -o /opt/oc/vulnerable_binary /tmp/vuln.c -fno-stack-protector -no-pie; then
        chmod +s /opt/oc/vulnerable_binary
        echo -e "${GREEN}  [+] vulnerable_binary compiled and SUID-set${NC}"
    else
        echo -e "${RED}  [!] gcc compile FAILED - Flag 'N2' vulnerable_binary NOT created${NC}"
    fi
else
    echo -e "${RED}  [!] gcc not available - Flag 'N2' vulnerable_binary NOT created${NC}"
fi
rm -f /tmp/vuln.c

# ===============================================
# VULNERABILITY 16: Archive Files
# ===============================================
echo -e "${YELLOW}[*] Creating archive files with flags...${NC}"

# T1 (FUNCTIONAL): the backup archive leaks a WORKING SSH private key. Extract
# it -> ssh in as svc_backup (a key-only account, so the leaked key is the ONLY
# way in) -> read the flag in its home. Realistic: keys left in old backups.
useradd -m -s /bin/bash svc_backup 2>/dev/null || true
passwd -l svc_backup 2>/dev/null || true
mkdir -p /home/svc_backup/.ssh
ssh-keygen -q -t ed25519 -N '' -C 'svc_backup@oc' -f /tmp/oc_t1_key
cp /tmp/oc_t1_key.pub /home/svc_backup/.ssh/authorized_keys
chown -R svc_backup:svc_backup /home/svc_backup/.ssh
chmod 700 /home/svc_backup/.ssh
chmod 600 /home/svc_backup/.ssh/authorized_keys
echo "$(build_flag 'T1')" > /home/svc_backup/flag.txt
chown svc_backup:svc_backup /home/svc_backup/flag.txt
chmod 600 /home/svc_backup/flag.txt

mkdir -p /tmp/archive_tmp
cp /tmp/oc_t1_key /tmp/archive_tmp/id_ed25519
cat > /tmp/archive_tmp/notes.txt << EOF
Project Notes
=============
Server migration scheduled for next month
Old VPN credentials (deprecated): vpnuser:vpnpass123
Dev server: 10.0.0.50   Test server: 10.0.0.51
Backup service key: ./id_ed25519   (login: svc_backup@<host>)
EOF
tar -czf /var/backups/old_project.tar.gz -C /tmp/archive_tmp notes.txt id_ed25519
rm -rf /tmp/archive_tmp /tmp/oc_t1_key /tmp/oc_t1_key.pub
chmod 644 /var/backups/old_project.tar.gz

# ===============================================
# VULNERABILITY 17: Git Repositories
# ===============================================
echo -e "${YELLOW}[*] Setting up Git repository vulnerabilities...${NC}"

# Create Git repository in /opt
mkdir -p /opt/development/project
cd /opt/development/project
git init 2>/dev/null || true
echo "$(enc_b64 'L2')" > .env
echo "DATABASE_URL=mysql://root:password@localhost/db" >> .env
git add .env
git config user.email "dev@local.com" 2>/dev/null || true
git config user.name "Developer" 2>/dev/null || true
git commit -m "Initial commit - added environment file" 2>/dev/null || true
chmod -R 755 /opt/development

# ===============================================
# VULNERABILITY 18: Cryptographic Weaknesses
# ===============================================
echo -e "${YELLOW}[*] Setting up cryptographic vulnerabilities...${NC}"

# Create weakly encrypted file with HARD flag
echo "$(build_flag 'H4')" | openssl enc -aes-128-cbc -pass pass:password123 -out /opt/oc/encrypted_flag.enc 2>/dev/null || true
echo "Hint: Weak encryption password used (common password)" > /opt/oc/encrypted_flag.hint
chmod 644 /opt/oc/encrypted_flag.enc /opt/oc/encrypted_flag.hint

# Create base64 encoded "secret"
echo "$(build_flag 'S2')" | base64 > /var/oc/data/encoded_secret.b64
chmod 644 /var/oc/data/encoded_secret.b64

# ===============================================
# VULNERABILITY 19: Process Information
# ===============================================
echo -e "${YELLOW}[*] Creating process-based vulnerabilities...${NC}"

# Create script that runs with credentials in command line
cat > /opt/oc/scripts/db_backup.sh << 'EOF'
#!/bin/bash
while true; do
    mysqldump -u backup_user -p'BackupPass123!' webapp_db > /dev/null 2>&1
    sleep 300
done
EOF
chmod 755 /opt/oc/scripts/db_backup.sh

# ===============================================
# VULNERABILITY 20: Scheduled Tasks
# ===============================================
echo -e "${YELLOW}[*] Setting up scheduled task vulnerabilities...${NC}"

# Create at job script
cat > /var/spool/cron/atjobs/backup_job << EOF
#!/bin/bash
# Scheduled backup job
# $(enc_b64 'M2')
tar -czf /backup/system_$(date +%Y%m%d).tar.gz /etc/
EOF
chmod 644 /var/spool/cron/atjobs/backup_job 2>/dev/null || true

# ===============================================
# Generate Flag Report
# ===============================================
# ===============================================
# FINAL ROOT FLAG (Phase 8 privilege escalation)
# The walkthrough's Flag 25 reads /root/root.txt after a student escalates to
# root. The original script never created it. Place it root-only (0600) so it is
# obtainable ONLY after a successful privesc.
# ===============================================
echo -e "${YELLOW}[*] Planting final root flag (/root/root.txt)...${NC}"
echo "$(build_flag 'R2')" > /root/root.txt
chown root:root /root/root.txt
chmod 600 /root/root.txt

# Machine-readable flag values for cross-script use: Install-OCWA (which runs
# later, once MariaDB is up) seeds M2/G1 into the internal.secrets DB table.
# Root-only; students can't read /root.
cat > /root/.oc_flags.env << ENVEOF
M2='$(build_flag 'M2')'
G1='$(build_flag 'G1')'
ENVEOF
chmod 600 /root/.oc_flags.env

# On-box answer-key report DISABLED by design (v5 realism pass): a student who
# roots the box must NOT be able to read the full key. The report heredoc below is
# redirected to /dev/null so nothing persists. Generate the instructor key off-box,
# admin-only, with Generate-AnswerKey.py (reads the same OC_FLAG_SEED + flag keys).
echo -e "${DARKYELLOW:-${YELLOW}}[answer key] On-box report disabled; use Generate-AnswerKey.py (admin, off-box).${NC}"

REPORT_DATE=$(date '+%Y-%m-%d %H:%M:%S')
REPORT_FILE="/dev/null"

cat > "$REPORT_FILE" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>OC Flag Report - Debian v13.1 Webserver Lab v2.0</title>
    <style>
        body { font-family: Arial; margin: 20px; background: #f0f0f0; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 10px; }
        h1 { color: #333; border-bottom: 3px solid #9b59b6; padding-bottom: 10px; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th { background: #9b59b6; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        tr:hover { background: #f5f5f5; }
        .easy { color: green; font-weight: bold; }
        .medium { color: orange; font-weight: bold; }
        .hard { color: red; font-weight: bold; }
        .stats { background: #e8daef; padding: 15px; border-radius: 5px; margin: 20px 0; }
        .flag-code { font-family: 'Courier New'; background: #f0f0f0; padding: 2px 5px; border-radius: 3px; }
        .hp-theme { background: linear-gradient(135deg, #9b59b6 0%, #3498db 100%); color: white; padding: 10px; border-radius: 5px; margin-bottom: 20px; }
        .creds-section { background: #ffeaa7; padding: 15px; border-left: 5px solid #fdcb6e; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="container">
        <div class="hp-theme">
            <h1 style="color: white; border: none;">OC Webserver Flag Report - Debian v13.1</h1>
            <h2 style="color: white;">Educational Penetration Testing Lab v2.0</h2>
        </div>
        
        <div class="stats">
            <h2>Statistics</h2>
            <p><strong>Total Flags:</strong> 23</p>
            <p><strong>Easy Flags:</strong> 10</p>
            <p><strong>Medium Flags:</strong> 7</p>
            <p><strong>Hard Flags:</strong> 6</p>
            <p><strong>Report Generated:</strong> $REPORT_DATE</p>
        </div>
        
        <h2>Flag Details</h2>
        <table>
            <thead>
                <tr>
                    <th>ID</th>
                    <th>Flag</th>
                    <th>Location</th>
                    <th>Description</th>
                    <th>Difficulty</th>
                    <th>Technique</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td>001</td>
                    <td class="flag-code">$(build_flag 'H1')</td>
                    <td>User Description</td>
                    <td>Hidden in 'user1' user description</td>
                    <td class="easy">Easy</td>
                    <td>User enumeration</td>
                </tr>
                <tr>
                    <td>002</td>
                    <td class="flag-code">$(build_flag 'H2')</td>
                    <td>/opt/secrets/network_credentials.txt</td>
                    <td>Network credentials file (includes Windows creds)</td>
                    <td class="easy">Easy</td>
                    <td>File discovery</td>
                </tr>
                <tr>
                    <td>003</td>
                    <td class="flag-code">$(build_flag 'R1')</td>
                    <td>/var/backups/system/old_passwords.txt</td>
                    <td>Legacy password file</td>
                    <td class="easy">Easy</td>
                    <td>Backup enumeration</td>
                </tr>
                <tr>
                    <td>004</td>
                    <td class="flag-code">$(build_flag 'D1')</td>
                    <td>SSH Banner</td>
                    <td>SSH server banner</td>
                    <td class="easy">Easy</td>
                    <td>Service enumeration</td>
                </tr>
                <tr>
                    <td>005</td>
                    <td class="flag-code">$(build_flag 'H3')</td>
                    <td>/opt/oc/.secret</td>
                    <td>Hidden file in OC directory</td>
                    <td class="easy">Easy</td>
                    <td>Hidden file discovery</td>
                </tr>
                <tr>
                    <td>006</td>
                    <td class="flag-code">$(build_flag 'N1')</td>
                    <td>/tmp/.hidden/secret.txt</td>
                    <td>Hidden directory in /tmp</td>
                    <td class="easy">Easy</td>
                    <td>Directory traversal</td>
                </tr>
                <tr>
                    <td>007</td>
                    <td class="flag-code">$(build_flag 'L1')</td>
                    <td>/var/lib/postgresql/.pgpass</td>
                    <td>PostgreSQL password file</td>
                    <td class="easy">Easy</td>
                    <td>Database enumeration</td>
                </tr>
                <tr>
                    <td>008</td>
                    <td class="flag-code">$(build_flag 'G1')</td>
                    <td>/opt/webapp/config/database.yml</td>
                    <td>Application config file</td>
                    <td class="easy">Easy</td>
                    <td>Config file analysis</td>
                </tr>
                <tr>
                    <td>009</td>
                    <td class="flag-code">$(build_flag 'F1')</td>
                    <td>/var/log/oc.log</td>
                    <td>World-readable log file</td>
                    <td class="easy">Easy</td>
                    <td>Log file analysis</td>
                </tr>
                <tr>
                    <td>010</td>
                    <td class="flag-code">$(build_flag 'G2')</td>
                    <td>/var/log/webapp/app.log</td>
                    <td>Application debug log</td>
                    <td class="easy">Easy</td>
                    <td>Log enumeration</td>
                </tr>
                <tr>
                    <td>011</td>
                    <td class="flag-code">$(build_flag 'S1')</td>
                    <td>/usr/local/bin/backup_tool</td>
                    <td>SUID binary exploitation</td>
                    <td class="medium">Medium</td>
                    <td>SUID exploitation</td>
                </tr>
                <tr>
                    <td>012</td>
                    <td class="flag-code">$(build_flag 'S2')</td>
                    <td>/etc/sudoers.d/oc_flag</td>
                    <td>Sudoers configuration file</td>
                    <td class="medium">Medium</td>
                    <td>Sudo enumeration</td>
                </tr>
                <tr>
                    <td>013</td>
                    <td class="flag-code">$(build_flag 'L2')</td>
                    <td>/opt/scripts/cleanup.sh</td>
                    <td>Cron job script exploitation</td>
                    <td class="medium">Medium</td>
                    <td>Cron job hijacking</td>
                </tr>
                <tr>
                    <td>014</td>
                    <td class="flag-code">$(build_flag 'T1')</td>
                    <td>/var/backups/old_project.tar.gz</td>
                    <td>Archive file extraction</td>
                    <td class="medium">Medium</td>
                    <td>Archive analysis</td>
                </tr>
                <tr>
                    <td>015</td>
                    <td class="flag-code">$(build_flag 'M1')</td>
                    <td>/home/user1/.hidden_flag</td>
                    <td>Hidden file in home directory</td>
                    <td class="medium">Medium</td>
                    <td>User enumeration</td>
                </tr>
                <tr>
                    <td>016</td>
                    <td class="flag-code">$(build_flag 'M2')</td>
                    <td>/etc/mysql/conf.d/oc.cnf</td>
                    <td>MySQL configuration file</td>
                    <td class="medium">Medium</td>
                    <td>Database enumeration</td>
                </tr>
                <tr>
                    <td>017</td>
                    <td class="flag-code">$(build_flag 'D2')</td>
                    <td>/etc/profile.d/oc.sh</td>
                    <td>Environment variable</td>
                    <td class="medium">Medium</td>
                    <td>Environment analysis</td>
                </tr>
                <tr>
                    <td>018</td>
                    <td class="flag-code">$(build_flag 'V1')</td>
                    <td>oc-monitor.service</td>
                    <td>Service environment variable</td>
                    <td class="hard">Hard</td>
                    <td>Service exploitation</td>
                </tr>
                <tr>
                    <td>019</td>
                    <td class="flag-code">$(build_flag 'B1')</td>
                    <td>/etc/modprobe.d/oc.conf</td>
                    <td>Kernel module configuration</td>
                    <td class="hard">Hard</td>
                    <td>Kernel enumeration</td>
                </tr>
                <tr>
                    <td>020</td>
                    <td class="flag-code">$(build_flag 'G3')</td>
                    <td>/etc/docker/daemon.json</td>
                    <td>Docker configuration file</td>
                    <td class="hard">Hard</td>
                    <td>Container escape</td>
                </tr>
                <tr>
                    <td>021</td>
                    <td class="flag-code">$(build_flag 'N2')</td>
                    <td>/opt/oc/vulnerable_binary</td>
                    <td>Binary exploitation (buffer overflow)</td>
                    <td class="hard">Hard</td>
                    <td>Binary exploitation</td>
                </tr>
                <tr>
                    <td>022</td>
                    <td class="flag-code">$(build_flag 'H4')</td>
                    <td>/opt/oc/encrypted_flag.enc</td>
                    <td>Weak cryptography</td>
                    <td class="hard">Hard</td>
                    <td>Cryptanalysis</td>
                </tr>
                <tr>
                    <td>023</td>
                    <td class="flag-code">$(build_flag 'R2')</td>
                    <td>/root/root.txt</td>
                    <td>Final root flag (readable only after privilege escalation)</td>
                    <td class="hard">Hard</td>
                    <td>Privilege escalation</td>
                </tr>
            </tbody>
        </table>
    </div>
</body>
</html>
EOF
# Answer key stays root-only (0600) under /root (mode 700). Ideally the instructor
# keeps it OFF the box; hardened so a rooted student gains nothing unearned.
# NOTE: the on-box report is disabled (REPORT_FILE=/dev/null); guard the chmod so we
# never alter /dev/null's permissions (a 600 /dev/null breaks non-root redirects box-wide).
[ "$REPORT_FILE" != "/dev/null" ] && chmod 600 "$REPORT_FILE" || true

# ===============================================
# Final Setup Steps
# ===============================================
echo -e "${GREEN}[+] Performing final setup steps...${NC}"

# Set proper permissions
chmod 755 /opt/oc
chmod 755 /var/oc
chmod 755 /opt/secrets

# Restart services
systemctl restart ssh 2>/dev/null || true
systemctl daemon-reload 2>/dev/null || true

# --- DECOY canaries: punish a blind `grep -rIa 'FLAG{' /`. The answer key /
# submission system MUST reject every FLAG{DECOY_*}. These sit in the most obvious
# grep magnets so lazy students burn time; the real flags are encoded/gated.
printf 'OC_AUDIT_TOKEN=FLAG{DECOY_TRY_HARDER_9F2A}\n' >> /etc/environment
echo "# TODO(dev): rotate before prod -- FLAG{DECOY_NOT_THIS_ONE_4C1B}" >> /opt/webapp/config/database.yml
sed -i '1i # legacy marker FLAG{DECOY_KEEP_LOOKING_7A33}' /var/log/oc.log 2>/dev/null || true
echo "backup verified FLAG{DECOY_ALMOST_5E90}" >> /var/backups/system/old_passwords.txt

# Create setup completion marker
touch /opt/oc/.setup_complete
date > /opt/oc/.setup_complete

# ===============================================
# Summary
# ===============================================
echo -e "${GREEN}===============================================${NC}"
echo -e "${GREEN}    OC Setup Complete!${NC}"
echo -e "${GREEN}===============================================${NC}"
echo -e "${BLUE}Total Flags Planted:${NC}"
echo -e "  Easy:   10 flags"
echo -e "  Medium: 7 flags"
echo -e "  Hard:   6 flags"
echo -e ""
echo -e "${YELLOW}Network Credentials Location:${NC}"
echo -e "  /opt/secrets/network_credentials.txt"
echo -e "  - Windows Server 2019: user1:Password123!"
echo -e "  - Windows 10 #1: jsmith:Welcome1"
echo -e "  - Windows 10 #2: mjones:Password1"
echo -e ""
echo -e "${YELLOW}Flag Report Location:${NC}"
echo -e "  /root/OC_FLAGS_REPORT_*.html"
echo -e ""
echo -e "${YELLOW}Important Users Created:${NC}"
echo -e "  user1:password123 (main OC user)"
echo -e "  developer:dev123"
echo -e "  admin_backup:admin"
echo -e ""
echo -e "${YELLOW}Note:${NC}"
echo -e "  If SSH is not installed, some flags may be in alternate locations"
echo -e "  Check /etc/banner/ directory for SSH-related flags"
echo -e ""
echo -e "${RED}WARNING:${NC} This system is now intentionally vulnerable!"
echo -e "Use only in isolated, educational environments."
echo -e "${GREEN}===============================================${NC}"
