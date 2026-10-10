#!/usr/bin/env bash
# One-time setup for hosting the CV site on an Ubuntu VPS that runs Apache
# behind Cloudflare, next to other services.
#
# What it does (and nothing else):
#   - creates a dedicated deploy user whose SSH key can ONLY rsync into the web root
#   - creates the web root
#   - adds ONE new Apache virtual host for $DOMAIN
#   - validates the whole Apache config before a graceful reload
#
# It never edits existing vhosts, ports, firewall or sshd settings, and it
# refuses to continue if Apache is not the service listening on port 80.
#
# Usage:
#   sudo bash server-setup.sh
#
# Optional environment variables:
#   DOMAIN=cv.u-network-it.com
#   DEPLOY_USER=cvdeploy
#   WEB_ROOT=/var/www/cv.u-network-it.com
#   SSL_CERT=/path/cert.pem SSL_KEY=/path/key.pem  # use this cert for the :443 vhost
#   ROTATE_KEY=1                                     # issue a new deploy key on re-runs

set -euo pipefail

DOMAIN="${DOMAIN:-cv.u-network-it.com}"
DEPLOY_USER="${DEPLOY_USER:-cvdeploy}"
WEB_ROOT="${WEB_ROOT:-/var/www/$DOMAIN}"
SSL_CERT="${SSL_CERT:-}"
SSL_KEY="${SSL_KEY:-}"
ROTATE_KEY="${ROTATE_KEY:-0}"

# "zz-" makes this vhost load last, so it never becomes Apache's default
# site for requests that match no ServerName (which could affect other sites).
SITE_NAME="zz-$DOMAIN"
SITE_CONF="/etc/apache2/sites-available/$SITE_NAME.conf"
SELF_SIGNED_DIR="/etc/ssl/cv-site"
HOST_KEY_ALIAS="cv-server"   # must match HostKeyAlias in .github/workflows/deploy.yml

PRIVATE_KEY=""
key_shown=0
tmp=""
on_exit() {
  [ -z "$tmp" ] || rm -rf "$tmp"
  if [ -n "$PRIVATE_KEY" ] && [ "$key_shown" = "0" ]; then
    printf '\nThe script stopped early, but a new deploy key was already installed.\n' >&2
    printf 'Save it as the SSH_PRIVATE_KEY secret:\n\n%s\n\n' "$PRIVATE_KEY" >&2
  fi
}
trap on_exit EXIT

info() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARNING:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- preflight
[ "$(id -u)" -eq 0 ] || die "Run as root: sudo bash $0"
command -v apache2ctl >/dev/null || die "apache2ctl not found. This script expects Apache installed on the host (not in Docker)."
command -v openssl >/dev/null || die "openssl not found."
command -v ss >/dev/null || die "ss (iproute2) not found."

info "Checking the current Apache config is valid before changing anything"
apache2ctl configtest >/dev/null 2>&1 || die "Apache config is already failing 'apache2ctl configtest'. Fix that first; nothing was changed."

port_owner() {
  ss -Hltnp "sport = :$1" 2>/dev/null | grep -o 'users:(("[^"]*' | head -n1 | cut -d'"' -f2 || true
}

owner80="$(port_owner 80)"
[ "$owner80" = "apache2" ] || die "Port 80 is served by '${owner80:-nothing}', not Apache. Nothing was changed."

owner443="$(port_owner 443)"
use_443=0
if [ "$owner443" = "apache2" ] && a2query -q -m ssl 2>/dev/null; then
  use_443=1
elif [ -n "$owner443" ]; then
  warn "Port 443 is served by '$owner443', not Apache. Only a port-80 vhost will be added."
fi

existing="$(apache2ctl -S 2>/dev/null \
  | awk -v d="$DOMAIN" '($3=="namevhost" && $4==d) || ($1=="alias" && $2==d) || ($1 ~ /:[0-9]+$/ && $2==d)' \
  | grep -vF "/$SITE_NAME.conf:" || true)"
[ -z "$existing" ] || die "Another Apache vhost already serves $DOMAIN:
$existing
Nothing was changed."

