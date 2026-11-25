#!/bin/sh

set -eu

export LANG=C.UTF-8

# --- Global Variables ---
VERSION="2.3.0"
SYSTEMD_SERVICES_DIR="/etc/systemd/system"
OPENRC_SERVICES_DIR="/etc/init.d"

# Hysteria2 路径常量
HY2_CONFIG_DIR="/etc/hysteria"
HY2_BIN="/usr/local/bin/hysteria"
HY2_USER="hysteria"
HY2_HOME_DIR="/var/lib/${HY2_USER}"

# VLESS (Xray + Gateway) 路径常量
VLESS_CONFIG_DIR="/etc/xray-gate"
XRAY_BIN="/usr/local/bin/xray"
XRAY_ASSET_DIR="/usr/local/share/xray"
GATEWAY_BIN="/usr/local/bin/airport-gateway"
VLESS_USER="xraygate"
VLESS_HOME_DIR="/var/lib/${VLESS_USER}"

# 证书自动同步常量
CERT_SYNC_BIN="/usr/local/bin/guaplus-cert-sync.sh"
CERT_SYNC_DIR="/etc/guaplus/cert-sync.d"
GUAPLUS_ETC_DIR="/etc/guaplus"
OPENRC_DAILY_SYNC="/etc/periodic/daily/guaplus-cert-sync"

TARGET="${TARGET:-}"
AUTO_YES="${AUTO_YES:-0}"
OS_FAMILY="unknown"
INIT_SYSTEM="unknown"

# --- Helper Functions ---

log_info() {
  printf '\033[32m[INFO]\033[0m %s\n' "$1" >&2
}

log_warn() {
  printf '\033[33m[WARN]\033[0m %s\n' "$1" >&2
}

log_error() {
  printf '\033[31m[ERROR]\033[0m %s\n' "$1" >&2
  exit 1
}

print_banner() {
  printf '\n'
  printf '\033[31m╭────────────────────────────────────────────────────────╮\033[0m\n'
  printf '\033[31m│\033[0m  \033[1;97mGuaPlus Airport Unified Uninstaller\033[0m  \033[1;33mv%-14s\033[0m \033[31m│\033[0m\n' "${VERSION}"
  printf '\033[31m│\033[0m  \033[2mComplete Cleanup · Hysteria2 / VLESS / Cert Sync\033[0m     \033[31m│\033[0m\n'
  printf '\033[31m├────────────────────────────────────────────────────────┤\033[0m\n'
  printf '\033[31m│\033[0m  \033[33mOS:\033[0m %-19s \033[33mInit:\033[0m %-22s \033[31m│\033[0m\n' "${OS_FAMILY}" "${INIT_SYSTEM}"
  printf '\033[31m╰────────────────────────────────────────────────────────╯\033[0m\n\n'
}

usage() {
  cat <<EOF
GuaPlus Airport Unified Uninstaller v${VERSION}

用法:
  $0 [选项]

选项:
  -t, --type <TARGET>    卸载目标: all|hy2|hysteria2|vless (默认交互选择)
  -y, --yes              跳过二次确认直接卸载 (环境变量: AUTO_YES=1)
  -h, --help             显示此帮助信息
EOF
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -t|--type|--protocol)
        [ $# -ge 2 ] || log_error "选项 $1 需要参数"
        TARGET="$2"; shift 2 ;;
      -y|--yes|--force)
        AUTO_YES="1"; shift ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        log_error "未知参数: $1 (使用 -h 查看帮助)" ;;
    esac
  done
}

require_root() {
  [ "$(id -u)" -eq 0 ] || log_error "请使用 root 运行"
}

detect_env() {
  if [ -f /etc/os-release ]; then
    os_info=$(tr '[:upper:]' '[:lower:]' < /etc/os-release)
    case "$os_info" in
      *alpine*) OS_FAMILY="alpine" ;;
      *debian*|*ubuntu*) OS_FAMILY="debian" ;;
      *centos*|*"red hat"*|*rhel*|*alma*|*rocky*|*fedora*|*amazon*) OS_FAMILY="rhel" ;;
    esac
  fi

  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    INIT_SYSTEM="systemd"
  elif command -v rc-service >/dev/null 2>&1 && [ -d "${OPENRC_SERVICES_DIR}" ]; then
    INIT_SYSTEM="openrc"
  fi
}

prompt_read() {
  prompt_text="$1"
  prompt_variable="$2"

  printf '%s' "$prompt_text" >&2

  if [ -r /dev/tty ]; then
    IFS= read -r "$prompt_variable" </dev/tty || log_error "无法从终端读取输入"
  elif [ -t 0 ]; then
    IFS= read -r "$prompt_variable" || log_error "无法读取输入"
  else
    log_error "当前无可用交互终端，请传入 --type 与 --yes 参数执行非交互卸载"
  fi
}

