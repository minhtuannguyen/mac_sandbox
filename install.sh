#!/bin/bash
#
# install.sh — installs (or updates) the mac-sandbox wrapper
#
# One-liner install (defaults to opencode):
#   curl -fsSL https://raw.githubusercontent.com/minhtuannguyen/mac_sandbox/main/install.sh | bash
#
# Install for a different app:
#   curl -fsSL https://raw.githubusercontent.com/minhtuannguyen/mac_sandbox/main/install.sh | bash -s -- --app claude
#
# What it does:
#   1. Downloads mac-sandbox to ~/.local/bin/<app>-sandbox
#   2. Creates ~/.config/mac-sandbox/<app>.json (user config) if not present
#      └─ for opencode: migrates ~/.config/opencode/sandbox.json automatically
#   3. Adds alias <app>=<app>-sandbox to ~/.zshrc
#
# Update behaviour (safe to re-run):
#   - wrapper:     replaced only when the remote version differs (checksum check)
#   - user config: never overwritten — your settings are preserved
#   - alias:       idempotent — added only once
#

set -e

# ── Parse args ────────────────────────────────────────────────────────────────

APP_NAME="opencode"   # default

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)   APP_NAME="$2"; shift 2 ;;
    --app=*) APP_NAME="${1#--app=}"; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

WRAPPER_NAME="${APP_NAME}-sandbox"

# ── URLs & paths ──────────────────────────────────────────────────────────────

REPO_RAW="https://raw.githubusercontent.com/minhtuannguyen/mac_sandbox/main/install.sh"
WRAPPER_URL="${REPO_RAW}/mac-sandbox"
CONFIG_TEMPLATE_URL="${REPO_RAW}/config.example.json"

INSTALL_DIR="${HOME}/.local/bin"
WRAPPER_DST="${INSTALL_DIR}/${WRAPPER_NAME}"

MAC_SANDBOX_DIR="${HOME}/.config/mac-sandbox"
USER_CONFIG="${MAC_SANDBOX_DIR}/${APP_NAME}.json"

# Migration sources (checked only when APP_NAME=opencode)
OLD_CONFIG_V2="${HOME}/.config/opencode/sandbox.json"         # v2 location
OLD_CONFIG_V1="${HOME}/.config/opencode/sandbox/config.json"  # v1 location

ZSHRC="${HOME}/.zshrc"
ALIAS_LINE="alias ${APP_NAME}=${WRAPPER_NAME}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()     { echo -e "${GREEN}✓${NC} $1"; }
info()   { echo -e "${YELLOW}→${NC} $1"; }
update() { echo -e "${BLUE}↑${NC} $1"; }

echo ""
echo "Installing ${WRAPPER_NAME} (mac-sandbox for ${APP_NAME})..."
echo ""

# ── Detect whether we're running from a local clone or via curl ──────────────

if [[ "${BASH_SOURCE[0]}" != "${0}" ]] || [[ -z "${BASH_SOURCE[0]}" ]]; then
  # Piped through bash (curl | bash) — always fetch from remote
  SCRIPT_DIR=""
  FETCH_MODE="remote"
else
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # Check if mac-sandbox exists locally next to this script
  if [[ -f "${SCRIPT_DIR}/mac-sandbox" ]]; then
    FETCH_MODE="local"
  else
    FETCH_MODE="remote"
  fi
fi

# ── 1. Create ~/.local/bin if needed ─────────────────────────────────────────

if [[ ! -d "$INSTALL_DIR" ]]; then
  mkdir -p "$INSTALL_DIR"
  ok "Created $INSTALL_DIR"
fi

# ── 2. Install / update the wrapper ──────────────────────────────────────────

install_wrapper_from_remote() {
  local tmp
  tmp="$(mktemp)"
  if ! curl -fsSL "$WRAPPER_URL" -o "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    echo "Error: failed to download wrapper from $WRAPPER_URL" >&2
    exit 1
  fi
  chmod +x "$tmp"
  mv "$tmp" "$WRAPPER_DST"
}

if [[ "$FETCH_MODE" == "local" ]]; then
  # Running from a local clone — compare checksums and replace only if changed
  LOCAL_SRC="${SCRIPT_DIR}/mac-sandbox"
  if [[ -f "$WRAPPER_DST" ]]; then
    src_sum="$(shasum -a 256 "$LOCAL_SRC" | awk '{print $1}')"
    dst_sum="$(shasum -a 256 "$WRAPPER_DST" | awk '{print $1}')"
    if [[ "$src_sum" == "$dst_sum" ]]; then
      ok "Wrapper already up to date"
    else
      cp "$LOCAL_SRC" "$WRAPPER_DST"
      chmod +x "$WRAPPER_DST"
      update "Wrapper updated → $WRAPPER_DST"
    fi
  else
    cp "$LOCAL_SRC" "$WRAPPER_DST"
    chmod +x "$WRAPPER_DST"
    ok "Installed $WRAPPER_DST"
  fi