# A wildcard vhost loaded earlier (e.g. ServerAlias *.u-network-it.com) would
# answer for $DOMAIN instead of this site.
wildcard_warning=""
while read -r pat; do
  [ -n "$pat" ] || continue
  # shellcheck disable=SC2053
  if [[ "$DOMAIN" == $pat ]]; then
    wildcard_warning="Another site's vhost answers for '$pat', which also matches $DOMAIN. Apache uses the first match, so that site will show instead of the CV until its ServerAlias is narrowed."
    warn "$wildcard_warning"
  fi
done < <(apache2ctl -S 2>/dev/null | awk '($1=="alias"){print $2} ($1=="wild" && $2=="alias"){print $3} ($3=="namevhost"){print $4}' | grep -F '*' | sort -u || true)

# ---------------------------------------------------------------- packages
if ! command -v rsync >/dev/null; then
  info "Installing rsync"
  apt-get install -y rsync >/dev/null
fi

RRSYNC=""
if command -v rrsync >/dev/null; then
  RRSYNC="$(command -v rrsync)"
elif [ -f /usr/share/doc/rsync/scripts/rrsync.gz ]; then
  gunzip -c /usr/share/doc/rsync/scripts/rrsync.gz > /usr/local/bin/rrsync
  chmod 755 /usr/local/bin/rrsync
  RRSYNC=/usr/local/bin/rrsync
else
  warn "rrsync not found; the deploy key will be limited by 'restrict' only, not to the web root."
fi

# ---------------------------------------------------------------- deploy user + web root
if id -u "$DEPLOY_USER" >/dev/null 2>&1; then
  info "Deploy user '$DEPLOY_USER' already exists"
else
  info "Creating deploy user '$DEPLOY_USER' (no password, no sudo)"
  useradd --create-home --shell /bin/bash "$DEPLOY_USER"
fi

info "Preparing web root $WEB_ROOT"
install -d -o "$DEPLOY_USER" -g "$DEPLOY_USER" -m 755 "$WEB_ROOT"
if [ -z "$(ls -A "$WEB_ROOT")" ]; then
  cat > "$WEB_ROOT/index.html" <<'HTML'
<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>Deploying soon</title></head>
<body style="font-family:system-ui;padding:40px">Site is set up. Waiting for the first deploy from GitHub Actions.</body></html>
HTML
  chown "$DEPLOY_USER:$DEPLOY_USER" "$WEB_ROOT/index.html"
fi

# ---------------------------------------------------------------- deploy SSH key
SSH_DIR="$(getent passwd "$DEPLOY_USER" | cut -d: -f6)/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

if [ -s "$AUTH_KEYS" ] && [ "$ROTATE_KEY" != "1" ]; then
  info "Deploy key already installed (re-run with ROTATE_KEY=1 to issue a new one)"
else
  info "Generating a new deploy key"
  tmp="$(mktemp -d)"
  ssh-keygen -q -t ed25519 -N "" -C "github-actions-deploy@$DOMAIN" -f "$tmp/key"
  if [ -n "$RRSYNC" ]; then
    opts="command=\"$RRSYNC -wo $WEB_ROOT\",restrict"
  else
    opts="restrict"
  fi
  install -d -o "$DEPLOY_USER" -g "$DEPLOY_USER" -m 700 "$SSH_DIR"
  printf '%s %s\n' "$opts" "$(cat "$tmp/key.pub")" > "$AUTH_KEYS"
  chown "$DEPLOY_USER:$DEPLOY_USER" "$AUTH_KEYS"
  chmod 600 "$AUTH_KEYS"
  PRIVATE_KEY="$(cat "$tmp/key")"
fi

# ---------------------------------------------------------------- TLS for :443
cert_covers_domain() {
  local sans parent="${DOMAIN#*.}"
  openssl x509 -in "$1" -noout -checkend 86400 >/dev/null 2>&1 || return 1
  sans="$(openssl x509 -in "$1" -noout -ext subjectAltName 2>/dev/null | tr ',' '\n' | sed -n 's/^ *DNS://p')"
  grep -qxF -e "$DOMAIN" -e "*.$parent" <<<"$sans"
}

key_matches_cert() {
  local a b
  a="$(openssl x509 -in "$1" -noout -pubkey 2>/dev/null)" || return 1
  b="$(openssl pkey -in "$2" -pubout 2>/dev/null)" || return 1
  [ -n "$a" ] && [ "$a" = "$b" ]
}

