#!/bin/sh

set -eu

export LANG=C.UTF-8

# --- Global Variables ---
VERSION="2.4.0"
SYSTEMD_SERVICES_DIR="/etc/systemd/system"
OPENRC_SERVICES_DIR="/etc/init.d"

# Hysteria2 常量
HY2_CONFIG_DIR="/etc/hysteria"
HY2_BIN="/usr/local/bin/hysteria"
HY2_USER="hysteria"
HY2_HOME_DIR="/var/lib/${HY2_USER}"
HY2_CERT_PATH="${HY2_CONFIG_DIR}/cert.crt"
HY2_KEY_PATH="${HY2_CONFIG_DIR}/private.key"
HY2_CONFIG_PATH="${HY2_CONFIG_DIR}/config.yaml"
HY2_FP_PATH="${HY2_CONFIG_DIR}/fingerprint.sha256"
HY2_REPO_API="https://api.github.com/repos/apernet/hysteria"
HY2_DL_BASE="https://github.com/apernet/hysteria/releases/download"

# VLESS (Xray + Gateway) 常量
VLESS_CONFIG_DIR="/etc/xray-gate"
XRAY_BIN="/usr/local/bin/xray"
XRAY_ASSET_DIR="/usr/local/share/xray"
GATEWAY_BIN="/usr/local/bin/airport-gateway"
VLESS_USER="xraygate"
VLESS_HOME_DIR="/var/lib/${VLESS_USER}"
VLESS_CERT_PATH="${VLESS_CONFIG_DIR}/cert.crt"
VLESS_KEY_PATH="${VLESS_CONFIG_DIR}/private.key"
VLESS_FP_PATH="${VLESS_CONFIG_DIR}/fingerprint.sha256"
XRAY_CONFIG_PATH="${VLESS_CONFIG_DIR}/xray.json"
GATEWAY_ENV_PATH="${VLESS_CONFIG_DIR}/gateway.env"
XRAY_INTERNAL_PORT="${XRAY_INTERNAL_PORT:-18086}"
XRAY_WS_PATH="${XRAY_WS_PATH:-/ws}"
PATH_PREFIX="${PATH_PREFIX:-/w/}"
XRAY_REPO_API="https://api.github.com/repos/XTLS/Xray-core"
XRAY_DL_BASE="https://github.com/XTLS/Xray-core/releases/download"

# 证书自动同步常量
CERT_SYNC_BIN="/usr/local/bin/guaplus-cert-sync.sh"
CERT_SYNC_DIR="/etc/guaplus/cert-sync.d"

# 通用可配置参数（支持环境变量或命令行传入）
PROTOCOL="${PROTOCOL:-}"
PANEL_BASE="${PANEL_BASE:-}"
PANEL_CERT_API="${PANEL_CERT_API:-}"
PANEL_GATEWAY_API="${PANEL_GATEWAY_API:-}"
INSTALL_KEY="${INSTALL_KEY:-}"
NODE_NAME="${NODE_NAME:-}"
DOMAIN="${DOMAIN:-}"
LISTEN_PORT="${LISTEN_PORT:-3389}"
SNI="${SNI:-}"
INSECURE="${INSECURE:-0}"
AUTO_DNS="${AUTO_DNS:-}"

AUTO_DNS_BOOL="true"
OS_FAMILY=""
INIT_SYSTEM=""
PM_UPDATE=""
PM_INSTALL=""
PANEL_INSTALL_API=""
PANEL_VERIFY_API=""

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
  printf '\033[36m╭────────────────────────────────────────────────────────╮\033[0m\n'
  printf '\033[36m│\033[0m  \033[1;97mGuaPlus Airport Unified Installer\033[0m  \033[1;32mv%-16s\033[0m \033[36m│\033[0m\n' "${VERSION}"
  printf '\033[36m│\033[0m  \033[2mHysteria2 & VLESS · Zero-Token Cert & Gateway Sync\033[0m  \033[36m│\033[0m\n'
  printf '\033[36m├────────────────────────────────────────────────────────┤\033[0m\n'
  printf '\033[36m│\033[0m  \033[33mOS:\033[0m %-19s \033[33mInit:\033[0m %-22s \033[36m│\033[0m\n' "${OS_FAMILY}" "${INIT_SYSTEM}"
  printf '\033[36m╰────────────────────────────────────────────────────────╯\033[0m\n\n'
}

usage() {
  cat <<EOF
GuaPlus Airport Unified Installer v${VERSION} (Hysteria2 & VLESS)

用法:
  $0 [选项]

选项:
  -t, --type <PROTO>         协议类型: hy2|hysteria2|vless (环境变量: PROTOCOL)
  -u, --url <URL>            机场面板地址 (环境变量: PANEL_BASE)
  -k, --key <KEY>            安装密钥 (环境变量: INSTALL_KEY)
  -n, --name <NAME>          节点名称 (环境变量: NODE_NAME)
  -d, --domain <DOMAIN>      节点域名 (环境变量: DOMAIN)
  -p, --port <PORT>          对外监听端口，默认 3389 (环境变量: LISTEN_PORT)
      --sni <SNI>            TLS SNI，默认与节点域名一致 (环境变量: SNI)
      --insecure <1|0>       是否跳过证书校验，默认 0 (环境变量: INSECURE)
      --prefix <PREFIX>      [仅 VLESS] 鉴权路径前缀，默认 /w/ (环境变量: PATH_PREFIX)
      --auto-dns <1|0>       是否自动解析域名 (Cloudflare)，默认 1 (环境变量: AUTO_DNS)
      --cert-api <URL>       面板证书下载接口，默认 <PANEL_BASE>/api/v1/cert/download
      --gateway-api <URL>    [仅 VLESS] airport-gateway 预下载接口，默认 <PANEL_BASE>/api/v1/gateway/download
  -h, --help                 显示此帮助信息
EOF
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -t|--type|--protocol)
        [ $# -ge 2 ] || log_error "选项 $1 需要参数"
        PROTOCOL="$2"; shift 2 ;;
      -u|--url)
        [ $# -ge 2 ] || log_error "选项 $1 需要参数"
        PANEL_BASE="$2"; shift 2 ;;
      -k|--key)
        [ $# -ge 2 ] || log_error "选项 $1 需要参数"
        INSTALL_KEY="$2"; shift 2 ;;
      -n|--name)
        [ $# -ge 2 ] || log_error "选项 $1 需要参数"
        NODE_NAME="$2"; shift 2 ;;
      -d|--domain)
        [ $# -ge 2 ] || log_error "选项 $1 需要参数"
        DOMAIN="$2"; shift 2 ;;
      -p|--port)
        [ $# -ge 2 ] || log_error "选项 $1 需要参数"
        LISTEN_PORT="$2"; shift 2 ;;
      --sni)
        [ $# -ge 2 ] || log_error "选项 $1 需要参数"
        SNI="$2"; shift 2 ;;
      --insecure)
        [ $# -ge 2 ] || log_error "选项 $1 需要参数"
        INSECURE="$2"; shift 2 ;;
      --prefix)
        [ $# -ge 2 ] || log_error "选项 $1 需要参数"
        PATH_PREFIX="$2"; shift 2 ;;
      --auto-dns)
        [ $# -ge 2 ] || log_error "选项 $1 需要参数"
        AUTO_DNS="$2"; shift 2 ;;
      --cert-api)
        [ $# -ge 2 ] || log_error "选项 $1 需要参数"
        PANEL_CERT_API="$2"; shift 2 ;;
      --gateway-api)
        [ $# -ge 2 ] || log_error "选项 $1 需要参数"
        PANEL_GATEWAY_API="$2"; shift 2 ;;
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

sh_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

detect_os_pm() {
  [ -f /etc/os-release ] || log_error "无法检测操作系统 (/etc/os-release 不存在)"
  os_info=$(tr '[:upper:]' '[:lower:]' < /etc/os-release)

  case "$os_info" in
    *alpine*)
      OS_FAMILY="alpine"
      PM_UPDATE="apk update"
      PM_INSTALL="apk add --no-cache"
      ;;
    *debian*|*ubuntu*)
      OS_FAMILY="debian"
      export DEBIAN_FRONTEND=noninteractive
      PM_UPDATE="apt-get update -y"
      PM_INSTALL="apt-get install -y"
      ;;
    *centos*|*"red hat"*|*rhel*|*alma*|*rocky*|*fedora*|*amazon*)
      OS_FAMILY="rhel"
      if command -v dnf >/dev/null 2>&1; then
        PM_UPDATE="dnf -y makecache"
        PM_INSTALL="dnf -y install"
      else
        PM_UPDATE="yum -y makecache"
        PM_INSTALL="yum -y install"
      fi
      ;;
    *)
      pretty=$(grep -i '^PRETTY_NAME=' /etc/os-release | cut -d '"' -f2 || echo "unknown")
      log_error "不支持的系统: ${pretty}"
      ;;
  esac
}

