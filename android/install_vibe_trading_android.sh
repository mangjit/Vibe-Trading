#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Vibe-Trading Android installer
# Recommended target: Termux + proot-distro + Debian/Ubuntu userspace.
# Default Python installer: uv.
# Strategy:
#   - keep most installs wheel-only / prebuilt-heavy
#   - avoid on-phone compilation of large native packages
#   - use targeted workarounds for problem packages (e.g. AKShare on Ubuntu ARM)

VT_CONTAINER="${VT_CONTAINER:-vibe-trading}"
VT_DISTRO="${VT_DISTRO:-debian}"
VT_SOURCE="${VT_SOURCE:-pypi}"                 # pypi | git
VT_PACKAGE_SPEC="${VT_PACKAGE_SPEC:-vibe-trading-ai==0.1.14}"
VT_REPO_URL="${VT_REPO_URL:-https://github.com/HKUDS/Vibe-Trading.git}"
VT_APP_DIR="${VT_APP_DIR:-/root/Vibe-Trading}"
VT_VENV="${VT_VENV:-/opt/vibe-trading-venv}"
VT_PY_INSTALLER="${VT_PY_INSTALLER:-uv}"       # uv | pip
VT_REFUSE_SOURCE_BUILDS="${VT_REFUSE_SOURCE_BUILDS:-1}"
VT_ALLOW_LIGHT_SDISTS="${VT_ALLOW_LIGHT_SDISTS:-1}"
VT_UV_INSTALL_DIR="${VT_UV_INSTALL_DIR:-/usr/local/bin}"
VT_UV_INSTALLER_URL="${VT_UV_INSTALLER_URL:-https://astral.sh/uv/install.sh}"

# Feature flags: defaults are intentionally lean for phone use.
VT_WITH_MARKET="${VT_WITH_MARKET:-1}"
VT_WITH_AKSHARE="${VT_WITH_AKSHARE:-1}"
VT_WITH_DOCS="${VT_WITH_DOCS:-1}"
VT_WITH_API="${VT_WITH_API:-0}"
VT_WITH_MCP="${VT_WITH_MCP:-0}"
VT_WITH_ML="${VT_WITH_ML:-0}"
VT_WITH_REPORTS="${VT_WITH_REPORTS:-0}"
VT_WITH_DUCKDB="${VT_WITH_DUCKDB:-0}"
VT_WITH_AIOHTTP="${VT_WITH_AIOHTTP:-0}"

TERMUX_BIN_DIR="${TERMUX_BIN_DIR:-$HOME/bin}"

log() {
  printf '\n==> %s\n' "$*"
}

die() {
  printf '\n[ERROR] %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

ensure_termux() {
  need_cmd pkg
  case "${VT_DISTRO}" in
    debian|debian:*|ubuntu|ubuntu:* ) ;;
    * ) die "VT_DISTRO=${VT_DISTRO} is not supported by this script. Use a Debian/Ubuntu container." ;;
  esac
  case "${VT_PY_INSTALLER}" in
    uv|pip ) ;;
    * ) die "VT_PY_INSTALLER=${VT_PY_INSTALLER} is not supported. Use uv or pip." ;;
  esac
}

install_termux_side() {
  log "Installing Termux-side prerequisites"
  pkg update -y
  pkg install -y proot-distro
}

container_exists() {
  proot-distro login "$VT_CONTAINER" -- /bin/sh -lc 'exit 0' >/dev/null 2>&1
}

ensure_container() {
  if container_exists; then
    log "Reusing existing container: $VT_CONTAINER"
    return
  fi

  log "Installing proot container: $VT_CONTAINER from $VT_DISTRO"
  if proot-distro install --help 2>/dev/null | grep -q -- '--name'; then
    proot-distro install --name "$VT_CONTAINER" "$VT_DISTRO"
  else
    if [ "$VT_CONTAINER" != "$VT_DISTRO" ]; then
      die "This proot-distro version does not support --name. Set VT_CONTAINER=$VT_DISTRO or upgrade proot-distro."
    fi
    proot-distro install "$VT_DISTRO"
  fi
}