find_existing_cert() {
  local files=() f cert key
  for f in /etc/apache2/sites-enabled/*; do
    [ -f "$f" ] && [ "$(readlink -f "$f")" != "$SITE_CONF" ] && files+=("$f")
  done
  [ "${#files[@]}" -gt 0 ] || return 1
  local certs keys
  certs="$(grep -hiE '^\s*SSLCertificateFile\s' "${files[@]}" 2>/dev/null | awk '{print $2}' | tr -d '"' | sort -u || true)"
  keys="$(grep -hiE '^\s*SSLCertificateKeyFile\s' "${files[@]}" 2>/dev/null | awk '{print $2}' | tr -d '"' | sort -u || true)"
  for cert in $certs; do
    if [ ! -r "$cert" ] || ! cert_covers_domain "$cert"; then continue; fi
    for key in $keys; do
      [ -r "$key" ] && key_matches_cert "$cert" "$key" && { printf '%s %s\n' "$cert" "$key"; return 0; }
    done
  done
  return 1
}

tls_note=""
if [ "$use_443" = "1" ]; then
  if [ -n "$SSL_CERT" ] || [ -n "$SSL_KEY" ]; then
    if [ ! -r "$SSL_CERT" ] || [ ! -r "$SSL_KEY" ]; then
      die "SSL_CERT/SSL_KEY must both point to readable files."
    fi
    key_matches_cert "$SSL_CERT" "$SSL_KEY" || die "SSL_KEY does not match SSL_CERT."
    tls_note="Using the certificate you provided: $SSL_CERT"
  elif found="$(find_existing_cert)"; then
    SSL_CERT="${found% *}"
    SSL_KEY="${found#* }"
    tls_note="Reusing an existing certificate that covers $DOMAIN: $SSL_CERT"
  else
    install -d -m 755 "$SELF_SIGNED_DIR"
    SSL_CERT="$SELF_SIGNED_DIR/$DOMAIN.crt"
    SSL_KEY="$SELF_SIGNED_DIR/$DOMAIN.key"
    if [ ! -s "$SSL_CERT" ]; then
      openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=$DOMAIN" \
        -addext "subjectAltName=DNS:$DOMAIN" -addext "basicConstraints=critical,CA:FALSE" -keyout "$SSL_KEY" -out "$SSL_CERT" >/dev/null 2>&1
      chmod 600 "$SSL_KEY"
    fi
    tls_note="No certificate for $DOMAIN found; using a self-signed one. This works with Cloudflare SSL mode 'Full'. For 'Full (strict)', create a Cloudflare Origin Certificate and re-run with SSL_CERT=... SSL_KEY=..."
  fi
  info "$tls_note"
fi

# ---------------------------------------------------------------- Apache vhost
site_body() {
  cat <<EOF
    ServerName $DOMAIN
    DocumentRoot $WEB_ROOT

    <Directory $WEB_ROOT>
        Options -Indexes
        AllowOverride None
        Require all granted
    </Directory>
    DirectoryIndex index.html

    <IfModule mod_headers.c>
        Header always set X-Content-Type-Options "nosniff"
        Header always set X-Frame-Options "SAMEORIGIN"
        Header always set Referrer-Policy "strict-origin-when-cross-origin"
        Header always set Permissions-Policy "camera=(), microphone=(), geolocation=()"
        # Asset URLs carry ?v=<commit>, so they can be cached for a week.
        <FilesMatch "\.(css|js|svg|jpg|jpeg|png|webp|pdf)$">
            Header set Cache-Control "public, max-age=604800"
        </FilesMatch>
        <FilesMatch "\.html$">
            Header set Cache-Control "no-cache"
        </FilesMatch>
    </IfModule>

    <IfModule mod_deflate.c>
        AddOutputFilterByType DEFLATE text/html text/css application/javascript image/svg+xml
    </IfModule>

    ErrorLog \${APACHE_LOG_DIR}/cv-site-error.log
    CustomLog \${APACHE_LOG_DIR}/cv-site-access.log combined
EOF
}

info "Writing $SITE_CONF"
{
  echo "# CV site, created by deploy/server-setup.sh"
  echo "# Remove with: a2dissite $SITE_NAME && systemctl reload apache2"
  echo "<VirtualHost *:80>"
  site_body
  echo "</VirtualHost>"
  if [ "$use_443" = "1" ]; then
    echo
    echo "<VirtualHost *:443>"
    site_body
    echo
    echo "    SSLEngine on"
    echo "    SSLCertificateFile $SSL_CERT"
    echo "    SSLCertificateKeyFile $SSL_KEY"
    echo "</VirtualHost>"
  fi
} > "$SITE_CONF.new"
mv "$SITE_CONF.new" "$SITE_CONF"

enabled_headers=0
if ! a2query -q -m headers 2>/dev/null; then
  a2enmod -q headers >/dev/null
  enabled_headers=1
fi
a2ensite -q "$SITE_NAME" >/dev/null

info "Validating Apache config"
if ! apache2ctl configtest >/dev/null 2>&1; then
  apache2ctl configtest || true
  a2dissite -q "$SITE_NAME" >/dev/null || true
  rm -f "$SITE_CONF"
  if [ "$enabled_headers" = "1" ]; then a2dismod -q headers >/dev/null || true; fi
  die "Apache rejected the new config. It was removed again and Apache was NOT reloaded."
fi

info "Reloading Apache gracefully (other sites keep running)"
if command -v systemctl >/dev/null && systemctl is-active --quiet apache2 2>/dev/null; then
  systemctl reload apache2
else
  apache2ctl graceful
fi

# ---------------------------------------------------------------- summary
# 'sshd -T' fails on some systems (e.g. socket-activated ssh without /run/sshd),
# so fall back to reading the config files directly.
sshd_settings() {
  if sshd -T 2>/dev/null; then return 0; fi
  cat /etc/ssh/sshd_config.d/*.conf /etc/ssh/sshd_config 2>/dev/null \
    | sed -E 's/#.*//; s/^[[:space:]]+//' \
    | awk 'NF { $1 = tolower($1); print }'
}
sshd_conf="$(sshd_settings || true)"
ssh_port="$(awk '$1=="port"{print $2; exit}' <<<"$sshd_conf")"
host_key=""
for t in ed25519 ecdsa rsa; do
  if [ -r "/etc/ssh/ssh_host_${t}_key.pub" ]; then
    host_key="$(awk '{print $1" "$2}' "/etc/ssh/ssh_host_${t}_key.pub")"
    break
  fi