detect_init_system() {
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    INIT_SYSTEM="systemd"
  elif command -v rc-service >/dev/null 2>&1 && [ -d "${OPENRC_SERVICES_DIR}" ]; then
    INIT_SYSTEM="openrc"
  else
    log_error "未检测到受支持的服务管理器 (systemd 或 OpenRC)"
  fi
}

ensure_cmds() {
  missing=""
  for c in "$@"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      missing="${missing} ${c}"
    fi
  done

  if [ "$OS_FAMILY" = "alpine" ] && [ ! -f /etc/ssl/certs/ca-certificates.crt ]; then
    missing="${missing} ca-certificates"
  fi

  [ -z "$missing" ] && return 0

  log_info "安装所需依赖:${missing}"
  # shellcheck disable=SC2086
  $PM_UPDATE || log_error "更新软件包索引失败，请检查网络和软件源"
  # shellcheck disable=SC2086
  $PM_INSTALL $missing || log_error "依赖安装失败，请检查系统包管理器"
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7*|armv6*) echo "arm" ;;
    i386|i686) echo "386" ;;
    *) log_error "不支持的 CPU 架构: $(uname -m)" ;;
  esac
}

rand_port() {
  hex=$(openssl rand -hex 2)
  num=$((0x${hex}))
  echo $((20000 + (num % 40001)))
}

