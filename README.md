# HTTPS-Ready Nginx Docker

Setting up HTTPS by hand is fiddly: install certbot, wire the ACME challenge, point Nginx at the cert files, and renew before they expire. Nginx also won't start if its config names a cert that doesn't exist yet, so the first boot is a chicken-and-egg problem.

This container solves that. Nginx and certbot run together and handle issuing, installing, and renewing the certificate.

## What it does

- Boots Nginx behind a temporary self-signed cert, so the server is up before a real cert exists.
- Requests a Let's Encrypt cert, swaps to it, and reloads Nginx.
- Renews on a schedule and reloads when the cert changes.
- Reads the domain and email from `.env`; picks up subdomains from drop-in `.conf` files.

Set three variables, point the config at your frontend, and run `docker-compose up -d`. HTTPS works from the first second, and the browser warning clears once the real cert arrives.

## Two ways to validate

Let's Encrypt must confirm you control the domain. This repo offers both methods, one per folder. See that folder's README to set it up.

| | [`HTTP-01/`](HTTP-01/) | [`DNS-01/`](DNS-01/) |
|---|---|---|
| How it proves control | Serves a file on port 80 | Adds a DNS TXT record |
| Needs port 80 reachable | Yes | No |
| Wildcard certificate | No | Yes, covers every subdomain |
| Extra requirement | None | Cloudflare API token |
| Good when | The server is public on port 80 | Port 80 is closed, or you want a wildcard |

Pick `HTTP-01/` for a public server that answers on port 80. Pick `DNS-01/` for a wildcard cert or when port 80 is closed, with DNS on Cloudflare.

## Prerequisites

- Docker and Docker Compose
- A domain pointed at your server
- For `DNS-01/`, a Cloudflare API token with DNS edit permission