run_container_setup() {
  log "Installing Python environment inside $VT_CONTAINER"

  proot-distro login "$VT_CONTAINER" -- env \
    VT_SOURCE="$VT_SOURCE" \
    VT_PACKAGE_SPEC="$VT_PACKAGE_SPEC" \
    VT_REPO_URL="$VT_REPO_URL" \
    VT_APP_DIR="$VT_APP_DIR" \
    VT_VENV="$VT_VENV" \
    VT_PY_INSTALLER="$VT_PY_INSTALLER" \
    VT_REFUSE_SOURCE_BUILDS="$VT_REFUSE_SOURCE_BUILDS" \
    VT_ALLOW_LIGHT_SDISTS="$VT_ALLOW_LIGHT_SDISTS" \
    VT_UV_INSTALL_DIR="$VT_UV_INSTALL_DIR" \
    VT_UV_INSTALLER_URL="$VT_UV_INSTALLER_URL" \
    VT_WITH_MARKET="$VT_WITH_MARKET" \
    VT_WITH_AKSHARE="$VT_WITH_AKSHARE" \
    VT_WITH_DOCS="$VT_WITH_DOCS" \
    VT_WITH_API="$VT_WITH_API" \
    VT_WITH_MCP="$VT_WITH_MCP" \
    VT_WITH_ML="$VT_WITH_ML" \
    VT_WITH_REPORTS="$VT_WITH_REPORTS" \
    VT_WITH_DUCKDB="$VT_WITH_DUCKDB" \
    VT_WITH_AIOHTTP="$VT_WITH_AIOHTTP" \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    /bin/bash -s <<'EOF'
set -euo pipefail
IFS=$'\n\t'
export DEBIAN_FRONTEND=noninteractive

log() {
  printf '\n[container] %s\n' "$*"
}

BASE_APT=(
  ca-certificates
  python3
  python3-venv
  python3-pip
)

if [ "$VT_PY_INSTALLER" = "uv" ]; then
  BASE_APT+=(curl)
fi

if [ "$VT_SOURCE" = "git" ]; then
  BASE_APT+=(git)
fi

REPORT_APT=(
  fonts-dejavu-core
  libcairo2
  libgdk-pixbuf-2.0-0
  libpango-1.0-0
  shared-mime-info
)

log "apt-get update"
apt-get update

log "Installing base apt packages"
apt-get install -y --no-install-recommends "${BASE_APT[@]}"

if [ "$VT_WITH_REPORTS" = "1" ]; then
  log "Installing report-rendering apt packages"
  apt-get install -y --no-install-recommends "${REPORT_APT[@]}"
fi

install_uv() {
  if command -v uv >/dev/null 2>&1; then
    return
  fi
  log "Installing uv"
  INSTALLER_NO_MODIFY_PATH=1 UV_INSTALL_DIR="$VT_UV_INSTALL_DIR" \
    sh -c "
      set -e
      curl -LsSf '$VT_UV_INSTALLER_URL' | sh
    "
}

create_venv() {
  mkdir -p "$(dirname "$VT_VENV")"
  case "$VT_PY_INSTALLER" in
    uv)
      install_uv
      uv venv --python python3 "$VT_VENV"
      ;;
    pip)
      python3 -m venv "$VT_VENV"
      ;;
    *)
      echo "Unsupported VT_PY_INSTALLER=$VT_PY_INSTALLER" >&2
      exit 1
      ;;
  esac
}

py_install_binary() {
  local -a args
  case "$VT_PY_INSTALLER" in
    uv)
      args=(uv pip install --python "$VT_VENV/bin/python")
      if [ "$VT_REFUSE_SOURCE_BUILDS" = "1" ]; then
        args+=(--no-build)
      fi
      "${args[@]}" "$@"
      ;;
    pip)
      if [ "$VT_REFUSE_SOURCE_BUILDS" = "1" ]; then
        "$VT_VENV/bin/python" -m pip install --no-cache-dir --only-binary=:all: "$@"
      else
        "$VT_VENV/bin/python" -m pip install --no-cache-dir "$@"
      fi
      ;;
  esac
}

