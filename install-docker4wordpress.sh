#!/usr/bin/env bash
#
# Docker4WordPress installer for Ubuntu
# - Detects the latest stable GitHub release (minimum 6.2.9)
# - Installs Docker Engine + Compose plugin if not already available
# - Clones the selected release
# - Generates strong MariaDB credentials
# - Configures the project domain and starts the stack
# - Configures Traefik + Let's Encrypt HTTPS on ports 80/443
# - Redirects HTTP to HTTPS and keeps ACME certificates persistent
#
# Usage:
#   chmod +x install-docker4wordpress.sh
#   sudo ./install-docker4wordpress.sh wp.example.com
#   The installer will ask for the Let's Encrypt notification email.
#   Point the domain's A record to this server and allow inbound TCP 80/443.
#
# Optional:
#   INSTALL_DIR=/opt/docker4wordpress ./install-docker4wordpress.sh wp.example.com
#
set -Eeuo pipefail
IFS=$'\n\t'

readonly REPO="https://github.com/wodby/docker4wordpress.git"
readonly API_URL="https://api.github.com/repos/wodby/docker4wordpress/releases/latest"
readonly MIN_VERSION="6.2.9"
readonly DEFAULT_INSTALL_DIR="/opt/docker4wordpress"
readonly HTTP_PORT="80"
readonly HTTPS_PORT="443"

INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
DOMAIN="${1:-}"

log()  { printf '\033[1;32m[INFO]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

trap 'rc=$?; echo; echo "[ERROR] Script failed at line ${LINENO} (exit ${rc})." >&2; exit "$rc"' ERR

[[ $EUID -eq 0 ]] || die "Run this script as root: sudo $0 wp.example.com"

if [[ -z "$DOMAIN" ]]; then
  read -r -p "Enter WordPress domain (e.g. wp.example.com): " DOMAIN
fi
[[ -n "$DOMAIN" ]] || die "Domain/IP cannot be empty."
DOMAIN="${DOMAIN#http://}"
DOMAIN="${DOMAIN#https://}"
DOMAIN="${DOMAIN%%/*}"
[[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || die "Invalid domain/IP: $DOMAIN"

command -v apt-get >/dev/null 2>&1 || die "This installer supports Ubuntu with apt only."
[[ -r /etc/os-release ]] || die "Cannot detect operating system."
# shellcheck disable=SC1091
source /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || die "Ubuntu is required. Detected: ${PRETTY_NAME:-unknown}"

ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
  amd64|arm64) ;;
  *) die "Unsupported architecture: $ARCH (supported: amd64, arm64)" ;;
esac

if [[ -e "$INSTALL_DIR" ]]; then
  die "$INSTALL_DIR already exists. Move/backup it first; refusing to overwrite existing data."
fi

for port in "$HTTP_PORT" "$HTTPS_PORT"; do
  if ss -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]${port}$"; then
    die "TCP port ${port} is already in use. Stop the conflicting service before continuing."
  fi
done

LE_EMAIL="${LE_EMAIL:-}"
if [[ -z "$LE_EMAIL" ]]; then
  read -r -p "Let's Encrypt notification email: " LE_EMAIL
