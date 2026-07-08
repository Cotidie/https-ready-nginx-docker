#!/bin/bash

set -e

if [ -z "$SSL_DOMAIN" ]; then
    log_error "SSL_DOMAIN environment variable is not set."
    exit 1
fi

if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    log_error "CLOUDFLARE_API_TOKEN environment variable is not set."
    exit 1
fi

# ==============================================================================
# Configuration
# ==============================================================================
readonly SSL_DIR="/etc/nginx/ssl"
readonly CF_CREDENTIALS="/etc/letsencrypt/cloudflare.ini"
readonly CERTBOT_BASE="/etc/letsencrypt/live"
readonly CERTBOT_DIR="$CERTBOT_BASE/$SSL_DOMAIN"
readonly DNS_PROPAGATION_SECONDS=30

# ==============================================================================
# Logging Helpers
# ==============================================================================
log_info() {
    echo "[INFO] $1"
}

log_error() {
    echo "[ERROR] $1" >&2
}

# ==============================================================================
# Domain Logic
# ==============================================================================
build_domain_list() {
    # Wildcard covers every first-level subdomain; apex needs an explicit entry.
    echo "$SSL_DOMAIN *.$SSL_DOMAIN"
}

# ==============================================================================
# Infrastructure Setup
# ==============================================================================
ensure_directories() {
    mkdir -p "$SSL_DIR"
}

write_cloudflare_credentials() {
    mkdir -p "$(dirname "$CF_CREDENTIALS")"
    printf 'dns_cloudflare_api_token = %s\n' "$CLOUDFLARE_API_TOKEN" > "$CF_CREDENTIALS"
    chmod 600 "$CF_CREDENTIALS"
}

# ==============================================================================
# Certificate Management
# ==============================================================================
is_cert_available() {
    [ -d "$CERTBOT_DIR" ] && \
    [ -f "$CERTBOT_DIR/fullchain.pem" ] && \
    [ -f "$CERTBOT_DIR/privkey.pem" ]
}

link_certificate() {
    local crt="$1"
    local key="$2"

    ln -sf "$crt" "$SSL_DIR/current.crt"
    ln -sf "$key" "$SSL_DIR/current.key"
}

create_dummy_certificate() {
    if [ ! -f "$SSL_DIR/current.crt" ]; then
        log_info "Generating dummy self-signed certificate..."
        openssl req -x509 -nodes -newkey rsa:4096 -days 1 \
            -keyout "$SSL_DIR/dummy.key" \
            -out "$SSL_DIR/dummy.crt" \
            -subj "/CN=localhost" \
            2>/dev/null

        link_certificate "$SSL_DIR/dummy.crt" "$SSL_DIR/dummy.key"
    fi
}

request_lets_encrypt_cert() {
    local domain_list=$(build_domain_list)
    log_info "Requesting Let's Encrypt certificate (DNS-01) for: $domain_list"

    # Construct argument array for safer handling
    local certbot_args=(
        "certonly"
        "--dns-cloudflare"
        "--dns-cloudflare-credentials" "$CF_CREDENTIALS"
        "--dns-cloudflare-propagation-seconds" "$DNS_PROPAGATION_SECONDS"
        "--email" "$SSL_EMAIL"
        "--rsa-key-size" "4096"
        "--agree-tos"
        "--non-interactive"
    )

    for domain in $domain_list; do
        certbot_args+=("-d" "$domain")
    done

    if certbot "${certbot_args[@]}"; then
        return 0
    else
        log_error "Certbot request failed."
        return 1
    fi
}

start_renewal_loop() {
    log_info "Starting renewal loop..."
    (
        while true; do
            sleep 12h
            certbot renew \
                --quiet \
                --deploy-hook "nginx -s reload"
        done
    ) &
}

# ==============================================================================
# Nginx Control
# ==============================================================================
start_nginx() {
    log_info "Starting Nginx..."
    nginx -g "daemon off;" &
    NGINX_PID=$!
}

reload_nginx() {
    log_info "Reloading Nginx configuration..."
    nginx -s reload
}

# ==============================================================================
# Main Orchestrator
# ==============================================================================
main() {
    ensure_directories
    write_cloudflare_credentials
    create_dummy_certificate

    start_nginx
    sleep 5

    if is_cert_available; then
        log_info "Found existing Let's Encrypt certificate for $SSL_DOMAIN"
        link_certificate "$CERTBOT_DIR/fullchain.pem" "$CERTBOT_DIR/privkey.pem"
        reload_nginx
    else
        if request_lets_encrypt_cert; then
            log_info "Switching to real certificate..."
            link_certificate "$CERTBOT_DIR/fullchain.pem" "$CERTBOT_DIR/privkey.pem"
            reload_nginx
        else
            log_error "Failed to obtain real certificate. Continuing with dummy certificate."
        fi
    fi

    start_renewal_loop
    wait "$NGINX_PID"
}

main