py_install_allow_source() {
  case "$VT_PY_INSTALLER" in
    uv)
      uv pip install --python "$VT_VENV/bin/python" "$@"
      ;;
    pip)
      "$VT_VENV/bin/python" -m pip install --no-cache-dir "$@"
      ;;
  esac
}

py_install_nodeps() {
  case "$VT_PY_INSTALLER" in
    uv)
      uv pip install --python "$VT_VENV/bin/python" --no-deps "$@"
      ;;
    pip)
      "$VT_VENV/bin/python" -m pip install --no-cache-dir --no-deps "$@"
      ;;
  esac
}

install_akshare_stack() {
  local -a akshare_binary_prereqs=(
    'beautifulsoup4>=4.9.1'
    'lxml>=4.2.1'
    'curl_cffi>=0.13.0'
    'html5lib>=1.0.1'
    'xlrd>=1.2.0'
    'urllib3>=1.25.8'
    'tqdm>=4.43.0'
    'openpyxl>=3.0.3'
    'tabulate>=0.8.6'
    'decorator>=4.4.2'
    'akracer>=0.0.13'
  )

  log "Installing AKShare prerequisite wheels"
  py_install_binary "${akshare_binary_prereqs[@]}"

  if [ "$VT_ALLOW_LIGHT_SDISTS" != "1" ] && [ "$VT_REFUSE_SOURCE_BUILDS" = "1" ]; then
    echo "AKShare needs jsonpath from an sdist, but VT_ALLOW_LIGHT_SDISTS=0 blocks that workaround." >&2
    exit 1
  fi

  log "Installing jsonpath from source for AKShare (small pure-Python package)"
  py_install_allow_source 'jsonpath>=0.82'

  log "Installing AKShare without auto-resolving py-mini-racer"
  py_install_nodeps 'akshare>=1.12.0'
}

create_venv

log "Bootstrapping packaging tools"
case "$VT_PY_INSTALLER" in
  uv)
    uv pip install --python "$VT_VENV/bin/python" pip setuptools wheel
    ;;
  pip)
    "$VT_VENV/bin/python" -m pip install --no-cache-dir --upgrade pip setuptools wheel
    ;;
esac

CORE_PACKAGES=(
  'rich>=13.0.0'
  'pyyaml>=6.0.0'
  'langchain>=1.3.9,<2'
  'langchain-core>=1.0.0,<2'
  'langchain-openai>=1.0.0,<2'
  'langgraph>=1.2.5,<1.3'
  'langgraph-checkpoint>=2.1.0,<5'
  'python-dotenv>=1.0.0'
  'httpx>=0.28.0'
  'h2>=4.4.1'
  'defusedxml>=0.7.1'
  'oauth-cli-kit>=0.1.3'
  'numpy>=1.24.0'
  'pandas>=2.0.0,<3.0.0'
  'scipy>=1.10.0'
  'pydantic>=2.0.0'
  'ddgs>=6.0.0'
  'jinja2>=3.1.0'
  'prompt_toolkit>=3.0.0'
)

MARKET_PACKAGES=(
  'tushare>=1.2.89'
  'requests>=2.31.0'
  'yfinance>=0.2.30'
  'ccxt>=4.5.71'
  'cryptography>=50.0.0'
)

DOC_PACKAGES=(
  'openpyxl>=3.1.0'
  'python-docx>=1.1.0'
  'python-pptx>=0.6.23'
  'Pillow>=12.2.0'
  'pypdfium2>=4.0.0'
)

API_PACKAGES=(
  'fastapi>=0.104.0'
  'uvicorn>=0.24.0'
  'websockets>=12.0'
  'python-multipart>=0.0.18'
  'sse-starlette>=1.6.0'
)

