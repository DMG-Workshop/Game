#!/bin/bash
# SessionStart hook: install the Dart SDK so pf2e_core's analyzer and tests run.
#
# Dart is not preinstalled in Claude Code on the web containers. Without this,
# every session has to download the SDK by hand before it can run `dart test`.
set -euo pipefail

# Local machines are assumed to have their own toolchain.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

DART_VERSION="${DART_VERSION:-3.13.4}"
DART_SDK_DIR="${DART_SDK_DIR:-/opt/dart-sdk}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

install_dart() {
  # Idempotent: a matching SDK already in place is left alone, so a cached
  # container skips the ~230MB download entirely.
  if [ -x "$DART_SDK_DIR/bin/dart" ]; then
    local installed
    installed="$("$DART_SDK_DIR/bin/dart" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
    if [ "$installed" = "$DART_VERSION" ]; then
      echo "Dart $DART_VERSION already installed at $DART_SDK_DIR"
      return 0
    fi
    echo "Replacing Dart $installed with $DART_VERSION"
    rm -rf "$DART_SDK_DIR"
  fi

  local arch zip_name url tmp
  case "$(uname -m)" in
    x86_64) arch="x64" ;;
    aarch64 | arm64) arch="arm64" ;;
    *) echo "Unsupported architecture: $(uname -m)" >&2; return 1 ;;
  esac

  # Note the "-release" suffix: the path without it 404s.
  zip_name="dartsdk-linux-${arch}-release.zip"
  url="https://storage.googleapis.com/dart-archive/channels/stable/release/${DART_VERSION}/sdk/${zip_name}"

  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  echo "Downloading Dart $DART_VERSION ($arch)..."
  if ! curl -fsSL --retry 3 --retry-delay 2 --max-time 600 -o "$tmp/dart.zip" "$url"; then
    echo "Failed to download the Dart SDK from $url" >&2
    return 1
  fi

  mkdir -p "$(dirname "$DART_SDK_DIR")"
  unzip -q -o "$tmp/dart.zip" -d "$(dirname "$DART_SDK_DIR")"
  "$DART_SDK_DIR/bin/dart" --version
}

install_dart

export PATH="$DART_SDK_DIR/bin:$PATH"

# Persist the toolchain on PATH for the rest of the session.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$DART_SDK_DIR/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi

# Warm the package cache so `dart test` works immediately.
if [ -f "$PROJECT_DIR/packages/pf2e_core/pubspec.yaml" ]; then
  echo "Resolving pf2e_core dependencies..."
  (cd "$PROJECT_DIR/packages/pf2e_core" && dart pub get)
fi

echo "Dart toolchain ready."
