#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

function log_info {
    echo -e "${GREEN}[INFO]${NC} $1"
}

function log_warn {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

function log_error {
    echo -e "${RED}[ERROR]${NC} $1"
}

function check_prerequisites {
    log_info "Checking prerequisites..."

    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
        log_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi

    if [[ ! -f "$ENV_FILE" ]]; then
        log_error ".env file not found. Please create it from .env.example first."
        exit 1
    fi

    log_info "All prerequisites met."
}

function load_env {
    log_info "Loading environment variables from .env file..."
    set -a
    source "$ENV_FILE"
    set +a
}

function check_license {
    if [[ -z "${TFE_LICENSE}" ]]; then
        log_error "TFE_LICENSE is not set in .env file. Please add your license."
        exit 1
    fi
    log_info "TFE license found."
}

function docker_login {
    log_info "Authenticating to images.releases.hashicorp.com..."
    echo "${TFE_LICENSE}" | docker login --username terraform images.releases.hashicorp.com --password-stdin

    if [[ $? -eq 0 ]]; then
        log_info "Successfully authenticated to HashiCorp registry."
    else
        log_error "Failed to authenticate to HashiCorp registry."
        exit 1
    fi
}

function list_available_versions {
    log_info "Fetching available TFE versions..."
    local response=$(curl -s https://images.releases.hashicorp.com/v2/hashicorp/terraform-enterprise/tags/list \
        -u terraform:${TFE_LICENSE})

    if [[ -z "$response" ]]; then
        log_error "Failed to fetch TFE versions from registry."
        return 1
    fi

    # Show semantic versions (1.x.x) first, then date-based versions (v202XXX-X)
    echo "Semantic versions:"
    echo "$response" | jq -r '.tags[] | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$"))' | sort -V -r | head -10
    echo ""
    echo "Date-based versions:"
    echo "$response" | jq -r '.tags[] | select(test("^v[0-9]{6}-[0-9]+$"))' | sort -V -r | head -10

    if [[ $? -ne 0 ]]; then
        log_error "Failed to parse TFE versions. Raw response:"
        echo "$response"
        return 1
    fi
}

function pull_tfe_image {
    local VERSION="${1:-${TFE_VERSION:-1.1.2}}"

    log_info "Pulling TFE image: hashicorp/terraform-enterprise:${VERSION}"
    docker pull images.releases.hashicorp.com/hashicorp/terraform-enterprise:${VERSION}

    if [[ $? -eq 0 ]]; then
        log_info "Successfully pulled TFE image."

        # Update TFE_VERSION in .env file if it exists
        if [[ -f "$ENV_FILE" ]]; then
            if grep -q "^TFE_VERSION=" "$ENV_FILE"; then
                # Update existing TFE_VERSION
                if [[ "$(uname)" == "Darwin" ]]; then
                    sed -i '' "s/^TFE_VERSION=.*/TFE_VERSION=${VERSION}/" "$ENV_FILE"
                else
                    sed -i "s/^TFE_VERSION=.*/TFE_VERSION=${VERSION}/" "$ENV_FILE"
                fi
            else
                # Add TFE_VERSION at the beginning of the file
                if [[ "$(uname)" == "Darwin" ]]; then
                    sed -i '' "1s/^/TFE_VERSION=${VERSION}\n\n/" "$ENV_FILE"
                else
                    sed -i "1s/^/TFE_VERSION=${VERSION}\n\n/" "$ENV_FILE"
                fi
            fi
            log_info "Updated TFE_VERSION in .env file to ${VERSION}."
        fi
    else
        log_error "Failed to pull TFE image."
        exit 1
    fi
}

function generate_certificates {
    local CERTS_DIR="$SCRIPT_DIR/certs"
    local CERT_FILE="$CERTS_DIR/tfe.crt"
    local KEY_FILE="$CERTS_DIR/tfe.key"

    log_info "Checking TLS certificates..."

    if [[ -f "$CERT_FILE" ]] && [[ -f "$KEY_FILE" ]]; then
        log_info "TLS certificates already exist. Skipping generation."
        return 0
    fi

    log_info "Generating self-signed TLS certificates..."

    mkdir -p "$CERTS_DIR"

    # Generate self-signed certificate with SAN
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$KEY_FILE" \
        -out "$CERT_FILE" \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=tfe.local" \
        -addext "subjectAltName=DNS:tfe.local,DNS:localhost,IP:127.0.0.1"

    if [[ $? -eq 0 ]]; then
        log_info "Successfully generated TLS certificates."
        log_info "Certificate: $CERT_FILE"
        log_info "Private Key: $KEY_FILE"

        # Set proper permissions on private key
        chmod 600 "$KEY_FILE"
        log_info "Set permissions on private key to 600."
    else
        log_error "Failed to generate TLS certificates."
        exit 1
    fi
}

function install_certificate_to_keychain {
    local CERT_FILE="$SCRIPT_DIR/certs/tfe.crt"

    if [[ ! -f "$CERT_FILE" ]]; then
        log_error "Certificate file not found: $CERT_FILE"
        return 1
    fi

    # Check if running on macOS
    if [[ "$(uname)" != "Darwin" ]]; then
        log_info "Not running on macOS. Skipping keychain installation."
        return 0
    fi

    log_info "Checking if certificate is already in keychain..."

    # Check if certificate is already trusted in System keychain (exact match)
    CERT_CHECK=$(security find-certificate -a /Library/Keychains/System.keychain 2>/dev/null | grep "\"alis\"<blob>=\"tfe.local\"" || echo "")
    if [[ -n "$CERT_CHECK" ]]; then
        log_info "Certificate already exists in System keychain."

        # Verify if it's trusted
        if security dump-trust-settings -d 2>/dev/null | grep -q "tfe.local"; then
            log_info "Certificate is already trusted."
            return 0
        fi
    fi

    log_info "Adding certificate to macOS System keychain..."
    echo ""
    log_warn "This requires administrator privileges (sudo)."
    echo ""

    # Add certificate to System keychain and trust it
    sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CERT_FILE"

    if [[ $? -eq 0 ]]; then
        log_info "Successfully added and trusted certificate in System keychain."
        log_info "You may need to restart your browser for the changes to take effect."
    else
        log_error "Failed to add certificate to keychain."
        log_warn "You can manually add it later with:"
        echo "  sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain $CERT_FILE"
        return 1
    fi
}

function setup_hosts_file {
    log_info "Checking /etc/hosts configuration..."

    if grep -q "tfe.local" /etc/hosts; then
        log_info "/etc/hosts already contains tfe.local entry."
        return 0
    fi

    log_info "Adding tfe.local to /etc/hosts..."
    echo ""
    log_warn "This requires administrator privileges (sudo)."
    echo ""

    sudo sh -c 'echo "127.0.0.1 tfe.local" >> /etc/hosts'

    if [[ $? -eq 0 ]]; then
        log_info "Successfully added tfe.local to /etc/hosts."
    else
        log_error "Failed to add tfe.local to /etc/hosts."
        log_warn "You can manually add it later with:"
        echo "  sudo sh -c 'echo \"127.0.0.1 tfe.local\" >> /etc/hosts'"
        return 1
    fi
}

function main {
    echo "=================================================="
    echo "  Terraform Enterprise Setup Script"
    echo "=================================================="
    echo ""

    check_prerequisites
    load_env
    check_license
    docker_login

    echo ""
    log_info "Top 10 available TFE versions:"
    list_available_versions
    echo ""

    # Use TFE_VERSION from .env if available, otherwise prompt
    local DEFAULT_VERSION="${TFE_VERSION:-1.1.2}"
    read -p "Enter TFE version to use (default: ${DEFAULT_VERSION}): " USER_VERSION
    USER_VERSION=${USER_VERSION:-${DEFAULT_VERSION}}

    pull_tfe_image "${USER_VERSION}"
    generate_certificates
    install_certificate_to_keychain
    setup_hosts_file

    echo ""
    log_info "Setup completed successfully!"
    echo ""
    log_info "Next steps:"
    echo "  1. Ensure /etc/hosts contains: 127.0.0.1 tfe.local"
    echo "  2. Update docker-compose.yml image tag to: ${TFE_VERSION}"
    echo "  3. Start services: docker-compose up -d"
    echo "  4. View logs: docker-compose logs -f"
    echo "  5. Get IACT token: docker exec tfe tfectl admin token"
    echo "  6. Access TFE at: https://tfe.local"
    echo ""
}

main "$@"