MCP_PACKAGES=(
  'fastmcp>=2.14.0'
)

ML_PACKAGES=(
  'scikit-learn>=1.3.0'
  'joblib>=1.3.0'
  'bottleneck>=1.3.7'
)

REPORT_PACKAGES=(
  'matplotlib>=3.7.0'
  'weasyprint>=60.0'
)

DUCKDB_PACKAGES=(
  'duckdb>=1.2.0'
)

AIOHTTP_PACKAGES=(
  'aiohttp>=3.14.3'
)

ALL_BINARY_PACKAGES=("${CORE_PACKAGES[@]}")

if [ "$VT_WITH_MARKET" = "1" ]; then
  ALL_BINARY_PACKAGES+=("${MARKET_PACKAGES[@]}")
fi

if [ "$VT_WITH_DOCS" = "1" ]; then
  ALL_BINARY_PACKAGES+=("${DOC_PACKAGES[@]}")
fi

if [ "$VT_WITH_API" = "1" ]; then
  ALL_BINARY_PACKAGES+=("${API_PACKAGES[@]}")
fi

if [ "$VT_WITH_MCP" = "1" ]; then
  ALL_BINARY_PACKAGES+=("${MCP_PACKAGES[@]}")
fi

if [ "$VT_WITH_ML" = "1" ]; then
  ALL_BINARY_PACKAGES+=("${ML_PACKAGES[@]}")
fi

if [ "$VT_WITH_REPORTS" = "1" ]; then
  ALL_BINARY_PACKAGES+=("${REPORT_PACKAGES[@]}")
fi

if [ "$VT_WITH_DUCKDB" = "1" ]; then
  ALL_BINARY_PACKAGES+=("${DUCKDB_PACKAGES[@]}")
fi

if [ "$VT_WITH_AIOHTTP" = "1" ]; then
  ALL_BINARY_PACKAGES+=("${AIOHTTP_PACKAGES[@]}")
fi

log "Installing curated Python dependency set via $VT_PY_INSTALLER"
py_install_binary "${ALL_BINARY_PACKAGES[@]}"

if [ "$VT_WITH_MARKET" = "1" ] && [ "$VT_WITH_AKSHARE" = "1" ]; then
  install_akshare_stack
fi

case "$VT_SOURCE" in
  pypi)
    log "Installing Vibe-Trading from PyPI: $VT_PACKAGE_SPEC"
    py_install_nodeps "$VT_PACKAGE_SPEC"
    ;;
  git)
    log "Installing Vibe-Trading from git: $VT_REPO_URL"
    if [ ! -d "$VT_APP_DIR/.git" ]; then
      rm -rf "$VT_APP_DIR"
      git clone --depth 1 "$VT_REPO_URL" "$VT_APP_DIR"
    else
      git -C "$VT_APP_DIR" fetch --depth 1 origin
      git -C "$VT_APP_DIR" pull --ff-only
    fi
    py_install_nodeps "$VT_APP_DIR"
    ;;
  *)
    echo "Unsupported VT_SOURCE=$VT_SOURCE" >&2
    exit 1
    ;;
esac

