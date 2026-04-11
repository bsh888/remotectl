#!/usr/bin/env bash
# RemoteCtl server — systemd install script
# Usage:
#   sudo ./install.sh           # install / upgrade
#   sudo ./install.sh remove    # uninstall

set -euo pipefail

SERVICE=remotectl-server
INSTALL_DIR=/opt/remotectl
UNIT_FILE=/etc/systemd/system/${SERVICE}.service
USER=ubuntu

# ── Helpers ───────────────────────────────────────────────────────────────────

log()  { echo "[install] $*"; }
die()  { echo "[error]   $*" >&2; exit 1; }

require_root() {
  [[ $EUID -eq 0 ]] || die "Run as root: sudo $0 $*"
}

# ── Detect arch ───────────────────────────────────────────────────────────────

detect_binary() {
  local arch
  arch=$(uname -m)
  case "$arch" in
    x86_64|aarch64) echo "remotectl-server" ;;
    *)       die "Unsupported architecture: $arch" ;;
  esac
}

# ── Remove ────────────────────────────────────────────────────────────────────

do_remove() {
  log "Stopping and disabling service..."
  systemctl stop  "${SERVICE}" 2>/dev/null || true
  systemctl disable "${SERVICE}" 2>/dev/null || true

  log "Removing unit file..."
  rm -f "${UNIT_FILE}"
  systemctl daemon-reload

  log "Removing binaries (config and certs are kept in ${INSTALL_DIR})..."
  rm -f "${INSTALL_DIR}/remotectl-server"

  log "Done. Config, certs, and static files in ${INSTALL_DIR} were preserved."
  log "To fully remove: rm -rf ${INSTALL_DIR}"
}

# ── Install ───────────────────────────────────────────────────────────────────

do_install() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local bin_name
  bin_name=$(detect_binary)
  local bin_src="${script_dir}/${bin_name}"

  [[ -f "$bin_src" ]] || die "Binary not found: ${bin_src}"

  # ── Verify user exists ──────────────────────────────────────────────────────
  id -u "${USER}" &>/dev/null || die "User '${USER}' does not exist on this system."

  # ── Create install dir ──────────────────────────────────────────────────────
  log "Creating ${INSTALL_DIR}..."
  mkdir -p "${INSTALL_DIR}/certs" "${INSTALL_DIR}/static"

  # ── Copy binary ─────────────────────────────────────────────────────────────
  log "Installing remotectl-server → ${INSTALL_DIR}/remotectl-server"
  install -m 0755 "${bin_src}" "${INSTALL_DIR}/remotectl-server"

  # ── Copy static files ───────────────────────────────────────────────────────
  if [[ -d "${script_dir}/static" ]] && [[ -n "$(ls -A "${script_dir}/static" 2>/dev/null)" ]]; then
    log "Copying static files..."
    cp -r "${script_dir}/static/." "${INSTALL_DIR}/static/"
  fi

  # ── Copy default config if not present ──────────────────────────────────────
  if [[ ! -f "${INSTALL_DIR}/server.yaml" ]]; then
    if [[ -f "${script_dir}/server.yaml.example" ]]; then
      log "Copying server.yaml.example → ${INSTALL_DIR}/server.yaml"
      cp "${script_dir}/server.yaml.example" "${INSTALL_DIR}/server.yaml"
      log "⚠  Edit ${INSTALL_DIR}/server.yaml before starting the service!"
    fi
  else
    log "Existing server.yaml kept (not overwritten)."
  fi

  # ── Copy certs if not present ────────────────────────────────────────────────
  for f in server.crt server.key; do
    if [[ ! -f "${INSTALL_DIR}/certs/${f}" ]]; then
      if [[ -f "${script_dir}/certs/${f}" ]]; then
        log "Copying certs/${f}..."
        install -m 0640 "${script_dir}/certs/${f}" "${INSTALL_DIR}/certs/${f}"
      else
        log "⚠  certs/${f} not found — place TLS cert/key in ${INSTALL_DIR}/certs/"
      fi
    else
      log "Existing certs/${f} kept."
    fi
  done

  # ── Fix ownership ────────────────────────────────────────────────────────────
  chown -R "${USER}:${USER}" "${INSTALL_DIR}"
  chmod 0750 "${INSTALL_DIR}/certs"

  # ── Install systemd unit ─────────────────────────────────────────────────────
  log "Installing unit file → ${UNIT_FILE}"
  install -m 0644 "${script_dir}/remotectl-server.service" "${UNIT_FILE}"
  systemctl daemon-reload
  systemctl enable "${SERVICE}"

  # ── Start / restart ──────────────────────────────────────────────────────────
  if systemctl is-active --quiet "${SERVICE}"; then
    log "Restarting ${SERVICE}..."
    systemctl restart "${SERVICE}"
  else
    log "Starting ${SERVICE}..."
    systemctl start "${SERVICE}"
  fi

  systemctl status "${SERVICE}" --no-pager -l || true

  log ""
  log "Installation complete."
  log "  Config : ${INSTALL_DIR}/server.yaml"
  log "  Certs  : ${INSTALL_DIR}/certs/"
  log "  Logs   : journalctl -u ${SERVICE} -f"
}

# ── Main ──────────────────────────────────────────────────────────────────────

require_root

case "${1:-install}" in
  install|upgrade) do_install ;;
  remove|uninstall) do_remove ;;
  *) die "Usage: sudo $0 [install|remove]" ;;
esac