get_public_ip() {
  ip=$(curl -fsS --max-time 10 https://whatismyip.akamai.com 2>/dev/null \
    || curl -fsS --max-time 10 https://ipecho.net/plain 2>/dev/null || true)
  ip=$(printf '%s' "$ip" | tr -d '\r\n ')
  if [ -z "$ip" ] && [ "$AUTO_DNS_BOOL" = "true" ]; then
    log_error "开启自动解析域名时获取公网 IP 失败"
  fi
  echo "$ip"
}

ensure_system_user() {
  u_name="$1"
  u_home="$2"
  if ! id "${u_name}" >/dev/null 2>&1; then
    if command -v useradd >/dev/null 2>&1; then
      useradd -r -m -d "${u_home}" -s /sbin/nologin "${u_name}"
    elif command -v adduser >/dev/null 2>&1; then
      addgroup -S "${u_name}" >/dev/null 2>&1 || true
      adduser -S -D -h "${u_home}" -G "${u_name}" -s /sbin/nologin "${u_name}"
      mkdir -p "${u_home}"
      chown "${u_name}:${u_name}" "${u_home}"
    else
      log_error "未找到 useradd 或 adduser 命令"
    fi
  fi
}

# 与证书解耦的持久化机器指纹（避免多节点共享泛域名证书导致指纹冲突）
get_machine_fingerprint() {
  fp_dir="$1"
  fp_file="$2"
  fp_proto="$3"

  mkdir -p "${fp_dir}"
  if [ -s "${fp_file}" ]; then
    tr -d '\r\n ' < "${fp_file}"
    printf '\n'
    return
  fi

  mid=""
  if [ -s /etc/machine-id ]; then
    mid=$(tr -d '\r\n ' < /etc/machine-id)
  elif [ -s /var/lib/dbus/machine-id ]; then
    mid=$(tr -d '\r\n ' < /var/lib/dbus/machine-id)
  fi

  if [ -n "${mid}" ]; then
    fp=$(printf '%s:%s' "${mid}" "${fp_proto}" | openssl dgst -sha256 | awk '{print $NF}' | tr '[:upper:]' '[:lower:]')
  else
    fp=$(openssl rand -hex 32 | tr '[:upper:]' '[:lower:]')
  fi

  printf '%s\n' "${fp}" > "${fp_file}"
  chmod 644 "${fp_file}"
  printf '%s\n' "${fp}"
}

# --- Certificate Sync (Zero-Token Panel Download) ---

validate_cert_pair() {
  v_cert="$1"
  v_key="$2"

  [ -s "${v_cert}" ] && [ -s "${v_key}" ] || return 1
  openssl x509 -in "${v_cert}" -noout >/dev/null 2>&1 || return 1
  openssl pkey -in "${v_key}" -noout >/dev/null 2>&1 || return 1

  v_pub_cert=$(openssl x509 -in "${v_cert}" -pubkey -noout 2>/dev/null | openssl sha256 | awk '{print $NF}')
  v_pub_key=$(openssl pkey -in "${v_key}" -pubout 2>/dev/null | openssl sha256 | awk '{print $NF}')
  [ -n "${v_pub_cert}" ] && [ "${v_pub_cert}" = "${v_pub_key}" ]
}

install_cert_from_panel() {
  ic_dir="$1"
  ic_cert="$2"
  ic_key="$3"
  ic_user="$4"
  ic_token="$5"

  mkdir -p "${ic_dir}"

  log_info "向面板申请证书临时下载链接 (${PANEL_CERT_API})..."
  ic_resp=$(curl -fsSL --max-time 20 -G "${PANEL_CERT_API}" \
    -H "Authorization: ${ic_token}" \
    --data-urlencode "domain=${DOMAIN}") \
    || log_error "请求面板证书接口失败: ${PANEL_CERT_API}"

  ic_url=$(printf '%s' "${ic_resp}" | jq -r '.data.download_url // empty' 2>/dev/null || true)
  [ -n "${ic_url}" ] || log_error "面板未返回有效的 download_url: ${ic_resp}"

  ic_tmp=$(mktemp -d)
  chmod 700 "${ic_tmp}"
  mkdir -p "${ic_tmp}/extract"

  log_info "通过临时下载链接拉取证书包..."
  if ! curl -fsSL --max-time 30 --retry 3 --retry-delay 2 -o "${ic_tmp}/cert.tar.gz" "${ic_url}"; then
    rm -rf "${ic_tmp}"
    log_error "下载证书包失败"
  fi

  if ! tar -xzf "${ic_tmp}/cert.tar.gz" -C "${ic_tmp}/extract" 2>/dev/null; then
    rm -rf "${ic_tmp}"
    log_error "解压证书包失败，请确认附件为标准 .tar.gz 格式"
  fi

  ic_found_cert=""
  ic_found_key=""
  for f in cert.crt fullchain.pem fullchain.cer cert.pem; do
    ic_found_cert=$(find "${ic_tmp}/extract" -type f -name "$f" | head -n 1 || true)
    [ -n "${ic_found_cert}" ] && break
  done
  for f in private.key privkey.pem key.pem; do
    ic_found_key=$(find "${ic_tmp}/extract" -type f -name "$f" | head -n 1 || true)
    [ -n "${ic_found_key}" ] && break
  done

  if [ -z "${ic_found_cert}" ] || [ -z "${ic_found_key}" ]; then
    rm -rf "${ic_tmp}"
    log_error "证书包中未找到证书/私钥文件 (期望 cert.crt + private.key 或 fullchain.pem + privkey.pem)"
  fi

  tr -d '\r' < "${ic_found_cert}" > "${ic_tmp}/cert.clean"
  tr -d '\r' < "${ic_found_key}" > "${ic_tmp}/key.clean"

  if ! validate_cert_pair "${ic_tmp}/cert.clean" "${ic_tmp}/key.clean"; then
    rm -rf "${ic_tmp}"
    log_error "下载的证书与私钥校验失败（格式错误或公私钥不匹配）"
  fi

  ic_end=$(openssl x509 -in "${ic_tmp}/cert.clean" -noout -enddate 2>/dev/null | sed 's/^notAfter=//')
  if ! openssl x509 -in "${ic_tmp}/cert.clean" -noout -checkend 0 >/dev/null 2>&1; then
    log_warn "注意：拉取到的证书已过期 (${ic_end})"
  else
    log_info "证书校验通过，到期时间: ${ic_end}"
  fi

  mv -f "${ic_tmp}/cert.clean" "${ic_cert}"
  mv -f "${ic_tmp}/key.clean" "${ic_key}"
  rm -rf "${ic_tmp}"

  chown "root:${ic_user}" "${ic_cert}" "${ic_key}"
  chmod 640 "${ic_cert}" "${ic_key}"
}

install_cert_auto_sync() {
  cs_proto="$1"
  cs_cert="$2"
  cs_key="$3"
  cs_user="$4"
  cs_svc="$5"
  cs_fp="$6"

  mkdir -p "${CERT_SYNC_DIR}"

  cat > "${CERT_SYNC_DIR}/${cs_proto}.conf" <<EOF
PROTOCOL=$(sh_quote "${cs_proto}")
DOMAIN=$(sh_quote "${DOMAIN}")
CERT_PATH=$(sh_quote "${cs_cert}")
KEY_PATH=$(sh_quote "${cs_key}")
SVC_NAME=$(sh_quote "${cs_svc}")
SVC_USER=$(sh_quote "${cs_user}")
PANEL_INSTALL_API=$(sh_quote "${PANEL_INSTALL_API}")
PANEL_CERT_API=$(sh_quote "${PANEL_CERT_API}")
INSTALL_KEY=$(sh_quote "${INSTALL_KEY}")
FINGERPRINT=$(sh_quote "${cs_fp}")
EOF
  chmod 600 "${CERT_SYNC_DIR}/${cs_proto}.conf"

  cat > "${CERT_SYNC_BIN}" <<'EOF'
#!/bin/sh

set -eu

SYNC_DIR="/etc/guaplus/cert-sync.d"

restart_svc() {
  rs_svc="$1"
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    systemctl restart "${rs_svc}" >/dev/null 2>&1 || true
  elif command -v rc-service >/dev/null 2>&1; then
    rc-service "${rs_svc}" restart >/dev/null 2>&1 || true
  fi
}

get_cert_sha256() {
  [ -s "$1" ] || return 0
  openssl x509 -in "$1" -noout -fingerprint -sha256 2>/dev/null \
    | awk -F= '{print $2}' | tr -d ':' | tr '[:upper:]' '[:lower:]' || true
}

validate_pair() {
  vp_cert="$1"
  vp_key="$2"
  [ -s "${vp_cert}" ] && [ -s "${vp_key}" ] || return 1
  openssl x509 -in "${vp_cert}" -noout >/dev/null 2>&1 || return 1
  openssl pkey -in "${vp_key}" -noout >/dev/null 2>&1 || return 1
  vp_pc=$(openssl x509 -in "${vp_cert}" -pubkey -noout 2>/dev/null | openssl sha256 | awk '{print $NF}')
  vp_pk=$(openssl pkey -in "${vp_key}" -pubout 2>/dev/null | openssl sha256 | awk '{print $NF}')
  [ -n "${vp_pc}" ] && [ "${vp_pc}" = "${vp_pk}" ]
}

for conf in "${SYNC_DIR}"/*.conf; do
  [ -f "${conf}" ] || continue

  PROTOCOL=""
  DOMAIN=""
  CERT_PATH=""
  KEY_PATH=""
  SVC_NAME=""
  SVC_USER=""
  PANEL_INSTALL_API=""
  PANEL_CERT_API=""
  INSTALL_KEY=""
  FINGERPRINT=""

  # shellcheck disable=SC1090
  . "${conf}"

  [ -n "${PANEL_INSTALL_API}" ] && [ -n "${PANEL_CERT_API}" ] && [ -n "${INSTALL_KEY}" ] && [ -n "${FINGERPRINT}" ] || continue

  cur_sha=""
  if validate_pair "${CERT_PATH}" "${KEY_PATH}"; then
    cur_sha=$(get_cert_sha256 "${CERT_PATH}")
  fi

  token=$(curl -fsSL --max-time 15 -G "${PANEL_INSTALL_API}" \
    --data-urlencode "key=${INSTALL_KEY}" \
    --data-urlencode "fingerprint=${FINGERPRINT}" 2>/dev/null | jq -r '.data.token // empty' 2>/dev/null | tr -d '\r\n' || true)
  [ -n "${token}" ] || continue

  resp=$(curl -fsSL --max-time 20 -G "${PANEL_CERT_API}" \
    -H "Authorization: ${token}" \
    --data-urlencode "domain=${DOMAIN}" \
    --data-urlencode "sha256=${cur_sha}" 2>/dev/null || true)
  [ -n "${resp}" ] || continue

  up_to_date=$(printf '%s' "${resp}" | jq -r '.data.up_to_date // false' 2>/dev/null || echo "false")
  remote_sha=$(printf '%s' "${resp}" | jq -r '.data.sha256 // empty' 2>/dev/null | tr -d ':' | tr '[:upper:]' '[:lower:]' || true)
  dl_url=$(printf '%s' "${resp}" | jq -r '.data.download_url // empty' 2>/dev/null || true)

  if [ "${up_to_date}" = "true" ] && [ -n "${cur_sha}" ]; then
    continue
  fi
  if [ -n "${cur_sha}" ] && [ -n "${remote_sha}" ] && [ "${cur_sha}" = "${remote_sha}" ]; then
    continue
  fi
  [ -n "${dl_url}" ] || continue

  tmp_dir=$(mktemp -d)
  chmod 700 "${tmp_dir}"
  mkdir -p "${tmp_dir}/extract"

  if ! curl -fsSL --max-time 30 --retry 3 --retry-delay 2 -o "${tmp_dir}/cert.tar.gz" "${dl_url}" 2>/dev/null; then
    rm -rf "${tmp_dir}"
    continue
  fi
  if ! tar -xzf "${tmp_dir}/cert.tar.gz" -C "${tmp_dir}/extract" 2>/dev/null; then
    rm -rf "${tmp_dir}"
    continue
  fi

  fc=""
  fk=""
  for f in cert.crt fullchain.pem fullchain.cer cert.pem; do
    fc=$(find "${tmp_dir}/extract" -type f -name "$f" | head -n 1 || true)
    [ -n "${fc}" ] && break
  done
  for f in private.key privkey.pem key.pem; do
    fk=$(find "${tmp_dir}/extract" -type f -name "$f" | head -n 1 || true)
    [ -n "${fk}" ] && break
  done

  if [ -z "${fc}" ] || [ -z "${fk}" ]; then
    rm -rf "${tmp_dir}"
    continue
  fi

  tr -d '\r' < "${fc}" > "${tmp_dir}/cert.clean"
  tr -d '\r' < "${fk}" > "${tmp_dir}/key.clean"

  if ! validate_pair "${tmp_dir}/cert.clean" "${tmp_dir}/key.clean" \
    || ! openssl x509 -in "${tmp_dir}/cert.clean" -noout -checkend 0 >/dev/null 2>&1; then
    rm -rf "${tmp_dir}"
    continue
  fi

  mv -f "${tmp_dir}/cert.clean" "${CERT_PATH}"
  mv -f "${tmp_dir}/key.clean" "${KEY_PATH}"
  rm -rf "${tmp_dir}"

  chown "root:${SVC_USER}" "${CERT_PATH}" "${KEY_PATH}" 2>/dev/null || true
  chmod 640 "${CERT_PATH}" "${KEY_PATH}" 2>/dev/null || true
  restart_svc "${SVC_NAME}"
done
EOF
  chmod 755 "${CERT_SYNC_BIN}"

  case "$INIT_SYSTEM" in
    systemd)
      log_info "配置每日证书自动同步定时器 (guaplus-cert-sync.timer)..."
      cat > "${SYSTEMD_SERVICES_DIR}/guaplus-cert-sync.service" <<EOF
[Unit]
Description=GuaPlus TLS Certificate Auto Sync
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=${CERT_SYNC_BIN}
EOF

      cat > "${SYSTEMD_SERVICES_DIR}/guaplus-cert-sync.timer" <<EOF
[Unit]
Description=Run GuaPlus TLS Certificate Sync Daily

[Timer]
OnCalendar=*-*-* 09:00:00
RandomizedDelaySec=300
Persistent=true

[Install]
WantedBy=timers.target
EOF
      systemctl daemon-reload
      systemctl enable --now guaplus-cert-sync.timer
      ;;
    openrc)
      log_info "配置每日证书自动同步任务 (/etc/periodic/daily/guaplus-cert-sync)..."
      mkdir -p /etc/periodic/daily
      cat > /etc/periodic/daily/guaplus-cert-sync <<EOF
#!/bin/sh
exec ${CERT_SYNC_BIN}
EOF
      chmod 755 /etc/periodic/daily/guaplus-cert-sync
      if [ -x "${OPENRC_SERVICES_DIR}/crond" ]; then
        rc-update add crond default >/dev/null 2>&1 || true
        rc-service crond start >/dev/null 2>&1 || true
      fi
      ;;
  esac
}

enable_and_restart_service() {
  svc="$1"
  case "$INIT_SYSTEM" in
    systemd)
      systemctl enable "$svc"
      systemctl restart "$svc"
      ;;
    openrc)
      rc-update add "$svc" default || log_info "服务 $svc 已存在于 OpenRC default 运行级别"
      rc-service "$svc" restart
      ;;
  esac
}

get_service_status() {
  svc="$1"
  case "$INIT_SYSTEM" in
    systemd)
      systemctl is-active "$svc" 2>/dev/null || echo "inactive"
      ;;
    openrc)
      if rc-service "$svc" status >/dev/null 2>&1; then
        echo "active"
      else
        echo "inactive"
      fi
      ;;
  esac
}

panel_get_token() {
  log_info "尝试从面板获取授权TOKEN..."
  key="$1"
  fp="$2"
  curl -fsSL -G "${PANEL_INSTALL_API}" \
    --data-urlencode "key=${key}" \
    --data-urlencode "fingerprint=${fp}" | jq -r '.data.token' | tr -d '\r\n'
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
    log_error "缺少交互参数，且当前没有可用终端；请通过命令行参数传入 (使用 -h 查看用法)"
  fi
}

prompt_if_empty() {
  var_name="$1"
  prompt_text="$2"
  eval "current_val=\${$var_name}"
  if [ -z "$current_val" ]; then
    prompt_read "$prompt_text" input_val
    eval "${var_name}=\$input_val"
  fi
}

resolve_protocol() {
  if [ -z "$PROTOCOL" ]; then
    printf '请选择要安装的协议:\n'
    printf '  1) Hysteria2 (默认)\n'
    printf '  2) VLESS (Xray + Gateway)\n'
    prompt_read "请输入选项 [1-2]: " proto_ans
    PROTOCOL="${proto_ans:-1}"
  fi

  case "$(printf '%s' "$PROTOCOL" | tr '[:upper:]' '[:lower:]')" in
    1|hy2|hysteria|hysteria2)
      PROTOCOL="hysteria2" ;;
    2|vless|xray|ws)
      PROTOCOL="vless" ;;
    *)
      log_error "不支持的协议类型: ${PROTOCOL} (可选: hysteria2 / vless)" ;;
  esac
}

resolve_auto_dns() {
  if [ -z "$AUTO_DNS" ]; then
    prompt_read "是否自动解析域名 (Cloudflare)? [Y/n]: " ans
    case "$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')" in
      n|no|0) AUTO_DNS="0" ;;
      ""|y|yes|1) AUTO_DNS="1" ;;
      *) log_error "无效输入: ${ans} (请输入 Y/n)" ;;
    esac
  fi

  case "$AUTO_DNS" in
    0) AUTO_DNS_BOOL="false" ;;
    1) AUTO_DNS_BOOL="true" ;;
    *) log_error "--auto-dns 仅支持 1 或 0，当前传入: ${AUTO_DNS}" ;;
  esac
}

resolve_insecure() {
  case "$INSECURE" in
    0|1) ;;
    *) log_error "--insecure 仅支持 1 或 0，当前传入: ${INSECURE}" ;;
  esac
}

# ==========================================
# Hysteria2 Installation Flow
# ==========================================

hy2_get_latest_version() {
  ver=$(curl -fsSL "${HY2_REPO_API}/releases/latest" | jq -r '.tag_name' | sed 's#app/##')
  [ -n "$ver" ] && [ "$ver" != "null" ] || log_error "获取 Hysteria2 最新版本失败"
  echo "$ver"
}

hy2_install_binary() {
  log_info "下载并安装 Hysteria2 可执行文件..."
  arch=$(detect_arch)
  ver=$(hy2_get_latest_version)
  url="${HY2_DL_BASE}/app/${ver}/hysteria-linux-${arch}"

  curl -fL --progress-bar -o /tmp/hysteria "$url" || log_error "下载 Hysteria2 失败"
  mkdir -p "$(dirname "${HY2_BIN}")"
  mv -f /tmp/hysteria "${HY2_BIN}"
  chmod 755 "${HY2_BIN}"
}

hy2_install_service() {
  case "$INIT_SYSTEM" in
    systemd)
      log_info "创建 systemd 服务文件 (hysteria-server)..."
      cat > "${SYSTEMD_SERVICES_DIR}/hysteria-server.service" <<EOF
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
ExecStart=${HY2_BIN} server -c ${HY2_CONFIG_PATH}
User=${HY2_USER}
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
      systemctl daemon-reload
      ;;
    openrc)
      log_info "创建 OpenRC 服务文件 (hysteria-server)..."
      cat > "${OPENRC_SERVICES_DIR}/hysteria-server" <<EOF
#!/sbin/openrc-run

name="hysteria-server"
description="Hysteria2 Server"
command="${HY2_BIN}"
command_args="server -c ${HY2_CONFIG_PATH}"
command_user="${HY2_USER}:${HY2_USER}"
command_background="yes"
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/hysteria-server.log"
error_log="/var/log/hysteria-server.err"

depend() {
  need net
  after firewall
}

start_pre() {
  checkpath --file --owner "${HY2_USER}:${HY2_USER}" --mode 0640 "\${output_log}" "\${error_log}"
}
EOF
      chmod 755 "${OPENRC_SERVICES_DIR}/hysteria-server"
      if command -v setcap >/dev/null 2>&1; then
        setcap 'cap_net_admin,cap_net_bind_service,cap_net_raw=+ep' "${HY2_BIN}" 2>/dev/null || true
      fi
      ;;
  esac
}

hy2_write_config() {
  obfs_pwd="$1"
  stats_port="$2"
  stats_secret="$3"
  log_info "写入 Hysteria2 配置文件 ${HY2_CONFIG_PATH}..."
  cat > "${HY2_CONFIG_PATH}" <<EOF
listen: :${LISTEN_PORT}

tls:
  cert: ${HY2_CERT_PATH}
  key: ${HY2_KEY_PATH}

auth:
  type: http
  http:
    url: ${PANEL_VERIFY_API}
    insecure: false

obfs:
  type: salamander
  salamander:
    password: ${obfs_pwd}

trafficStats:
  listen: :${stats_port}
  secret: ${stats_secret}
EOF
  chown "${HY2_USER}:${HY2_USER}" "${HY2_CONFIG_PATH}"
  chmod 600 "${HY2_CONFIG_PATH}"
}

hy2_panel_upload() {
  log_info "上传 Hysteria2 节点信息到面板 (auto_dns=${AUTO_DNS_BOOL}, sni=${SNI}, insecure=${INSECURE})..."
  token=$(printf '%s' "$1" | tr -d '\r\n')
  ip="$2"
  obfs_pwd="$3"
  stats_port="$4"
  stats_secret="$5"

  payload=$(jq -n \
    --arg protocol "hysteria2" \
    --argjson auto_dns "${AUTO_DNS_BOOL}" \
    --arg ip "$ip" \
    --arg name "${NODE_NAME}" \
    --arg domain "${DOMAIN}" \
    --arg port "${LISTEN_PORT}" \
    --arg insecure "${INSECURE}" \
    --arg sni "${SNI}" \
    --arg obfs "salamander" \
    --arg obfs_password "$obfs_pwd" \
    --arg traffic_stats_port "$stats_port" \
    --arg traffic_stats_secret "$stats_secret" \
    '{
      protocol: $protocol,
      auto_dns: $auto_dns,
      ip: $ip,
      name: $name,
      domain: $domain,
      port: ($port | tonumber),
      insecure: ($insecure | tonumber),
      sni: $sni,
      obfs: $obfs,
      obfs_password: $obfs_password,
      traffic_stats_port: ($traffic_stats_port | tonumber),
      traffic_stats_secret: $traffic_stats_secret
    }')

  curl -fsS -X POST "${PANEL_INSTALL_API}" \
    -H "Authorization: ${token}" \
    -H "Content-Type: application/json" \
    -d "$payload" | jq -r '.data.id'
}

run_hysteria2_install() {
  ensure_cmds curl jq openssl tar
  ensure_system_user "${HY2_USER}" "${HY2_HOME_DIR}"
  [ -x "${HY2_BIN}" ] || hy2_install_binary
  hy2_install_service

  FINGERPRINT=$(get_machine_fingerprint "${HY2_CONFIG_DIR}" "${HY2_FP_PATH}" "hysteria2")
  TOKEN=$(panel_get_token "${INSTALL_KEY}" "${FINGERPRINT}")
  [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ] || log_error "获取授权TOKEN失败，请检查机场地址、密钥和指纹"

  install_cert_from_panel "${HY2_CONFIG_DIR}" "${HY2_CERT_PATH}" "${HY2_KEY_PATH}" "${HY2_USER}" "${TOKEN}"

  IP=$(get_public_ip)
  OBFS_PWD=$(openssl rand -hex 16)
  STATS_PORT=$(rand_port)
  STATS_SECRET=$(openssl rand -hex 16)

  hy2_write_config "$OBFS_PWD" "$STATS_PORT" "$STATS_SECRET"
  log_info "启动并启用 hysteria-server 服务..."
  enable_and_restart_service "hysteria-server"

  NODE_ID=$(hy2_panel_upload "$TOKEN" "$IP" "$OBFS_PWD" "$STATS_PORT" "$STATS_SECRET")
  [ -n "$NODE_ID" ] && [ "$NODE_ID" != "null" ] || log_error "上传节点信息到面板失败"

  install_cert_auto_sync "hysteria2" "${HY2_CERT_PATH}" "${HY2_KEY_PATH}" "${HY2_USER}" "hysteria-server" "${FINGERPRINT}"

  printf '\n'
  printf '\033[32m-------------------------------------\033[0m\n'
  printf '\033[1;32m✅ Hysteria2 节点安装和配置完成!\033[0m\n'
  printf '\033[32m-------------------------------------\033[0m\n'
  printf '系统/服务管理器: %s / %s\n' "${OS_FAMILY}" "${INIT_SYSTEM}"
  printf '服务状态: %s\n' "$(get_service_status hysteria-server)"
  printf '节点 ID: %s\n' "${NODE_ID}"
  printf '节点域名 / SNI: %s / %s\n' "${DOMAIN}" "${SNI}"
  printf '跳过证书校验: %s\n' "${INSECURE}"
  printf '自动解析域名: %s\n' "${AUTO_DNS_BOOL}"
  printf '监听端口 (UDP): %s\n' "${LISTEN_PORT}"
  printf '证书路径: %s\n' "${HY2_CERT_PATH}"
  printf '私钥路径: %s\n' "${HY2_KEY_PATH}"
  printf '配置路径: %s\n' "${HY2_CONFIG_PATH}"
  printf '证书自动同步: 已开启 (每日同步 %s)\n' "${PANEL_CERT_API}"
  printf '\033[32m-------------------------------------\033[0m\n'
}

# ==========================================
# VLESS (Xray + Gateway) Installation Flow
# ==========================================

vless_normalize_prefix() {
  case "$PATH_PREFIX" in
    /*) ;;
    *) PATH_PREFIX="/${PATH_PREFIX}" ;;
  esac
  case "$PATH_PREFIX" in
    */) ;;
    *) PATH_PREFIX="${PATH_PREFIX}/" ;;
  esac
}

