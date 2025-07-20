#!/usr/bin/env bash

set -euo pipefail

OUTPUT_DIR="./prismlinux/out"

if [[ $(podman info --format '{{.Host.Security.Rootless}}') == "true" ]]; then
  echo "❌ ERROR: This script must run as root for loop device + mount support."
  echo "✅ Run: sudo ./build.sh"
  exit 1
fi

echo "🚀 Starting archiso build with auto-build container..."

podman-compose up --build

if [ -d "$OUTPUT_DIR" ] && [ "$(ls -A $OUTPUT_DIR 2>/dev/null)" ]; then
  echo "✅ Build completed successfully!"
  echo "📦 Final ISO files:"
  ls -lh "$OUTPUT_DIR"/*.iso 2>/dev/null || echo "No ISO files found"
  
  for iso in "$OUTPUT_DIR"/*.iso; do
    if [ -f "$iso" ]; then
      echo "🎯 Ready to use: $(realpath "$iso")"
    fi
  done
else
  echo "❌ Build failed or no output files found"
  exit 1
fi

echo "🏁 Done! Your archiso is ready."
