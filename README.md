# Portal Server

Automated Debian 13 deployment for the DNS Security Portal and the
NetFortress Firewall Appliance.

One launcher, three deployment options:

| Option | Deployment | What is installed |
|---|---|---|
| 1 | Management Portal + Technitium DNS | PostgreSQL, NGINX, PHP-FPM, FastAPI Portal, Technitium DNS |
| 2 | Management Portal + NetFortress Firewall Appliance **(recommended)** | Both on one server: the full Portal stack **plus** the NetFortress appliance (API on 127.0.0.1:8080) |
| 3 | NetFortress Firewall Appliance (standalone) | The appliance only — no Portal, no Technitium, no PostgreSQL |

## Requirements

- Clean Debian 13 installation
- Root access
- Internet access during installation (packages, updates, licensing server)

## Installation

Clone the repository and run the launcher:

    git clone https://github.com/chriscc12345/DNS-Dashboard.git /opt/portal-installer
    cd /opt/portal-installer
    ./install.sh

The launcher presents a graphical menu (whiptail). For unattended installs:

    ./install.sh --backend technitium   # option 1
    ./install.sh --backend firewall     # option 2
    ./install.sh --backend netfortress  # option 3

All input prompts are graphical dialog boxes when a terminal is
available, with plain-text fallbacks for piped installs.

## Option 2 — Management Portal + NetFortress (recommended)

Installs both on the same server:

- **Portal**: NGINX on 80/443 (its own vhost), PHP-FPM, PostgreSQL,
  FastAPI on 127.0.0.1:8000
- **NetFortress appliance**: API on 8080 (web console
  `http://<server>:8080`), DNS block page on port 80, captive portal
  on 8420, dnsmasq DNS, Kea DHCP, Squid, blocklists, guarded
  transaction tooling

The Portal drives DNS blocking through the appliance API via the
provider abstraction (`portal_settings.dns_provider = firewall`):

- Unblock requests, approvals and denials apply on the appliance
  within seconds (guarded DNS transactions; the appliance reconciler
  catches up within a minute as a safety net)
- **User sync**: adding a user in the Portal mirrors the user into
  the appliance; when the appliance licence reaches its account
  limit the Portal shows the appliance's limit message and the user
  is not created
- **Unified administrator setup**: the Portal setup page
  (`https://<hostname>/setup.php`) creates ONE administrator account
  for both the Portal and the appliance — no credentials are entered
  during installation
- Licence edition limits (including account limits) apply to Portal
  user creation

## NetFortress licensing

- A fresh appliance starts a **60-day full-feature trial
  automatically** on install (issued by the licensing server, one
  trial per installation)
- When the trial runs out, the appliance **automatically continues
  on the free Home Lite licence** (10 devices, one account, full
  core protection)
- Paid editions (Home, Essential, Professional, Corporate) unlock
  more devices, accounts and features

## Update framework

Installed portals track an update level
(`/var/lib/portal/update-version`). The installer applies all
pending updates automatically at install time; each update is
SHA256-verified, backed up before applying and rolled back on
failure.

Current updates:

1. User Profile case-insensitive username fixes
2. User management and initial administrator setup
3. Profiles, appearance, themes and favicon management
4. Complete customization configuration and permissions
5. Portal identity, two-factor authentication, monitoring and DNS services
6. Network services provider abstraction and Firewall Appliance support
7. Unified initial administrator setup (Portal + appliance)

## Security notes

- Portal and appliance authentication are independent and
  portal-owned (bcrypt + optional TOTP two-factor)
- The appliance integration uses a scoped API token
  (`dns:read`, `dns:write`, `users:read`, `users:write`)
- Firewall rule enforcement stays in the appliance's guarded
  candidate-only mode until an administrator deploys policy from the
  appliance console; DNS blocking enforces immediately
- No firewall or fail2ban configuration is performed by these
  installers beyond what the NetFortress appliance itself manages