done
ip_guess="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"

allow="$(grep -iE '^(allowusers|allowgroups) ' <<<"$sshd_conf" || true)"
if [ -n "$allow" ] && ! grep -qw "$DEPLOY_USER" <<<"$allow"; then
  warn "sshd limits logins ($(tr '\n' ' ' <<<"$allow")). Add '$DEPLOY_USER' there or deploys will be refused."
fi

cat <<EOF

=====================================================================
 Server is ready for $DOMAIN
=====================================================================
 Web root : $WEB_ROOT
 Vhost    : $SITE_CONF ($( [ "$use_443" = "1" ] && echo "ports 80 + 443" || echo "port 80 only" ))

 Add these as GitHub repository secrets
 (Settings -> Secrets and variables -> Actions -> New repository secret):

   SSH_HOST         ${ip_guess:-<your server public IP>}   (the server IP, NOT the Cloudflare domain)
   SSH_PORT         ${ssh_port:-22}
   SSH_USER         $DEPLOY_USER
   SSH_KNOWN_HOSTS  $HOST_KEY_ALIAS $host_key
EOF

if [ -n "$PRIVATE_KEY" ]; then
  cat <<EOF
   SSH_PRIVATE_KEY  everything between the lines below, including BEGIN/END:

$PRIVATE_KEY

 This private key is shown once and not stored on the server.
 It can only upload files into $WEB_ROOT.
EOF
  key_shown=1
else
  echo "   SSH_PRIVATE_KEY  (unchanged; use ROTATE_KEY=1 to get a new one)"
fi

if [ -n "$wildcard_warning" ]; then
  echo
  echo " WARNING: $wildcard_warning"
fi

if [ "$use_443" != "1" ]; then
  cat <<EOF

 Note: only a port-80 vhost was added, so set Cloudflare SSL/TLS mode
 for this hostname to 'Flexible', or enable HTTPS in Apache and re-run.
EOF
fi
echo "====================================================================="