else
  # Running via curl | bash — fetch from remote
  if [[ -f "$WRAPPER_DST" ]]; then
    tmp="$(mktemp)"
    if curl -fsSL "$WRAPPER_URL" -o "$tmp" 2>/dev/null; then
      dst_sum="$(shasum -a 256 "$WRAPPER_DST" | awk '{print $1}')"
      src_sum="$(shasum -a 256 "$tmp" | awk '{print $1}')"
      if [[ "$src_sum" == "$dst_sum" ]]; then
        rm -f "$tmp"
        ok "Wrapper already up to date"
      else
        chmod +x "$tmp"
        mv "$tmp" "$WRAPPER_DST"
        update "Wrapper updated → $WRAPPER_DST"
      fi
    else
      rm -f "$tmp"
      echo "Error: failed to download wrapper" >&2
      exit 1
    fi
  else
    install_wrapper_from_remote
    ok "Installed $WRAPPER_DST"
  fi
fi

# ── 3. Create user config at ~/.config/mac-sandbox/<app>.json ────────────────

mkdir -p "$MAC_SANDBOX_DIR"

if [[ -f "$USER_CONFIG" ]]; then
  ok "User config unchanged: $USER_CONFIG"
elif [[ "$APP_NAME" == "opencode" && -f "$OLD_CONFIG_V2" ]]; then
  # Migrate from the v2 opencode-specific location
  cp "$OLD_CONFIG_V2" "$USER_CONFIG"
  # Add state_dirs if missing (previously they were hardcoded in the wrapper)
  if ! jq -e '.state_dirs' "$USER_CONFIG" > /dev/null 2>&1; then
    tmp_cfg="$(mktemp)"
    jq '. + {"state_dirs": ["~/.config/opencode/", "~/.local/share/opencode/", "~/.local/state/opencode/"]}' \
      "$USER_CONFIG" > "$tmp_cfg" && mv "$tmp_cfg" "$USER_CONFIG"
    info "Added state_dirs (opencode defaults) to migrated config."
  fi
  ok "Migrated config: $OLD_CONFIG_V2 → $USER_CONFIG"
  info "Old file kept at $OLD_CONFIG_V2 — remove it manually once verified."
elif [[ "$APP_NAME" == "opencode" && -f "$OLD_CONFIG_V1" ]]; then
  # Migrate from the v1 location
  cp "$OLD_CONFIG_V1" "$USER_CONFIG"
  if ! jq -e '.state_dirs' "$USER_CONFIG" > /dev/null 2>&1; then
    tmp_cfg="$(mktemp)"
    jq '. + {"state_dirs": ["~/.config/opencode/", "~/.local/share/opencode/", "~/.local/state/opencode/"]}' \
      "$USER_CONFIG" > "$tmp_cfg" && mv "$tmp_cfg" "$USER_CONFIG"
    info "Added state_dirs (opencode defaults) to migrated config."
  fi
  ok "Migrated config: $OLD_CONFIG_V1 → $USER_CONFIG"
else
  # Fetch template or write inline default
  if [[ "$FETCH_MODE" == "local" && -f "${SCRIPT_DIR}/config.example.json" && "$APP_NAME" == "opencode" ]]; then
    cp "${SCRIPT_DIR}/config.example.json" "$USER_CONFIG"
  elif [[ "$APP_NAME" == "opencode" ]]; then
    if ! curl -fsSL "$CONFIG_TEMPLATE_URL" -o "$USER_CONFIG" 2>/dev/null; then
      cat > "$USER_CONFIG" << EOF
{
  "\$schema": "${REPO_RAW}/schema.json",
  "sandbox_enabled": true,
  "allowed_directories": [
    "${HOME}/repositories/**"
  ],
  "state_dirs": [
    "~/.config/opencode/",
    "~/.local/share/opencode/",
    "~/.local/state/opencode/"
  ],
  "temp_allowed": true,
  "network": "full",
  "process_spawning": "allowed",
  "deny_privilege_escalation": true
}
EOF
    fi
  else
    # Minimal default for non-opencode apps
    cat > "$USER_CONFIG" << EOF
{
  "\$schema": "${REPO_RAW}/schema.json",
  "sandbox_enabled": true,
  "allowed_directories": [
    "${HOME}/repositories/**"
  ],
  "state_dirs": [],
  "temp_allowed": true,
  "network": "full",
  "process_spawning": "allowed",
  "deny_privilege_escalation": true,
  "description": "Sandbox config for ${APP_NAME}. Edit allowed_directories and state_dirs."
}
EOF
  fi
  ok "Created user config: $USER_CONFIG"
  info "Edit $USER_CONFIG to set allowed_directories and state_dirs for ${APP_NAME}."
fi

# ── 4. Add alias to ~/.zshrc ──────────────────────────────────────────────────

if grep -qF "$ALIAS_LINE" "$ZSHRC" 2>/dev/null; then
  ok "Alias already in $ZSHRC"
else
  echo "" >> "$ZSHRC"
  echo "# mac-sandbox wrapper for ${APP_NAME}" >> "$ZSHRC"
  echo "$ALIAS_LINE" >> "$ZSHRC"
  ok "Added alias to $ZSHRC"
fi

# ── 5. PATH check ─────────────────────────────────────────────────────────────

if ! echo "$PATH" | tr ':' '\n' | grep -qF "$INSTALL_DIR"; then
  info "Note: $INSTALL_DIR is not in your current PATH."
  info "Add this to ~/.zshrc:  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "Done. Open a new terminal (or: source ~/.zshrc) then type: ${APP_NAME}"
echo "Config: $USER_CONFIG"
echo ""
