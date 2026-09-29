# Portal

A clean, self-contained management portal for network security teams:
user and permission management, a domain-blocking request workflow
(pending / approved / denied), profiles with custom fields, two-factor
authentication, notification channels, monitoring and appearance
customisation — backed by PostgreSQL and served through NGINX.

The portal installs **without a network services backend**. After the
initial setup you select one from **Settings → System Status** and the
portal provisions and configures it in the background, then adapts
its pages and permissions to the selected backend automatically.

## Network services backends

| Backend | What it does |
|---|---|
| **Technitium DNS Server** | Downloaded from Technitium's official site and installed on this server. Domain blocking, DNS services (blocking, recursion, cache, DHCP, proxy) and the DNS certificate are managed from the portal. |
| **NetFortress Firewall Appliance** | Downloaded from [netfortress.tech](https://netfortress.tech). Domain blocking with live DNS enforcement, user shadowing with licence account limits, and a full firewall appliance console alongside the portal. Learn more at the [NetFortress website](https://netfortress.tech). |

The portal is the source of truth on both integrations: users live in
the portal and are pushed to the backend; the request workflow drives
blocking through whichever backend is active.

## Installation

Requirements: a clean Debian 13 (trixie) server, root access.

```bash
git clone https://github.com/chriscc12345/dns-dashboard.git
cd dns-dashboard
./install.sh                # interactive
# or unattended:
./install.sh --hostname portal.example.com
```

The installer sets up PostgreSQL, NGINX, PHP-FPM and the Portal API,
then prints the address of the initial setup page.

## After installation

1. Open `https://<portal-hostname>/` and complete the initial setup
   (the first administrator account).
2. Sign in and open **Settings → System Status**.
3. Select **Technitium DNS Server** or **NetFortress Firewall
   Appliance** and click **Provision Backend**. The portal downloads,
   installs and configures the backend in the background — progress is
   shown on the page — and the portal adapts once it completes.

Blocked-domain visitors reach the Access Denied page with a request
form; approved requests unblock the domain for the allowed time and
re-block automatically when it expires.

## Updates

Portal releases are delivered from the NetFortress update server:
installed portals periodically check for new versions and show an
update banner in the admin UI. (The appliance receives its updates
through the same channel via its licence sync.)

## Repository layout

```
install.sh                      single portal installer
portal/portal-source.tar.gz     clean portal v1.0 source
database/                       database baselines (portal + monitoring)
nginx/                          portal NGINX vhost template
systemd/                        portal-api + heartbeat units
requirements.txt                Python dependencies
```