apt-get clean
rm -rf /var/lib/apt/lists/* ~/.cache/pip ~/.cache/uv

log "Done"
"$VT_VENV/bin/python" --version
"$VT_VENV/bin/python" - <<'PY'
from importlib import metadata
print('vibe-trading-ai', metadata.version('vibe-trading-ai'))
PY
EOF
}

write_wrappers() {
  log "Writing Termux wrapper commands into $TERMUX_BIN_DIR"
  mkdir -p "$TERMUX_BIN_DIR"

  cat > "$TERMUX_BIN_DIR/vibe-trading-proot" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec proot-distro login "$VT_CONTAINER" -- /bin/bash -lc '. "$VT_VENV/bin/activate" && exec vibe-trading "\$@"' bash "\$@"
EOF
  chmod +x "$TERMUX_BIN_DIR/vibe-trading-proot"

  cat > "$TERMUX_BIN_DIR/vibe-trading-shell-proot" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec proot-distro login "$VT_CONTAINER" -- /bin/bash -lc '. "$VT_VENV/bin/activate" && exec /bin/bash -i'
EOF
  chmod +x "$TERMUX_BIN_DIR/vibe-trading-shell-proot"

  if [ "$VT_WITH_API" = "1" ]; then
    cat > "$TERMUX_BIN_DIR/vibe-trading-serve-proot" <<EOF
#!/usr/bin/env bash
set -euo pipefail
PORT="\${1:-8899}"
shift || true
exec proot-distro login "$VT_CONTAINER" -- /bin/bash -lc '. "$VT_VENV/bin/activate" && exec vibe-trading serve --host 127.0.0.1 --port "\$PORT" "\$@"' bash "\$@"
EOF
    chmod +x "$TERMUX_BIN_DIR/vibe-trading-serve-proot"
  fi

  if [ "$VT_WITH_MCP" = "1" ]; then
    cat > "$TERMUX_BIN_DIR/vibe-trading-mcp-proot" <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec proot-distro login "$VT_CONTAINER" -- /bin/bash -lc '. "$VT_VENV/bin/activate" && exec vibe-trading-mcp "\$@"' bash "\$@"
EOF
    chmod +x "$TERMUX_BIN_DIR/vibe-trading-mcp-proot"
  fi
}

print_summary() {
  cat <<EOF

Install complete.

Primary command:
  $TERMUX_BIN_DIR/vibe-trading-proot

Convenience shell:
  $TERMUX_BIN_DIR/vibe-trading-shell-proot
EOF

  if [ "$VT_WITH_API" = "1" ]; then
    cat <<EOF

API command:
  $TERMUX_BIN_DIR/vibe-trading-serve-proot 8899
  Then open http://127.0.0.1:8899 on the phone.
EOF
  fi

  if [ "$VT_WITH_MCP" = "1" ]; then
    cat <<EOF

MCP command:
  $TERMUX_BIN_DIR/vibe-trading-mcp-proot
EOF
  fi

  cat <<EOF

Current options:
  VT_DISTRO=$VT_DISTRO
  VT_SOURCE=$VT_SOURCE
  VT_PY_INSTALLER=$VT_PY_INSTALLER
  VT_REFUSE_SOURCE_BUILDS=$VT_REFUSE_SOURCE_BUILDS
  VT_ALLOW_LIGHT_SDISTS=$VT_ALLOW_LIGHT_SDISTS
  VT_WITH_MARKET=$VT_WITH_MARKET
  VT_WITH_AKSHARE=$VT_WITH_AKSHARE
  VT_WITH_DOCS=$VT_WITH_DOCS
  VT_WITH_API=$VT_WITH_API
  VT_WITH_MCP=$VT_WITH_MCP
  VT_WITH_ML=$VT_WITH_ML
  VT_WITH_REPORTS=$VT_WITH_REPORTS
  VT_WITH_DUCKDB=$VT_WITH_DUCKDB
  VT_WITH_AIOHTTP=$VT_WITH_AIOHTTP

Notes:
  - Frontend/Node build is intentionally skipped for phone installs.
  - Default installer is uv.
  - VT_REFUSE_SOURCE_BUILDS=1 keeps the bulk of the install wheel-only.
  - VT_ALLOW_LIGHT_SDISTS=1 allows tiny pure-Python source-only packages where needed.
  - AKShare on Ubuntu ARM is installed with an akracer/jsonpath workaround instead of the default py-mini-racer path.
  - If you explicitly want uv/pip to attempt broader source builds, re-run with VT_REFUSE_SOURCE_BUILDS=0.
EOF
}

main() {
  ensure_termux
  install_termux_side
  ensure_container
  run_container_setup
  write_wrappers
  print_summary
}

main "$@"