is_hy2_present() {
  [ -e "${HY2_BIN}" ] || [ -d "${HY2_CONFIG_DIR}" ] \
    || [ -f "${SYSTEMD_SERVICES_DIR}/hysteria-server.service" ] \
    || [ -f "${OPENRC_SERVICES_DIR}/hysteria-server" ] \
    || id "${HY2_USER}" >/dev/null 2>&1
}

is_vless_present() {
  [ -e "${XRAY_BIN}" ] || [ -e "${GATEWAY_BIN}" ] || [ -d "${VLESS_CONFIG_DIR}" ] \
    || [ -f "${SYSTEMD_SERVICES_DIR}/xray-backend.service" ] \
    || [ -f "${SYSTEMD_SERVICES_DIR}/airport-gateway.service" ] \
    || [ -f "${OPENRC_SERVICES_DIR}/xray-backend" ] \
    || [ -f "${OPENRC_SERVICES_DIR}/airport-gateway" ] \
    || id "${VLESS_USER}" >/dev/null 2>&1
}

resolve_target() {
  if [ -z "${TARGET}" ]; then
    hy2_mark="未检测到"
    vless_mark="未检测到"
    is_hy2_present && hy2_mark="已安装"
    is_vless_present && vless_mark="已安装"

    printf '请选择要卸载的组件:\n'
    printf '  1) 全部卸载 (Hysteria2 + VLESS + 证书自动同步) [默认]\n'
    printf '  2) 仅卸载 Hysteria2 (%s)\n' "${hy2_mark}"
    printf '  3) 仅卸载 VLESS (Xray + Gateway) (%s)\n' "${vless_mark}"
    prompt_read "请输入选项 [1-3]: " t_ans
    TARGET="${t_ans:-1}"
  fi

  case "$(printf '%s' "${TARGET}" | tr '[:upper:]' '[:lower:]')" in
    1|all)
      TARGET="all" ;;
    2|hy2|hysteria|hysteria2)
      TARGET="hysteria2" ;;
    3|vless|xray|ws)
      TARGET="vless" ;;
    *)
      log_error "不支持的卸载目标: ${TARGET} (可选: all / hysteria2 / vless)" ;;
  esac
}

confirm_uninstall() {
  [ "${AUTO_YES}" = "1" ] && return 0

  printf '\n\033[33m即将执行完全卸载 (目标: %s)，将永久删除对应的服务、程序、配置文件、证书、机器指纹及运行用户。\033[0m\n' "${TARGET}" >&2
  prompt_read "确认继续卸载？[y/N]: " c_ans
  case "$(printf '%s' "${c_ans}" | tr '[:upper:]' '[:lower:]')" in
    y|yes) return 0 ;;
    *)
      log_info "已取消卸载"
      exit 0
      ;;
  esac
}

stop_and_remove_service() {
  svc="$1"
  case "${INIT_SYSTEM}" in
    systemd)
      systemctl stop "${svc}.service" >/dev/null 2>&1 || true
      systemctl disable "${svc}.service" >/dev/null 2>&1 || true
      rm -f "${SYSTEMD_SERVICES_DIR}/${svc}.service"
      ;;
    openrc)
      rc-service "${svc}" stop >/dev/null 2>&1 || true
      rc-update del "${svc}" default >/dev/null 2>&1 || true
      rm -f "${OPENRC_SERVICES_DIR}/${svc}" "/run/${svc}.pid"
      ;;
    *)
      rm -f "${SYSTEMD_SERVICES_DIR}/${svc}.service" "${OPENRC_SERVICES_DIR}/${svc}" "/run/${svc}.pid"
      ;;
  esac
}

remove_system_user() {
  u_name="$1"
  u_home="$2"

  if id "${u_name}" >/dev/null 2>&1; then
    log_info "删除系统用户: ${u_name}"
    if command -v userdel >/dev/null 2>&1; then
      userdel -r "${u_name}" >/dev/null 2>&1 || userdel "${u_name}" >/dev/null 2>&1 || true
    elif command -v deluser >/dev/null 2>&1; then
      deluser "${u_name}" >/dev/null 2>&1 || true
    fi
  fi

  if command -v groupdel >/dev/null 2>&1; then
    groupdel "${u_name}" >/dev/null 2>&1 || true
  elif command -v delgroup >/dev/null 2>&1; then
    delgroup "${u_name}" >/dev/null 2>&1 || true
  fi

  if [ -n "${u_home}" ] && [ -e "${u_home}" ]; then
    rm -rf "${u_home}"
  fi
}