vless_get_latest_xray_version() {
  ver=$(curl -fsSL "${XRAY_REPO_API}/releases/latest" | jq -r '.tag_name')
  [ -n "$ver" ] && [ "$ver" != "null" ] || log_error "获取 Xray-core 最新版本失败"
  echo "$ver"
}

vless_gen_uuid() {
  u=$("${XRAY_BIN}" uuid 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || true)
  u=$(printf '%s' "$u" | tr -d '\r\n ')
  [ -n "$u" ] || log_error "生成随机 UUID 失败"
  echo "$u"
}

vless_install_xray_binary() {
  arch="$1"
  log_info "下载并安装最新版 Xray-core..."
  ver=$(vless_get_latest_xray_version)
  case "$arch" in
    amd64) asset="Xray-linux-64.zip" ;;
    arm64) asset="Xray-linux-arm64-v8a.zip" ;;
  esac

  url="${XRAY_DL_BASE}/${ver}/${asset}"
  tmpdir=$(mktemp -d)
  curl -fL --progress-bar -o "${tmpdir}/xray.zip" "$url" || { rm -rf "$tmpdir"; log_error "下载 Xray-core 失败: ${url}"; }
  unzip -qo "${tmpdir}/xray.zip" -d "${tmpdir}" || { rm -rf "$tmpdir"; log_error "解压 Xray-core 失败"; }

  mkdir -p "$(dirname "${XRAY_BIN}")" "${XRAY_ASSET_DIR}"
  mv -f "${tmpdir}/xray" "${XRAY_BIN}"
  chmod 755 "${XRAY_BIN}"
  [ -f "${tmpdir}/geoip.dat" ] && mv -f "${tmpdir}/geoip.dat" "${XRAY_ASSET_DIR}/geoip.dat"
  [ -f "${tmpdir}/geosite.dat" ] && mv -f "${tmpdir}/geosite.dat" "${XRAY_ASSET_DIR}/geosite.dat"
  rm -rf "$tmpdir"
}

