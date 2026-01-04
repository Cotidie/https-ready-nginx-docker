# HTTPS-Ready Nginx Docker

This Nginx based docker automates the process of issueing and renewal of SSL certificates using `certbot` and `letsencrypt`. It works by starting Nginx immediately with a temporary self-signed certificat (`openssl`) then requests a valid certificate from Let's Encrypt.

## Features

```mermaid
sequenceDiagram
    title HTTPS Certificate Issuance Flow (Nginx + Certbot)

    participant Script as Entrypoint.sh
    participant OpenSSL
    participant Nginx
    participant Certbot
    participant LE as Let's Encrypt

    Note over Script: Container Startup

    Script->>Script: Check existing TLS cert

    alt No cert found
        Script->>OpenSSL: Generate dummy cert
        OpenSSL-->>Script: Dummy cert ready
    end

    Script->>Nginx: Start Nginx

    Script->>Certbot: Request cert (webroot)
    Certbot->>LE: Start ACME validation

    LE->>Nginx: HTTP challenge
    Nginx-->>LE: Serve challenge

    LE-->>Certbot: Issue certificate
    Certbot-->>Script: Store cert

    Script->>Nginx: Reload Nginx
```

```mermaid
sequenceDiagram
    title HTTPS Certificate Renewal Flow (Periodic)

    participant Script as Entrypoint.sh
    participant Certbot
    participant Nginx
    participant LE as Let's Encrypt

    Note over Script: Periodic Job (every 12h)

    Script->>Certbot: Check renewal

    alt Cert near expiry
        Certbot->>LE: Renew certificate
        LE-->>Certbot: New certificate issued
        Certbot->>Nginx: Reload Nginx (post-hook)
    else Cert still valid
        Note over Certbot: No action
    end
```

- **Default SSL:** Automatically installs Let's Encrypt certificates inside container
- **Auto-Renewal:** Crontab schedule checks for TLS renewals every 12 hours and reloads Nginx automatically.
- **Persistence:** Keeps certificates persistent in Docker Volume
    - `certbot_conf`: Let's Encrypt certificates.
    - `certbot_www`: ACME challenge files.

## Prerequisites

- Docker and Docker Compose
- A running server with public IP

## Quick Start

1. **Clone the repository** on your public server
   ```bash
   git clone <repository-url>
   cd https-ready-nginx-docker
   ```

2. **Configure Environment** for SSL certificates
   Edit a `.env` file in the root directory:
   ```bash
   SSL_DOMAIN=example.com
   SSL_SUBDOMAINS=www,api
   SSL_EMAIL=cotidie@kaist.ac.kr
   ```

3. **Configure Nginx**
   - **Main Domain:** Edit `nginx.conf` and replace `<your domain>` with your actual domain name (e.g., `example.com`).
   - **Subdomains:** Place any subdomain configurations (like `api.example.com`) in the `apps/` directory.
     - You can find examples in the `subdomains/` folder.
     - Ensure your subdomain config files end with `.conf`.

4. **Run**
   ```bash
   docker-compose up -d
   ```

   Your server will be available immediately at `https://example.com`. You may see a browser warning initially (due to the dummy cert), which will disappear once the Let's Encrypt certificate is successfully acquired (usually within a few seconds).

## Configuration

| Variable | Description | Required |
|----------|-------------|:--------:|
| `SSL_DOMAIN` | The domain name for the certificate. | Yes |
| `SSL_SUBDOMAINS` | Comma-separated list of subdomains (e.g., `www,api`). | No |
| `SSL_EMAIL` | Email address for Let's Encrypt registration and recovery. | Yes |


