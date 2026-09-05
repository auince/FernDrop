#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "$(uname -m)" in arm64) arch=aarch64;; x86_64) arch=x86_64;; *) echo 'Unsupported architecture'; exit 1;; esac
mkdir -p vendor/bin build/downloads
url="https://github.com/n0-computer/sendme/releases/download/v0.36.0/sendme-v0.36.0-darwin-${arch}.tar.gz"
curl --fail --location "$url" -o build/downloads/sendme.tar.gz
tar -xzf build/downloads/sendme.tar.gz -C vendor/bin ./sendme
chmod +x vendor/bin/sendme
vendor/bin/sendme --version
shasum -a 256 vendor/bin/sendme