vless_install_gateway_binary() {
  arch="$1"
  gw_token="$2"
  log_info "向面板申请 airport-gateway (${OS_FAMILY}-${arch}) 临时下载链接 (${PANEL_GATEWAY_API})..."

  gw_resp=$(curl -fsSL --max-time 20 -G "${PANEL_GATEWAY_API}" \
    -H "Authorization: ${gw_token}" \
    --data-urlencode "os=${OS_FAMILY}" \
    --data-urlencode "arch=${arch}") \
    || log_error "请求面板 airport-gateway 下载接口失败: ${PANEL_GATEWAY_API}"

  gw_url=$(printf '%s' "${gw_resp}" | jq -r '.data.download_url // empty' 2>/dev/null || true)
  gw_sha=$(printf '%s' "${gw_resp}" | jq -r '.data.sha256 // empty' 2>/dev/null | tr -d ':' | tr '[:upper:]' '[:lower:]' || true)
  [ -n "${gw_url}" ] || log_error "面板未返回有效的 airport-gateway download_url: ${gw_resp}"

  gw_tmp=$(mktemp)
  log_info "通过临时下载链接下载 airport-gateway (${OS_FAMILY}-${arch})..."
  if ! curl -fL --progress-bar --max-time 120 --retry 3 --retry-delay 2 -o "${gw_tmp}" "${gw_url}"; then
    rm -f "${gw_tmp}"
    log_error "下载 airport-gateway 失败"
  fi

  if [ -n "${gw_sha}" ]; then
    actual_sha=$(openssl dgst -sha256 "${gw_tmp}" | awk '{print $NF}' | tr '[:upper:]' '[:lower:]')
    if [ "${actual_sha}" != "${gw_sha}" ]; then
      rm -f "${gw_tmp}"
      log_error "airport-gateway SHA-256 校验失败 (期望: ${gw_sha}, 实际: ${actual_sha})"
    fi
    log_info "airport-gateway SHA-256 校验通过"
  fi

  mkdir -p "$(dirname "${GATEWAY_BIN}")"
  mv -f "${gw_tmp}" "${GATEWAY_BIN}"
  chmod 755 "${GATEWAY_BIN}"
}