has_remaining_sync_confs() {
  [ -d "${CERT_SYNC_DIR}" ] || return 1
  for f in "${CERT_SYNC_DIR}"/*.conf; do
    [ -f "$f" ] && return 0
  done
  return 1
}

remove_cert_sync_infra() {
  log_info "清理证书自动同步脚本与定时任务..."
  case "${INIT_SYSTEM}" in
    systemd)
      systemctl stop guaplus-cert-sync.timer >/dev/null 2>&1 || true
      systemctl disable guaplus-cert-sync.timer >/dev/null 2>&1 || true
      systemctl stop guaplus-cert-sync.service >/dev/null 2>&1 || true
      systemctl disable guaplus-cert-sync.service >/dev/null 2>&1 || true
      rm -f "${SYSTEMD_SERVICES_DIR}/guaplus-cert-sync.timer" \
            "${SYSTEMD_SERVICES_DIR}/guaplus-cert-sync.service"
      ;;
    openrc)
      rm -f "${OPENRC_DAILY_SYNC}"
      ;;
    *)
      rm -f "${SYSTEMD_SERVICES_DIR}/guaplus-cert-sync.timer" \
            "${SYSTEMD_SERVICES_DIR}/guaplus-cert-sync.service" \
            "${OPENRC_DAILY_SYNC}"
      ;;
  esac

  rm -f "${CERT_SYNC_BIN}"
  rm -rf "${CERT_SYNC_DIR}"
  rmdir "${GUAPLUS_ETC_DIR}" >/dev/null 2>&1 || true
}

reload_init_system() {
  if [ "${INIT_SYSTEM}" = "systemd" ]; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl reset-failed >/dev/null 2>&1 || true
  fi
}

# ==========================================
# Uninstall Flows
# ==========================================

uninstall_hysteria2() {
  log_info "开始卸载 Hysteria2..."
  stop_and_remove_service "hysteria-server"

  rm -f "${HY2_BIN}" \
        "/var/log/hysteria-server.log" \
        "/var/log/hysteria-server.err" \
        "/tmp/hysteria" \
        "${CERT_SYNC_DIR}/hysteria2.conf"

  rm -rf "${HY2_CONFIG_DIR}"
  remove_system_user "${HY2_USER}" "${HY2_HOME_DIR}"
  log_info "Hysteria2 已清理完成"
}

uninstall_vless() {
  log_info "开始卸载 VLESS (Xray + Gateway)..."
  # 先停入口网关，再停本地 Xray 后端
  stop_and_remove_service "airport-gateway"
  stop_and_remove_service "xray-backend"

  rm -f "${GATEWAY_BIN}" \
        "${XRAY_BIN}" \
        "/var/log/airport-gateway.log" \
        "/var/log/airport-gateway.err" \
        "/var/log/xray-backend.log" \
        "/var/log/xray-backend.err" \
        "/tmp/airport-gateway" \
        "${CERT_SYNC_DIR}/vless.conf"

  rm -rf "${VLESS_CONFIG_DIR}" "${XRAY_ASSET_DIR}"
  remove_system_user "${VLESS_USER}" "${VLESS_HOME_DIR}"
  log_info "VLESS (Xray + Gateway) 已清理完成"
}

main() {
  parse_args "$@"
  require_root
  detect_env
  print_banner
  resolve_target
  confirm_uninstall

  case "${TARGET}" in
    all)
      uninstall_hysteria2
      uninstall_vless
      remove_cert_sync_infra
      ;;
    hysteria2)
      uninstall_hysteria2
      if ! has_remaining_sync_confs; then
        remove_cert_sync_infra
      else
        log_info "检测到本机仍有其他协议在运行，保留共享的证书自动同步组件"
      fi
      ;;
    vless)
      uninstall_vless
      if ! has_remaining_sync_confs; then
        remove_cert_sync_infra
      else
        log_info "检测到本机仍有其他协议在运行，保留共享的证书自动同步组件"
      fi
      ;;
  esac

  reload_init_system

  printf '\n'
  printf '\033[32m-------------------------------------\033[0m\n'
  printf '\033[1;32m✅ 卸载完成! (目标: %s)\033[0m\n' "${TARGET}"
  printf '\033[32m-------------------------------------\033[0m\n'
  printf '说明: 未卸载系统基础工具 (curl/jq/openssl/tar/unzip)。\n'
  printf '如需从机场面板彻底移除节点记录，请在面板后台手动删除。\n'
  printf '\033[32m-------------------------------------\033[0m\n'
}

main "$@"