#!/bin/bash

#
# Entrypoint script for Nginx + Certbot container.
#
# Responsibilities:
# - Build domain list from DOMAIN and optional SUBDOMAINS
# - Generate a temporary self-signed certificate if no valid cert exists
# - Start Nginx using the dummy certificate
# - Request a real Let's Encrypt certificate via Certbot (webroot)
# - Swap in the real certificate and reload Nginx
# - Run a background auto-renewal
#
# This script is designed to be run inside docker container
#


set -e

SSL_DIR="/etc/nginx/ssl"
WEBROOT="/var/www/certbot"
CERTBOT_BASE="/etc/letsencrypt/live"

#######################################
# Domain handling
#######################################
build_domains() {
    local domains="$DOMAIN"

    if [ -n "$SUBDOMAINS" ]; then
        for sub in $(echo "$SUBDOMAINS" | tr ',' ' '); do
            domains="$domains $sub.$DOMAIN"
        done
    fi

    echo "$domains"
}

#######################################
# Filesystem prep
#######################################
prepare_dirs() {
    mkdir -p "$SSL_DIR" "$WEBROOT"
}

#######################################
# Certificate helpers
#######################################
certbot_dir() {
    echo "$CERTBOT_BASE/$DOMAIN"
}

has_real_cert() {
    [ -d "$(certbot_dir)" ]
}

link_cert() {
    local crt="$1"
    local key="$2"

    ln -sf "$crt" "$SSL_DIR/current.crt"
    ln -sf "$key" "$SSL_DIR/current.key"
}

generate_dummy_cert() {
    openssl req -x509 -nodes -newkey rsa:4096 -days 1 \
        -keyout "$SSL_DIR/dummy.key" \
        -out "$SSL_DIR/dummy.crt" \
        -subj "/CN=localhost"
}

setup_initial_cert() {
    if has_real_cert; then
        echo "Using existing Let's Encrypt certificate"
        link_cert "$(certbot_dir)/fullchain.pem" "$(certbot_dir)/privkey.pem"
        return
    fi

    if [ ! -f "$SSL_DIR/current.crt" ]; then
        echo "Generating dummy certificate"
        generate_dummy_cert
        link_cert "$SSL_DIR/dummy.crt" "$SSL_DIR/dummy.key"
    fi
}

#######################################
# Nginx
#######################################
render_nginx_conf() {
    export DOMAIN NGINX_SERVER_NAMES
    envsubst '${NGINX_SERVER_NAMES} ${DOMAIN}' \
        < /etc/nginx/conf.d/default.conf.template \
        > /etc/nginx/conf.d/default.conf
}

start_nginx() {
    nginx -g "daemon off;" &
    echo $!
}

reload_nginx() {
    nginx -s reload
}

#######################################
# Certbot
#######################################
request_cert() {
    echo "Requesting Let's Encrypt certificate..."
    certbot certonly \
        --webroot -w "$WEBROOT" \
        -d "$DOMAIN" \
        --email "$SSL_EMAIL" \
        --rsa-key-size 4096 \
        --agree-tos \
        --non-interactive
}

renew_loop() {
    while true; do
        sleep 12h
        certbot renew \
            --webroot -w "$WEBROOT" \
            --quiet \
            --deploy-hook "nginx -s reload"
    done
}

#######################################
# Main
#######################################
main() {
    NGINX_SERVER_NAMES="$(build_domains)"
    export NGINX_SERVER_NAMES

    prepare_dirs
    setup_initial_cert
    render_nginx_conf

    echo "Starting nginx for: $NGINX_SERVER_NAMES"
    NGINX_PID=$(start_nginx)

    if ! has_real_cert; then
        sleep 5
        if request_cert && has_real_cert; then
            echo "Switching to real certificate"
            link_cert "$(certbot_dir)/fullchain.pem" "$(certbot_dir)/privkey.pem"
            reload_nginx
        else
            echo "WARNING: Certbot failed, continuing with dummy cert"
        fi
    fi

    renew_loop &
    wait "$NGINX_PID"
}

main
