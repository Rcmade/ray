#!/bin/sh
# ═══════════════════════════════════════════════════════════════════════════════
# Ray CLI Universal Installer
# Compatible with macOS, Linux, Alpine (musl), WSL, Docker, and CI environments
# ═══════════════════════════════════════════════════════════════════════════════
set -e

# Safe HOME fallback for bare containers
HOME="${HOME:-/root}"

# Visual colors (disabled if not interactive TTY)
if [ -t 1 ]; then
  ESC="$(printf '\033')"
  BOLD="${ESC}[1m"
  GREEN="${ESC}[32m"
  CYAN="${ESC}[36m"
  YELLOW="${ESC}[33m"
  RED="${ESC}[31m"
  DIM="${ESC}[2m"
  RESET="${ESC}[0m"
else
  BOLD=""
  GREEN=""
  CYAN=""
  YELLOW=""
  RED=""
  DIM=""
  RESET=""
fi

echo "${CYAN}${BOLD}"
echo "    ██████╗  █████╗ ██╗   ██╗"
echo "    ██╔══██╗██╔══██╗╚██╗ ██╔╝"
echo "    ██████╔╝███████║ ╚████╔╝ "
echo "    ██╔══██╗██╔══██║  ╚██╔╝  "
echo "    ██║  ██║██║  ██║   ██║   "
echo "    ╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   "
echo "   Git for your .env"
echo "${RESET}"

# 1. Detect Operating System
OS="$(uname -s)"
case "$OS" in
  Darwin*)
    PLATFORM="darwin"
    ;;
  Linux*)
    PLATFORM="linux"
    ;;
  *)
    echo "${RED}Error: Unsupported operating system: ${OS}${RESET}" >&2
    echo "For Windows, run the PowerShell installer:"
    echo "  ${CYAN}iwr https://secrets.rcmade.io/install.ps1 -useb | iex${RESET}"
    echo "Or install via NPM:"
    echo "  ${CYAN}npm install -g @rcmade/ray${RESET}"
    exit 1
    ;;
esac

# 2. Detect CPU Architecture & C Library Runtime
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64)
    ARCH="x64"
    ;;
  arm64|aarch64)
    ARCH="arm64"
    ;;
  *)
    echo "${RED}Error: Unsupported architecture: ${ARCH}${RESET}" >&2
    echo "You can install Ray CLI via NPM instead:"
    echo "  ${CYAN}npm install -g @rcmade/ray${RESET}"
    exit 1
    ;;
esac

# Detect Libc (musl vs glibc) on Linux for Alpine/Docker compatibility
LIBC_SUFFIX=""
if [ "$PLATFORM" = "linux" ]; then
  if ldd /bin/sh 2>&1 | grep -qi "musl" || [ -f /lib/ld-musl-x86_64.so.1 ] || [ -f /lib/ld-musl-aarch64.so.1 ]; then
    LIBC_SUFFIX="-musl"
  fi
fi

TARGET_NAME="ray-${PLATFORM}-${ARCH}${LIBC_SUFFIX}"
ARCHIVE_NAME="${TARGET_NAME}.tar.gz"

# 3. Determine Version and URLs
VERSION="${RAY_VERSION:-latest}"
REPO_OWNER="Rcmade"
REPO_NAME="ray"

if [ "$VERSION" = "latest" ]; then
  DOWNLOAD_URL="${RAY_RELEASE_URL:-https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/latest/download}/${ARCHIVE_NAME}"
else
  DOWNLOAD_URL="${RAY_RELEASE_URL:-https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/${VERSION}}/${ARCHIVE_NAME}"
fi

# 4. Determine Install Directory
if [ -n "$RAY_INSTALL_DIR" ]; then
  INSTALL_DIR="$RAY_INSTALL_DIR"
elif [ "$(id -u)" = "0" ] && [ -d "/usr/local/bin" ] && [ -w "/usr/local/bin" ]; then
  INSTALL_DIR="/usr/local/bin"
else
  INSTALL_DIR="${HOME}/.ray/bin"
