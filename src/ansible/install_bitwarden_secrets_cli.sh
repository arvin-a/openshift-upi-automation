#!/bin/bash

set -e

# Download the latest Bitwarden CLI to /tmp
echo "Downloading latest Bitwarden CLI..."
curl -L -o /tmp/bw-linux.zip https://github.com/bitwarden/sdk-sm/releases/download/bws-v1.0.0/bws-x86_64-unknown-linux-gnu-1.0.0.zip

# Unzip if it's zipped
echo "Extracting Bitwarden CLI..."
cd /tmp
unzip -o bw-linux.zip

# Find the binary (it might be in a subdirectory or directly in /tmp)
if [ -f /tmp/bws ]; then
    BW_BINARY=/tmp/bws
elif [ -f /tmp/bws-linux/bws ]; then
    BW_BINARY=/tmp/bws-linux/bws
else
    echo "Error: Could not find bws binary after extraction"
    exit 1
fi

# Make it executable
echo "Making binary executable..."
chmod +x "$BW_BINARY"

# Copy to /usr/bin (requires sudo)
echo "Copying binary to /usr/bin (requires sudo)..."
sudo cp "$BW_BINARY" /usr/bin/bws

# Verify installation
if command -v bws &> /dev/null; then
    echo "Bitwarden CLI installed successfully!"
    bws --version
else
    echo "Error: Installation verification failed"
    exit 1
fi

# Cleanup
echo "Cleaning up temporary files..."
rm -f /tmp/bw-linux.zip
rm -rf /tmp/bw-linux 2>/dev/null || true
rm -f /tmp/bw

echo "Done!"