vless_install_services() {
  case "$INIT_SYSTEM" in
    systemd)
      log_info "创建 systemd 服务文件 (xray-backend & airport-gateway)..."
      cat > "${SYSTEMD_SERVICES_DIR}/xray-backend.service" <<EOF
[Unit]
Description=Xray-core Local WS Backend
After=network.target

[Service]
Type=simple
User=${VLESS_USER}
Environment=XRAY_LOCATION_ASSET=${XRAY_ASSET_DIR}
ExecStart=${XRAY_BIN} run -c ${XRAY_CONFIG_PATH}
NoNewPrivileges=true
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

      cat > "${SYSTEMD_SERVICES_DIR}/airport-gateway.service" <<EOF
[Unit]
Description=Airport VLESS WS Auth Gateway
After=network.target xray-backend.service
Wants=xray-backend.service

[Service]
Type=simple
User=${VLESS_USER}
EnvironmentFile=${GATEWAY_ENV_PATH}
ExecStart=${GATEWAY_BIN}
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
      systemctl daemon-reload
      ;;
    openrc)
      log_info "创建 OpenRC 服务文件 (xray-backend & airport-gateway)..."
      cat > "${OPENRC_SERVICES_DIR}/xray-backend" <<EOF
#!/sbin/openrc-run

name="xray-backend"
description="Xray-core Local WS Backend"
command="${XRAY_BIN}"
command_args="run -c ${XRAY_CONFIG_PATH}"
command_user="${VLESS_USER}:${VLESS_USER}"
command_background="yes"
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/xray-backend.log"
error_log="/var/log/xray-backend.err"