fi
[[ "$LE_EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] || die "A valid Let's Encrypt email address is required."

log "Installing required system packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y ca-certificates curl git openssl python3

install_docker() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    log "Docker Engine and Docker Compose plugin are already installed."
    return
  fi

  # Avoid silently replacing an existing Ubuntu/Debian Docker installation.
  for pkg in docker.io docker-compose docker-compose-v2 podman-docker; do
    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
      die "Conflicting package '$pkg' is installed. Resolve/remove it manually, then rerun this installer."
    fi
  done

  log "Adding the official Docker APT repository..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${VERSION_CODENAME}
Components: stable
Architectures: ${ARCH}
Signed-By: /etc/apt/keyrings/docker.asc
EOF

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

  systemctl enable --now docker
  docker compose version >/dev/null
}

install_docker
systemctl enable --now docker

log "Detecting latest stable Docker4WordPress release from GitHub..."
RELEASE_JSON="$(curl -fsSL --retry 3 --retry-delay 2 \
  -H 'Accept: application/vnd.github+json' \
  -H 'X-GitHub-Api-Version: 2022-11-28' "$API_URL")"

VERSION="$(printf '%s' "$RELEASE_JSON" | python3 -c '
import json,sys
obj=json.load(sys.stdin)
if obj.get("draft") or obj.get("prerelease"):
    raise SystemExit("Latest GitHub release is not stable")
print(obj.get("tag_name",""))
')"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Could not determine a valid stable release tag."
LOWEST="$(printf '%s\n%s\n' "$MIN_VERSION" "$VERSION" | sort -V | head -n1)"
[[ "$LOWEST" == "$MIN_VERSION" ]] || die "Latest release $VERSION is older than required minimum $MIN_VERSION."

log "Latest stable release: $VERSION (minimum allowed: $MIN_VERSION)"
log "Cloning repository..."
install -d -m 0755 "$(dirname "$INSTALL_DIR")"
git clone --depth 1 --branch "$VERSION" "$REPO" "$INSTALL_DIR"
cd "$INSTALL_DIR"

[[ -f .env && -f compose.yml && -f compose.override.yml ]] || \
  die "Expected project files are missing in release $VERSION."

log "Applying server-safe Compose adjustments..."
mkdir -p data/mariadb data/traefik
install -m 0600 /dev/null data/traefik/acme.json
python3 - "$LE_EMAIL" <<'PYCOMPOSE'
from pathlib import Path
import re
import sys

email = sys.argv[1]
path = Path("compose.yml")
s = path.read_text()

# Persist MariaDB outside the container writable layer.
needle = "      MYSQL_PASSWORD: $DB_PASSWORD\n"
if "./data/mariadb:/var/lib/mysql" not in s:
    if s.count(needle) != 1:
        raise SystemExit("Could not safely locate MariaDB MYSQL_PASSWORD entry")
    s = s.replace(needle, needle + "    volumes:\n      - ./data/mariadb:/var/lib/mysql\n", 1)

# Configure Traefik HTTPS + Let's Encrypt HTTP-01. No insecure dashboard.
block = re.search(r"(?ms)^  traefik:\n(.*?)(?=^  [A-Za-z0-9_-]+:\n|\Z)", s)
if not block:
    raise SystemExit("Could not locate Traefik service")
cmd = re.search(r"(?m)^    command:.*$", block.group(1))
if not cmd:
    raise SystemExit("Could not locate Traefik command")
abs_start = block.start(1) + cmd.start()
abs_end = block.start(1) + cmd.end()
new_cmd = """    command:
    - --providers.docker=true
    - --providers.docker.exposedbydefault=false
    - --entrypoints.web.address=:80
    - --entrypoints.web.http.redirections.entrypoint.to=websecure
    - --entrypoints.web.http.redirections.entrypoint.scheme=https
    - --entrypoints.websecure.address=:443
    - --certificatesresolvers.le.acme.email=""" + email + """
    - --certificatesresolvers.le.acme.storage=/letsencrypt/acme.json
    - --certificatesresolvers.le.acme.httpchallenge.entrypoint=web"""
s = s[:abs_start] + new_cmd + s[abs_end:]

# Replace the upstream development-only 8000 mapping with public HTTP/HTTPS.
ports_old = """    ports:
    - '8000:80'
#    - '8080:8080' # Dashboard
    volumes:
    - /var/run/docker.sock:/var/run/docker.sock"""
ports_new = """    ports:
    - '80:80'
    - '443:443'
    volumes:
    - /var/run/docker.sock:/var/run/docker.sock
    - ./data/traefik/acme.json:/letsencrypt/acme.json"""
if s.count(ports_old) != 1:
    raise SystemExit("Could not safely locate Traefik published ports/volumes block")
s = s.replace(ports_old, ports_new, 1)

# Enable only the WordPress Nginx router; development Mailpit stays private.
nginx_rule = '    - "traefik.http.routers.${PROJECT_NAME}_nginx.rule=Host(`${PROJECT_BASE_URL}`)"'
if s.count(nginx_rule) != 1:
    raise SystemExit("Could not safely locate Nginx Traefik Host rule")
nginx_labels = nginx_rule + "\n" + "\n".join([
    '    - "traefik.enable=true"',
    '    - "traefik.http.routers.${PROJECT_NAME}_nginx.entrypoints=websecure"',
    '    - "traefik.http.routers.${PROJECT_NAME}_nginx.tls=true"',
    '    - "traefik.http.routers.${PROJECT_NAME}_nginx.tls.certresolver=le"',
    '    - "traefik.http.services.${PROJECT_NAME}_nginx.loadbalancer.server.port=80"',
])
s = s.replace(nginx_rule, nginx_labels, 1)

# Ensure enabled services restart after host reboot / Docker restart.
for service in ("mariadb", "php", "crond", "nginx", "mailpit", "traefik"):
    pattern = rf"(?ms)^(  {service}:\n)(.*?)(?=^  [A-Za-z0-9_-]+:\n|\Z)"
    match = re.search(pattern, s)
    if not match:
        raise SystemExit(f"Could not find expected Compose service: {service}")
    block = match.group(2)
    if not re.search(r"(?m)^    restart:", block):
        if re.search(r"(?m)^    container_name:", block):
            block = re.sub(r"(?m)^(    container_name:.*)$", r"\1\n    restart: unless-stopped", block, count=1)
        else:
            block = "    restart: unless-stopped\n" + block
        s = s[:match.start(2)] + block + s[match.end(2):]

path.write_text(s)
PYCOMPOSE

DB_PASSWORD="$(openssl rand -hex 32)"
DB_ROOT_PASSWORD="$(openssl rand -hex 40)"

log "Configuring domain and database credentials..."
python3 - "$DOMAIN" "$DB_PASSWORD" "$DB_ROOT_PASSWORD" <<'PY'
from pathlib import Path
import sys

domain, db_password, root_password = sys.argv[1:]
path = Path(".env")
lines = path.read_text().splitlines()
updates = {
    "PROJECT_BASE_URL": domain,
    "DB_PASSWORD": db_password,
    "DB_ROOT_PASSWORD": root_password,
}
seen = set()
out = []
for line in lines:
    stripped = line.strip()
    if not stripped or stripped.startswith("#") or "=" not in line:
        out.append(line)
        continue
    key = line.split("=", 1)[0].strip()
    if key in updates:
        out.append(f"{key}={updates[key]}")
        seen.add(key)
    else:
        out.append(line)

missing = set(updates) - seen
if missing:
    raise SystemExit("Required .env variables not found: " + ", ".join(sorted(missing)))
path.write_text("\n".join(out) + "\n")
PY
# Generate unique WordPress authentication keys/salts when the upstream .env leaves them blank.
python3 - <<'PYSALTS'
from pathlib import Path
import secrets
p = Path(".env")
keys = ("WP_AUTH_KEY", "WP_SECURE_AUTH_KEY", "WP_LOGGED_IN_KEY", "WP_NONCE_KEY",
        "WP_AUTH_SALT", "WP_SECURE_AUTH_SALT", "WP_LOGGED_IN_SALT", "WP_NONCE_SALT")
lines = p.read_text().splitlines()
seen = set()
out = []
for line in lines:
    if "=" in line and not line.lstrip().startswith("#"):
        key = line.split("=", 1)[0].strip()
        if key in keys:
            value = line.split("=", 1)[1]
            if not value.strip():
                value = secrets.token_urlsafe(48)
            out.append(f"{key}={value}")
            seen.add(key)
            continue
    out.append(line)
missing = set(keys) - seen
if missing:
    raise SystemExit("Missing WordPress salt variables in .env: " + ", ".join(sorted(missing)))
p.write_text("\n".join(out) + "\n")
PYSALTS
chmod 600 .env

cat > /root/docker4wordpress-credentials.txt <<EOF
Docker4WordPress release: ${VERSION}
Project domain: ${DOMAIN}
WordPress URL: https://${DOMAIN}/
Let's Encrypt email: ${LE_EMAIL}
Database name: wordpress
Database user: wordpress
Database password: ${DB_PASSWORD}
Database root password: ${DB_ROOT_PASSWORD}
EOF
chmod 600 /root/docker4wordpress-credentials.txt

log "Validating Docker Compose configuration..."
docker compose config --quiet

log "Pulling images (this may take several minutes)..."
docker compose pull

log "Opening firewall ports 80/tcp and 443/tcp when UFW is active..."
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow 80/tcp >/dev/null || warn "Could not add UFW rule for 80/tcp."
  ufw allow 443/tcp >/dev/null || warn "Could not add UFW rule for 443/tcp."
fi

log "Starting Docker4WordPress with HTTPS..."
docker compose up -d

log "Waiting for a trusted Let's Encrypt certificate (up to 5 minutes)..."
READY=0
CERT_READY=0
for attempt in $(seq 1 100); do
  CODE="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 \
    "https://${DOMAIN}/" 2>/dev/null || true)"
  if [[ "$CODE" =~ ^[1-5][0-9][0-9]$ ]]; then
    READY=1
    CERT_READY=1
    break
  fi
  # A TLS handshake may succeed before WordPress returns its final response.
  if [[ "$CODE" =~ ^(200|301|302|403|404)$ ]]; then
    READY=1
  fi
  sleep 3
done

echo
docker compose ps
echo

if [[ "$CERT_READY" -ne 1 ]]; then
  warn "A trusted HTTPS response was not confirmed within 5 minutes."
  warn "Check that DNS A for ${DOMAIN} points to this server and inbound TCP 80/443 are allowed by the provider firewall."
  warn "Traefik logs: cd '${INSTALL_DIR}' && docker compose logs --tail=200 traefik"
  die "Containers are running, but Let's Encrypt certificate validation did not complete."
fi

# If WordPress was already installed during a rerun, normalize its canonical URLs.
if docker compose exec -T php wp core is-installed --allow-root >/dev/null 2>&1; then
  docker compose exec -T php wp option update home "https://${DOMAIN}" --allow-root >/dev/null
  docker compose exec -T php wp option update siteurl "https://${DOMAIN}" --allow-root >/dev/null
  docker compose exec -T php wp cache flush --allow-root >/dev/null || true
fi

log "Installation completed with a trusted HTTPS certificate."
echo "Release:       ${VERSION}"
echo "Project path:  ${INSTALL_DIR}"
echo "WordPress URL: https://${DOMAIN}/"
echo "Admin URL:     https://${DOMAIN}/wp-admin/"
echo "Let's Encrypt: ${LE_EMAIL}"
echo "Credentials:   /root/docker4wordpress-credentials.txt"
echo
log "HTTPS endpoint responded with status ${CODE}."
warn "Ensure your provider firewall allows inbound TCP 80 and 443. Mailpit is intentionally not exposed publicly."
warn "This upstream project is primarily designed for development; review optional services and implement off-server backups before production use."
warn "Do not run 'docker compose down -v' unless you intentionally want to delete data."