fi

echo "${DIM}Detected environment:${RESET} ${BOLD}${PLATFORM}-${ARCH}${LIBC_SUFFIX}${RESET}"
echo "${DIM}Target binary:${RESET}        ${BOLD}${TARGET_NAME}${RESET}"
echo "${DIM}Install directory:${RESET}    ${BOLD}${INSTALL_DIR}${RESET}"
echo ""

# 5. Create temporary scratch directory
TMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'ray-install')"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

ARCHIVE_FILE="${TMP_DIR}/${ARCHIVE_NAME}"

# 6. Download Archive
echo "${CYAN}→ Downloading Ray CLI (${ARCHIVE_NAME})...${RESET}"
if command -v curl >/dev/null 2>&1; then
  if [ -t 1 ] && [ -t 2 ]; then
    curl -# -fL "$DOWNLOAD_URL" -o "$ARCHIVE_FILE" || {
      echo "${RED}Error: Failed to download archive from: ${DOWNLOAD_URL}${RESET}" >&2
      echo "Tip: Verify network connection or install via NPM: ${CYAN}npm install -g @rcmade/ray${RESET}" >&2
      exit 1
    }
  else
    curl -fsSL "$DOWNLOAD_URL" -o "$ARCHIVE_FILE" || {
      echo "${RED}Error: Failed to download archive from: ${DOWNLOAD_URL}${RESET}" >&2
      echo "Tip: Verify network connection or install via NPM: ${CYAN}npm install -g @rcmade/ray${RESET}" >&2
      exit 1
    }
  fi
elif command -v wget >/dev/null 2>&1; then
  if [ -t 1 ] && [ -t 2 ]; then
    wget --show-progress -qO "$ARCHIVE_FILE" "$DOWNLOAD_URL" || {
      echo "${RED}Error: Failed to download archive from: ${DOWNLOAD_URL}${RESET}" >&2
      exit 1
    }
  else
    wget -qO "$ARCHIVE_FILE" "$DOWNLOAD_URL" || {
      echo "${RED}Error: Failed to download archive from: ${DOWNLOAD_URL}${RESET}" >&2
      exit 1
    }
  fi
else
  echo "${RED}Error: Neither curl nor wget was found in PATH.${RESET}" >&2
  echo "Tip: Install via NPM: npm install -g @rcmade/ray" >&2
  exit 1
fi
echo "${GREEN}✓ Download complete${RESET}"

# 7. Extract Binary
echo "${CYAN}→ Extracting binary...${RESET}"
mkdir -p "$TMP_DIR/extracted"
tar -xzf "$ARCHIVE_FILE" -C "$TMP_DIR/extracted"

# Locate the extracted ray binary
if [ -f "$TMP_DIR/extracted/ray" ]; then
  EXTRACTED_BIN="$TMP_DIR/extracted/ray"
elif [ -f "$TMP_DIR/extracted/${TARGET_NAME}" ]; then
  EXTRACTED_BIN="$TMP_DIR/extracted/${TARGET_NAME}"
else
  # Find first executable file in extraction directory
  EXTRACTED_BIN="$(find "$TMP_DIR/extracted" -type f | head -n 1)"
fi

if [ -z "$EXTRACTED_BIN" ] || [ ! -f "$EXTRACTED_BIN" ]; then
  echo "${RED}Error: Failed to find executable inside downloaded archive.${RESET}" >&2
  exit 1
fi
echo "${GREEN}✓ Binary extracted${RESET}"

# 8. Install to Target Directory
echo "${CYAN}→ Installing to ${INSTALL_DIR}...${RESET}"
mkdir -p "$INSTALL_DIR"
cp -f "$EXTRACTED_BIN" "${INSTALL_DIR}/ray"
chmod 755 "${INSTALL_DIR}/ray"

# Clear macOS Gatekeeper quarantine attribute if present
if [ "$PLATFORM" = "darwin" ] && command -v xattr >/dev/null 2>&1; then
  xattr -d com.apple.quarantine "${INSTALL_DIR}/ray" 2>/dev/null || true