depend() {
  need net
  after firewall
}

start_pre() {
  export XRAY_LOCATION_ASSET="${XRAY_ASSET_DIR}"
  checkpath --file --owner "${VLESS_USER}:${VLESS_USER}" --mode 0640 "\${output_log}" "\${error_log}"
}
EOF

      cat > "${OPENRC_SERVICES_DIR}/airport-gateway" <<EOF
#!/sbin/openrc-run

name="airport-gateway"
description="Airport VLESS WS Auth Gateway"
command="${GATEWAY_BIN}"
command_user="${VLESS_USER}:${VLESS_USER}"
command_background="yes"
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/airport-gateway.log"
error_log="/var/log/airport-gateway.err"

depend() {
  need net xray-backend
  after firewall xray-backend
}

start_pre() {
  checkpath --file --owner "${VLESS_USER}:${VLESS_USER}" --mode 0640 "\${output_log}" "\${error_log}"
  set -a
  . "${GATEWAY_ENV_PATH}"
  set +a
}
EOF
      chmod 755 "${OPENRC_SERVICES_DIR}/xray-backend" "${OPENRC_SERVICES_DIR}/airport-gateway"
      if command -v setcap >/dev/null 2>&1; then
        setcap 'cap_net_bind_service=+ep' "${GATEWAY_BIN}" 2>/dev/null || true
      fi
      ;;
  esac
}

vless_write_xray_config() {
  node_uuid="$1"
  log_info "写入 Xray 配置文件 ${XRAY_CONFIG_PATH}..."
  jq -n \
    --arg port "${XRAY_INTERNAL_PORT}" \
    --arg uuid "${node_uuid}" \
    --arg ws_path "${XRAY_WS_PATH}" \
    '{
      log: { loglevel: "warning" },
      inbounds: [
        {
          listen: "127.0.0.1",
          port: ($port | tonumber),
          protocol: "vless",
          settings: {
            clients: [{ id: $uuid }],
            decryption: "none"
          },
          streamSettings: {
            network: "ws",
            security: "none",
            wsSettings: {
              path: $ws_path
            }
          }
        }
      ],
      outbounds: [
        { protocol: "freedom" }
      ]
    }' > "${XRAY_CONFIG_PATH}"

  chown "root:${VLESS_USER}" "${XRAY_CONFIG_PATH}"
  chmod 640 "${XRAY_CONFIG_PATH}"
}

vless_write_gateway_env() {
  stats_port="$1"
  stats_secret="$2"
  log_info "写入 Gateway 环境配置 ${GATEWAY_ENV_PATH}..."
  cat > "${GATEWAY_ENV_PATH}" <<EOF
LISTEN_ADDR=:${LISTEN_PORT}
STATS_ADDR=:${stats_port}
STATS_SECRET=${stats_secret}
XRAY_UPSTREAM=http://127.0.0.1:${XRAY_INTERNAL_PORT}
XRAY_WS_PATH=${XRAY_WS_PATH}
PATH_PREFIX=${PATH_PREFIX}
TLS_CERT=${VLESS_CERT_PATH}
TLS_KEY=${VLESS_KEY_PATH}
AUTH_URL=${PANEL_VERIFY_API}
EOF
  chown "root:${VLESS_USER}" "${GATEWAY_ENV_PATH}"
  chmod 640 "${GATEWAY_ENV_PATH}"
}

vless_panel_upload() {
  log_info "上传 VLESS 节点信息到面板 (auto_dns=${AUTO_DNS_BOOL}, sni=${SNI}, insecure=${INSECURE})..."
  token=$(printf '%s' "$1" | tr -d '\r\n')
  ip="$2"
  node_uuid="$3"
  stats_port="$4"
  stats_secret="$5"

  payload=$(jq -n \
    --arg protocol "vless" \
    --argjson auto_dns "${AUTO_DNS_BOOL}" \
    --arg ip "$ip" \
    --arg name "${NODE_NAME}" \
    --arg domain "${DOMAIN}" \
    --arg port "${LISTEN_PORT}" \
    --arg insecure "${INSECURE}" \
    --arg sni "${SNI}" \
    --arg uuid "$node_uuid" \
    --arg network "ws" \
    --arg path_prefix "${PATH_PREFIX}" \
    --arg traffic_stats_port "$stats_port" \
    --arg traffic_stats_secret "$stats_secret" \
    '{
      protocol: $protocol,
      auto_dns: $auto_dns,
      ip: $ip,
      name: $name,
      domain: $domain,
      port: ($port | tonumber),
      insecure: ($insecure | tonumber),
      sni: $sni,
      uuid: $uuid,
      network: $network,
      path_prefix: $path_prefix,
      traffic_stats_port: ($traffic_stats_port | tonumber),
      traffic_stats_secret: $traffic_stats_secret
    }')

  curl -fsS -X POST "${PANEL_INSTALL_API}" \
    -H "Authorization: ${token}" \
    -H "Content-Type: application/json" \
    -d "$payload" | jq -r '.data.id'
}

