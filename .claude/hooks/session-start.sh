#!/bin/bash
# Installs PandaCode's dependencies in Claude Code cloud sessions so
# typecheck, unit tests, the build and Rust checks work.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR"

# xlsx is pinned to a tarball on cdn.sheetjs.com. When the environment's
# network policy blocks that host, install the npm-registry build (same
# read/utils API) for this session only and put the manifests back.
install_root() {
  if npm install --no-audit --no-fund; then
    return
  fi
  echo "npm install failed; retrying with xlsx from the npm registry" >&2
  local backup
  backup="$(mktemp -d)"
  cp package.json package-lock.json "$backup/"
  trap 'cp "$backup/package.json" "$backup/package-lock.json" . ; rm -rf "$backup"; trap - RETURN' RETURN
  node -e '
    const fs = require("fs");
    const p = JSON.parse(fs.readFileSync("package.json", "utf8"));
    p.dependencies.xlsx = "0.18.5";
    fs.writeFileSync("package.json", JSON.stringify(p, null, 2) + "\n");
  '
  npm install --no-audit --no-fund
}

install_root
npm install --no-audit --no-fund --prefix website

# Native libraries the Tauri crate links against (same list as CI).
if ! pkg-config --exists webkit2gtk-4.1 2>/dev/null; then
  SUDO=""
  [ "$(id -u)" -ne 0 ] && SUDO="sudo"
  $SUDO apt-get update -qq
  DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y -qq \
    libwebkit2gtk-4.1-dev build-essential curl wget file libxdo-dev libssl-dev \
    libdbus-1-dev libayatana-appindicator3-dev librsvg2-dev patchelf xvfb dbus-x11 xdg-utils
fi

# Playwright: the config defaults to macOS Chrome; use the image's Chromium,
# and fewer workers so the dev server keeps up on a small container.
CHROME="$(ls -d /opt/pw-browsers/chromium-*/chrome-linux64/chrome 2>/dev/null | head -1 || true)"
if [ -n "$CHROME" ] && [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PANDACODE_TEST_CHROME=\"$CHROME\"" >> "$CLAUDE_ENV_FILE"
  echo "export PW_WORKERS=\"\${PW_WORKERS:-1}\"" >> "$CLAUDE_ENV_FILE"
fi

# Tauri embeds dist/, and tests/bundle.test.mjs reads it.
npm run build
