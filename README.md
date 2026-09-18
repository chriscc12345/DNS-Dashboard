# Portal Server

Automated Debian 13 installer for the Portal Server environment.

## Components

The installer deploys and configures:

- PostgreSQL 17
- NGINX
- PHP 8.4 FPM
- Python / FastAPI
- Technitium DNS Server
- Portal database
- Portal web interface
- Portal API systemd service
- HTTPS with a self-signed certificate
- Dedicated Technitium portal-api API user and token

## Requirements

- Clean Debian 13 installation
- Root access
- Internet access during installation

## Installation

Clone the repository:

    git clone https://github.com/chriscc12345/DNS-Dashboard.git /opt/portal-installer
    cd /opt/portal-installer

Run the installer:

    chmod +x install.sh
    ./install.sh

The installer installs the required packages, restores the Portal database
and application, configures services, generates runtime credentials,
configures Technitium integration, and performs final service checks.

## Services

- PostgreSQL: postgresql
- NGINX: nginx
- PHP-FPM: php8.4-fpm
- Portal API: portal-api.service
- Technitium DNS: dns.service

## Portal

The installer asks for the Portal hostname during installation.

Default hostname:

    portal.example.com

Example Portal URL after installation:

    https://portal.example.com/dashboard.php

FastAPI listens locally on:

    http://127.0.0.1:8000

Technitium listens locally on:

    http://127.0.0.1:5380/

## Security

The repository does not contain production database passwords or
Technitium API tokens.

Runtime credentials are generated and configured during installation.

The installer intentionally does not configure:

- Firewall rules
- Fail2Ban

These can be configured separately according to the deployment environment.

## Updates

Application updates are maintained separately from the validated base
installer.

The base installer remains unchanged while application fixes and
enhancements are distributed through the updates mechanism.

## Supported Operating System

Debian GNU/Linux 13.

## Important

Review the configuration before deploying to a production environment.

The included HTTPS certificate is self-signed. Replace it with a trusted
certificate where appropriate.