run_vless_install() {
  case "$OS_FAMILY" in
    alpine|debian) ;;
    *) log_error "VLESS 模式当前仅支持 Alpine 与 Debian/Ubuntu (airport-gateway 发行包限制)" ;;
  esac

  arch=$(detect_arch)
  case "$arch" in
    amd64|arm64) ;;
    *) log_error "VLESS 模式当前仅支持 amd64 与 arm64 架构，当前为: ${arch}" ;;
  esac

  ensure_cmds curl jq openssl tar unzip
  vless_normalize_prefix
  ensure_system_user "${VLESS_USER}" "${VLESS_HOME_DIR}"

  [ -x "${XRAY_BIN}" ] || vless_install_xray_binary "$arch"

  FINGERPRINT=$(get_machine_fingerprint "${VLESS_CONFIG_DIR}" "${VLESS_FP_PATH}" "vless")
  TOKEN=$(panel_get_token "${INSTALL_KEY}" "${FINGERPRINT}")
  [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ] || log_error "获取授权TOKEN失败，请检查机场地址、密钥和指纹"

  vless_install_gateway_binary "$arch" "${TOKEN}"
  vless_install_services
  install_cert_from_panel "${VLESS_CONFIG_DIR}" "${VLESS_CERT_PATH}" "${VLESS_KEY_PATH}" "${VLESS_USER}" "${TOKEN}"

  IP=$(get_public_ip)
  NODE_UUID=$(vless_gen_uuid)
  STATS_PORT=$(rand_port)
  STATS_SECRET=$(openssl rand -hex 16)

  vless_write_xray_config "$NODE_UUID"
  vless_write_gateway_env "$STATS_PORT" "$STATS_SECRET"
  log_info "启动并启用 xray-backend 与 airport-gateway 服务..."
  enable_and_restart_service "xray-backend"
  enable_and_restart_service "airport-gateway"

  NODE_ID=$(vless_panel_upload "$TOKEN" "$IP" "$NODE_UUID" "$STATS_PORT" "$STATS_SECRET")
  [ -n "$NODE_ID" ] && [ "$NODE_ID" != "null" ] || log_error "上传节点信息到面板失败"

  install_cert_auto_sync "vless" "${VLESS_CERT_PATH}" "${VLESS_KEY_PATH}" "${VLESS_USER}" "airport-gateway" "${FINGERPRINT}"

  printf '\n'
  printf '\033[32m-------------------------------------\033[0m\n'
  printf '\033[1;32m✅ VLESS (Xray + Gateway) 节点安装完成!\033[0m\n'
  printf '\033[32m-------------------------------------\033[0m\n'
  printf '系统/服务管理器: %s / %s\n' "${OS_FAMILY}" "${INIT_SYSTEM}"
  printf 'Xray 服务状态: %s\n' "$(get_service_status xray-backend)"
  printf 'Gateway 服务状态: %s\n' "$(get_service_status airport-gateway)"
  printf '节点 ID: %s\n' "${NODE_ID}"
  printf '节点域名 / SNI: %s / %s\n' "${DOMAIN}" "${SNI}"
  printf '跳过证书校验: %s\n' "${INSECURE}"
  printf '自动解析域名: %s\n' "${AUTO_DNS_BOOL}"
  printf '监听端口 (TCP): %s\n' "${LISTEN_PORT}"
  printf '节点 UUID: %s\n' "${NODE_UUID}"
  printf '鉴权前缀: %s\n' "${PATH_PREFIX}"
  printf '证书路径: %s\n' "${VLESS_CERT_PATH}"
  printf '私钥路径: %s\n' "${VLESS_KEY_PATH}"
  printf '配置目录: %s\n' "${VLESS_CONFIG_DIR}"
  printf '证书自动同步: 已开启 (每日同步 %s)\n' "${PANEL_CERT_API}"
  printf '\033[32m-------------------------------------\033[0m\n'
}

# --- Main Logic ---

main() {
  parse_args "$@"
  require_root
  detect_os_pm
  detect_init_system

  print_banner

  resolve_protocol
  prompt_if_empty PANEL_BASE "请输入机场地址: "
  prompt_if_empty INSTALL_KEY "请输入安装密钥: "
  prompt_if_empty NODE_NAME "请输入节点名称: "
  prompt_if_empty DOMAIN "请输入节点域名: "
  resolve_auto_dns
  resolve_insecure

  PANEL_BASE="${PANEL_BASE%/}"
  [ -n "${SNI}" ] || SNI="${DOMAIN}"

  if [ -z "$PANEL_BASE" ] || [ -z "$INSTALL_KEY" ] || [ -z "$NODE_NAME" ] || [ -z "$DOMAIN" ]; then
    log_error "所有必填输入项都不能为空"
  fi

  PANEL_INSTALL_API="${PANEL_BASE}/api/v1/install"
  PANEL_VERIFY_API="${PANEL_BASE}/api/v1/verify"
  [ -n "${PANEL_CERT_API}" ] || PANEL_CERT_API="${PANEL_BASE}/api/v1/cert/download"
  [ -n "${PANEL_GATEWAY_API}" ] || PANEL_GATEWAY_API="${PANEL_BASE}/api/v1/gateway/download"

  printf '\n\033[1m安装参数确认:\033[0m\n'
  printf '  协议类型: %s\n' "${PROTOCOL}"
  printf '  面板地址: %s\n' "${PANEL_BASE}"
  printf '  节点名称: %s\n' "${NODE_NAME}"
  printf '  节点域名: %s\n' "${DOMAIN}"
  printf '  TLS SNI:  %s\n' "${SNI}"
  printf '  跳过校验: %s\n' "${INSECURE}"
  printf '  监听端口: %s\n' "${LISTEN_PORT}"
  printf '  自动解析: %s\n\n' "${AUTO_DNS_BOOL}"

  case "$PROTOCOL" in
    hysteria2) run_hysteria2_install ;;
    vless)     run_vless_install ;;
  esac
}

main "$@"