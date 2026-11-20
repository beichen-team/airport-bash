#!/bin/sh

set -eu

export LANG=C.UTF-8

VERSION="1.1.0"
SILENT="${SILENT:-0}"
HYSTERIA_USER="hysteria"

usage() {
  cat <<EOF
GuaPlus Airport Hysteria2 Uninstaller v${VERSION}

用法:
  $0 [选项]

选项:
  -s, --silent   静默卸载模式，不输出常规信息 (环境变量: SILENT=1)
  -h, --help     显示此帮助信息
EOF
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -s|--silent|-q|--quiet)
        SILENT=1; shift ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        printf 'Unknown option: %s\n' "$1" >&2
        exit 1 ;;
    esac
  done
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    printf 'Please run this script as root.\n' >&2
    exit 1
  fi
}

main() {
  parse_args "$@"
  require_root

  if [ "$SILENT" -eq 0 ] && [ -t 1 ]; then
    clear || true
    printf '* Welcome to the GuaPlus Airport hysteria2 uninstaller.\n'
    printf '* Version: %s\n\n' "$VERSION"
  fi

  # 1. Stop & remove systemd service (Debian/Ubuntu/RHEL)
  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop hysteria-server >/dev/null 2>&1 || true
    systemctl disable hysteria-server >/dev/null 2>&1 || true
    rm -f /etc/systemd/system/hysteria-server.service \
          /etc/systemd/system/hysteria-server@.service \
          /lib/systemd/system/hysteria-server.service \
          /lib/systemd/system/hysteria-server@.service >/dev/null 2>&1 || true
    systemctl daemon-reload >/dev/null 2>&1 || true
  fi

  # 2. Stop & remove OpenRC service (Alpine Linux)
  if command -v rc-service >/dev/null 2>&1; then
    rc-service hysteria-server stop >/dev/null 2>&1 || true
  fi
  if command -v rc-update >/dev/null 2>&1; then
    rc-update del hysteria-server default >/dev/null 2>&1 || true
  fi
  rm -f /etc/init.d/hysteria-server >/dev/null 2>&1 || true

  # 3. Remove binaries, configs, and logs
  rm -rf /usr/local/bin/hysteria \
         /etc/hysteria \
         /root/hy \
         /var/lib/"${HYSTERIA_USER}" \
         /var/log/hysteria-server.log \
         /var/log/hysteria-server.err >/dev/null 2>&1 || true

  if [ "$SILENT" -eq 0 ]; then
    printf 'Uninstall completed.\n'
  fi
}

main "$@"