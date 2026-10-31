#!/usr/bin/env bash
# Netlify's build machines don't include Flutter, so install it before building.
set -euo pipefail

FLUTTER_VERSION=3.41.6
FLUTTER_DIR="$HOME/flutter"

if [ ! -d "$FLUTTER_DIR" ]; then
  git clone --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi
export PATH="$FLUTTER_DIR/bin:$PATH"

flutter --version
flutter pub get
flutter build web --release
