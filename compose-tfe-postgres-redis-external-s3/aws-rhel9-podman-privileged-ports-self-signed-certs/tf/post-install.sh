#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=================================================="
echo "  TFE Post-Install Configuration"
echo "=================================================="
echo ""

# Get values from Terraform output
EIP=$(terraform output -raw tfe_eip)
HOSTNAME=$(terraform output -raw tfe_hostname)
CERT_FILE="$SCRIPT_DIR/certs/tfe.crt"

echo "EIP: $EIP"
echo "Hostname: $HOSTNAME"
echo "Certificate: $CERT_FILE"
echo ""

# Check if /etc/hosts already contains the entry
if grep -q "$HOSTNAME" /etc/hosts; then
    echo "[INFO] /etc/hosts already contains $HOSTNAME entry."
    echo "[INFO] Current entry:"
    grep "$HOSTNAME" /etc/hosts
    echo ""
    read -p "Do you want to update it? (y/N): " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "[INFO] Removing old entry..."
        sudo sed -i.bak "/$HOSTNAME/d" /etc/hosts
    else
        echo "[INFO] Skipping /etc/hosts update."
    fi
fi

# Add to /etc/hosts if not present
if ! grep -q "$HOSTNAME" /etc/hosts; then
    echo "[INFO] Adding $HOSTNAME to /etc/hosts..."
    echo "$EIP $HOSTNAME" | sudo tee -a /etc/hosts > /dev/null
    echo "[SUCCESS] Added: $EIP $HOSTNAME"
fi

echo ""
echo "[INFO] Installing TLS certificate to system trust store..."

# Detect OS and install certificate
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    echo "[INFO] Detected macOS"

    # Check if certificate is already in keychain (exact match)
    CERT_CHECK=$(security find-certificate -a /Library/Keychains/System.keychain 2>/dev/null | grep "\"alis\"<blob>=\"$HOSTNAME\"" || echo "")
    if [[ -n "$CERT_CHECK" ]]; then
        echo "[INFO] Certificate already exists in System keychain."
        read -p "Do you want to reinstall it? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "[INFO] Removing old certificate..."
            sudo security delete-certificate -c "$HOSTNAME" /Library/Keychains/System.keychain 2>/dev/null || true
        else
            echo "[INFO] Skipping certificate installation."
            echo ""
            echo "[SUCCESS] Setup complete!"
            echo "Access TFE at: https://$HOSTNAME"
            exit 0
        fi
    fi

    echo "[INFO] Adding certificate to System keychain (requires sudo)..."
    sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CERT_FILE"
    echo "[SUCCESS] Certificate installed successfully!"
    echo "[INFO] You may need to restart your browser."

elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    echo "[INFO] Detected Linux"

    if [[ -f /etc/debian_version ]]; then
        # Debian/Ubuntu
        sudo cp "$CERT_FILE" /usr/local/share/ca-certificates/tfe.crt
        sudo update-ca-certificates
    elif [[ -f /etc/redhat-release ]]; then
        # RHEL/CentOS/Fedora
        sudo cp "$CERT_FILE" /etc/pki/ca-trust/source/anchors/tfe.crt
        sudo update-ca-trust
    else
        echo "[WARN] Unknown Linux distribution. Please manually install the certificate:"
        echo "       $CERT_FILE"
    fi
    echo "[SUCCESS] Certificate installed successfully!"

else
    echo "[WARN] Unknown OS. Please manually install the certificate:"
    echo "       $CERT_FILE"
    echo ""
    echo "And add this to /etc/hosts:"
    echo "       $EIP $HOSTNAME"
fi

echo ""
echo "=================================================="
echo "[SUCCESS] Setup complete!"
echo "=================================================="
echo ""
echo "Access TFE at: https://$HOSTNAME"
echo ""
echo "To get IACT token, connect to EC2 and run:"
echo "  sudo docker exec tfe tfectl admin token"
echo ""