fi
echo "${GREEN}✓ Installed to ${INSTALL_DIR}/ray${RESET}"

# 9. Configure Shell PATH if needed
PATH_CONFIGURED=0
case ":$PATH:" in
  *":$INSTALL_DIR:"*)
    PATH_CONFIGURED=1
    ;;
esac

PROFILE_FILE=""
if [ "$PATH_CONFIGURED" -eq 0 ] && [ "$INSTALL_DIR" = "${HOME}/.ray/bin" ]; then
  USER_SHELL="$(basename "${SHELL:-/bin/sh}")"
  case "$USER_SHELL" in
    zsh)
      PROFILE_FILE="${HOME}/.zshrc"
      PATH_EXPORT='export PATH="$HOME/.ray/bin:$PATH"'
      ;;
    bash)
      if [ "$PLATFORM" = "darwin" ] && [ -f "${HOME}/.bash_profile" ]; then
        PROFILE_FILE="${HOME}/.bash_profile"
      else
        PROFILE_FILE="${HOME}/.bashrc"
      fi
      PATH_EXPORT='export PATH="$HOME/.ray/bin:$PATH"'
      ;;
    fish)
      PROFILE_FILE="${HOME}/.config/fish/config.fish"
      PATH_EXPORT='set -gx PATH "$HOME/.ray/bin" $PATH'
      ;;
    *)
      PROFILE_FILE="${HOME}/.profile"
      PATH_EXPORT='export PATH="$HOME/.ray/bin:$PATH"'
      ;;
  esac

  if [ -n "$PROFILE_FILE" ]; then
    mkdir -p "$(dirname "$PROFILE_FILE")"
    if [ -f "$PROFILE_FILE" ]; then
      if ! grep -q '\.ray/bin' "$PROFILE_FILE" 2>/dev/null; then
        printf "\n# Ray CLI\n%s\n" "$PATH_EXPORT" >> "$PROFILE_FILE"
        echo "${GREEN}→ Automatically added ~/.ray/bin to your PATH in ${PROFILE_FILE}${RESET}"
      fi
    else
      printf "# Ray CLI\n%s\n" "$PATH_EXPORT" > "$PROFILE_FILE"
      echo "${GREEN}→ Automatically created ${PROFILE_FILE} and added ~/.ray/bin to PATH${RESET}"
    fi
  else
    echo "${YELLOW}Notice: Please manually add ${INSTALL_DIR} to your PATH:${RESET}"
    echo "  ${CYAN}${PATH_EXPORT}${RESET}"
  fi
fi

# 10. Smoke Test the Installed Binary
INSTALLED_RAY="${INSTALL_DIR}/ray"
if [ -x "$INSTALLED_RAY" ]; then
  INSTALLED_VERSION="$("$INSTALLED_RAY" --version 2>/dev/null || echo "installed")"
else
  INSTALLED_VERSION="installed"
fi

if [ "$INSTALLED_VERSION" = "installed" ] && [ "$LIBC_SUFFIX" = "-musl" ]; then
  if ! [ -f /usr/lib/libstdc++.so.6 ] && ! [ -f /lib/libstdc++.so.6 ]; then
    echo "${YELLOW}Notice: Alpine Linux requires libstdc++ and libgcc.${RESET}"
    echo "  Install with: ${CYAN}apk add --no-cache libstdc++ libgcc${RESET}"
  fi
fi

echo ""
echo "${GREEN}${BOLD}✓ Ray CLI successfully installed!${RESET} (${INSTALLED_VERSION})"
echo ""
echo "Get started with:"
if [ "$PATH_CONFIGURED" -eq 0 ] && [ -n "$PROFILE_FILE" ]; then
  echo "  ${BOLD}source ${PROFILE_FILE}${RESET}"
fi
echo "  ${CYAN}${BOLD}ray login${RESET}"
echo "  ${CYAN}${BOLD}ray --help${RESET}"
echo ""
