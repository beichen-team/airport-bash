#!/bin/sh

set -eu

export LANG=C.UTF-8

# --- Variables ---
VERSION="1.1.0"
CONFIG_DIR="/etc/hysteria"
EXECUTABLE_INSTALL_PATH="/usr/local/bin/hysteria"
SYSTEMD_SERVICES_DIR="/etc/systemd/system"
OPENRC_SERVICES_DIR="/etc/init.d"
HYSTERIA_USER="hysteria"
HYSTERIA_HOME_DIR="/var/lib/${HYSTERIA_USER}"
CERT_PATH="${CONFIG_DIR}/cert.crt"
KEY_PATH="${CONFIG_DIR}/private.key"
CONFIG_PATH="${CONFIG_DIR}/config.yaml"
FINGERPRINT_PATH="${CONFIG_DIR}/fingerprint.sha256"
SNI_DEFAULT="${SNI:-www.bing.com}"
LISTEN_PORT="${LISTEN_PORT:-3389}"
REPO_API="https://api.github.com/repos/apernet/hysteria"
REPO_DL_BASE="https://github.com/apernet/hysteria/releases/download"

# 可通过环境变量或命令行参数传入
PANEL_BASE="${PANEL_BASE:-}"
INSTALL_KEY="${INSTALL_KEY:-}"
NODE_NAME="${NODE_NAME:-}"
DOMAIN="${DOMAIN:-}"
SILENT="${SILENT:-0}"

OS_FAMILY=""
INIT_SYSTEM=""
PM_UPDATE=""
PM_INSTALL=""
PANEL_INSTALL_API=""
PANEL_VERIFY_API=""

# --- Helper Functions ---

log_info() {
  [ "$SILENT" -eq 1 ] && return 0
  printf '\033[32m[INFO]\033[0m %s\n' "$1" >&2
}

log_error() {
  printf '\033[31m[ERROR]\033[0m %s\n' "$1" >&2
  exit 1
}

usage() {
  cat <<EOF
GuaPlus Airport Hysteria2 Installer v${VERSION}

用法:
  $0 [选项]

选项:
  -u, --url <URL>        机场面板地址 (环境变量: PANEL_BASE)
  -k, --key <KEY>        安装密钥 (环境变量: INSTALL_KEY)
  -n, --name <NAME>      节点名称 (环境变量: NODE_NAME)
  -d, --domain <DOMAIN>  节点域名 (环境变量: DOMAIN)
  -p, --port <PORT>      监听端口，默认 3389 (环境变量: LISTEN_PORT)
      --sni <SNI>        自签名证书 SNI，默认 www.bing.com (环境变量: SNI)
  -s, --silent           静默安装模式，禁止交互与常规输出 (环境变量: SILENT=1)
  -h, --help             显示此帮助信息
EOF
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
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
        SNI_DEFAULT="$2"; shift 2 ;;
      -s|--silent|-q|--quiet)
        SILENT=1; shift ;;
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

# Detect OS and set package manager commands
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

# Detect systemd or OpenRC
detect_init_system() {
  if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    INIT_SYSTEM="systemd"
  elif command -v rc-service >/dev/null 2>&1 && [ -d "${OPENRC_SERVICES_DIR}" ]; then
    INIT_SYSTEM="openrc"
  else
    log_error "未检测到受支持的服务管理器 (systemd 或 OpenRC)"
  fi
}

# Ensure required commands are installed
ensure_cmds() {
  missing=""
  for c in "$@"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      missing="${missing} ${c}"
    fi
  done

  # Alpine 最小化环境确保 CA 证书存在，避免 HTTPS 下载失败
  if [ "$OS_FAMILY" = "alpine" ] && [ ! -f /etc/ssl/certs/ca-certificates.crt ]; then
    missing="${missing} ca-certificates"
  fi

  [ -z "$missing" ] && return 0

  log_info "安装所需依赖:${missing}"
  # shellcheck disable=SC2086
  $PM_UPDATE >/dev/null 2>&1 || true
  # shellcheck disable=SC2086
  $PM_INSTALL $missing >/dev/null 2>&1 || log_error "依赖安装失败，请检查系统包管理器"
}

# Get system architecture
detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7*|armv6*) echo "arm" ;;
    i386|i686) echo "386" ;;
    *) log_error "不支持的 CPU 架构: $(uname -m)" ;;
  esac
}

# Get latest Hysteria version tag
get_latest_version() {
  ver=$(curl -fsSL "${REPO_API}/releases/latest" | jq -r '.tag_name' | sed 's#app/##')
  [ -n "$ver" ] && [ "$ver" != "null" ] || log_error "获取 Hysteria2 最新版本失败"
  echo "$ver"
}

# Generate a random port number (20000-60000) without requiring shuf
rand_port() {
  hex=$(openssl rand -hex 2)
  num=$((0x${hex}))
  echo $((20000 + (num % 40001)))
}

# Get public IP address
get_public_ip() {
  ip=$(curl -fsS --max-time 10 https://whatismyip.akamai.com 2>/dev/null \
    || curl -fsS --max-time 10 https://ipecho.net/plain 2>/dev/null || true)
  ip=$(printf '%s' "$ip" | tr -d '\r\n ')
  [ -n "$ip" ] || log_error "获取公网 IP 地址失败"
  echo "$ip"
}

# --- Core Installation Functions ---

# 1. Install Hysteria binary
install_hysteria_binary() {
  log_info "下载并安装 Hysteria2 可执行文件..."
  arch=$(detect_arch)
  ver=$(get_latest_version)
  url="${REPO_DL_BASE}/app/${ver}/hysteria-linux-${arch}"

  curl -fsSL -o /tmp/hysteria "$url" || log_error "下载 Hysteria2 失败"
  mkdir -p "$(dirname "${EXECUTABLE_INSTALL_PATH}")"
  mv -f /tmp/hysteria "${EXECUTABLE_INSTALL_PATH}"
  chmod 755 "${EXECUTABLE_INSTALL_PATH}"
}

# 2. Setup service (systemd or OpenRC)
install_systemd() {
  log_info "创建 systemd 服务文件..."
  cat > "${SYSTEMD_SERVICES_DIR}/hysteria-server.service" <<EOF
[Unit]
Description=Hysteria2 Server
After=network.target

[Service]
ExecStart=${EXECUTABLE_INSTALL_PATH} server -c ${CONFIG_PATH}
User=${HYSTERIA_USER}
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
}

install_openrc() {
  log_info "创建 OpenRC 服务文件..."
  cat > "${OPENRC_SERVICES_DIR}/hysteria-server" <<EOF
#!/sbin/openrc-run

name="hysteria-server"
description="Hysteria2 Server"
command="${EXECUTABLE_INSTALL_PATH}"
command_args="server -c ${CONFIG_PATH}"
command_user="${HYSTERIA_USER}:${HYSTERIA_USER}"
command_background="yes"
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/hysteria-server.log"
error_log="/var/log/hysteria-server.err"

depend() {
  need net
  after firewall
}

start_pre() {
  checkpath --file --owner "${HYSTERIA_USER}:${HYSTERIA_USER}" --mode 0640 "\${output_log}" "\${error_log}"
}
EOF
  chmod 755 "${OPENRC_SERVICES_DIR}/hysteria-server"
  if command -v setcap >/dev/null 2>&1; then
    setcap 'cap_net_admin,cap_net_bind_service,cap_net_raw=+ep' "${EXECUTABLE_INSTALL_PATH}" 2>/dev/null || true
  fi
}

install_service() {
  case "$INIT_SYSTEM" in
    systemd) install_systemd ;;
    openrc)  install_openrc ;;
  esac
}

# 3. Create Hysteria user and install files
setup_hysteria() {
  if ! id "${HYSTERIA_USER}" >/dev/null 2>&1; then
    if command -v useradd >/dev/null 2>&1; then
      useradd -r -m -d "${HYSTERIA_HOME_DIR}" -s /sbin/nologin "${HYSTERIA_USER}"
    elif command -v adduser >/dev/null 2>&1; then
      addgroup -S "${HYSTERIA_USER}" >/dev/null 2>&1 || true
      adduser -S -D -h "${HYSTERIA_HOME_DIR}" -G "${HYSTERIA_USER}" -s /sbin/nologin "${HYSTERIA_USER}"
      mkdir -p "${HYSTERIA_HOME_DIR}"
      chown "${HYSTERIA_USER}:${HYSTERIA_USER}" "${HYSTERIA_HOME_DIR}"
    else
      log_error "未找到 useradd 或 adduser 命令"
    fi
  fi

  [ -x "${EXECUTABLE_INSTALL_PATH}" ] || install_hysteria_binary
  install_service
}

# 4. Generate self-signed certificate
write_selfsigned_cert() {
  mkdir -p "${CONFIG_DIR}"
  if [ -f "${CERT_PATH}" ] && [ -f "${KEY_PATH}" ]; then
    log_info "证书文件已存在，跳过生成."
    return
  fi
  log_info "生成自签名证书 (CN=${SNI_DEFAULT})..."
  openssl ecparam -genkey -name prime256v1 -out "${KEY_PATH}" >/dev/null 2>&1
  openssl req -new -x509 -days 36500 -key "${KEY_PATH}" -out "${CERT_PATH}" -subj "/CN=${SNI_DEFAULT}" >/dev/null 2>&1
  chown "root:${HYSTERIA_USER}" "${CERT_PATH}" "${KEY_PATH}"
  chmod 640 "${CERT_PATH}" "${KEY_PATH}"
}

# 5. Get and save SHA256 fingerprint of the certificate
get_machine_fingerprint() {
  if [ -f "${FINGERPRINT_PATH}" ]; then
    cat "${FINGERPRINT_PATH}"
    return
  fi
  fp=$(openssl x509 -in "${CERT_PATH}" -noout -fingerprint -sha256 | awk -F= '{print $2}' | tr -d ':' | tr 'A-Z' 'a-z')
  printf '%s\n' "$fp" > "${FINGERPRINT_PATH}"
  chmod 644 "${FINGERPRINT_PATH}"
  printf '%s\n' "$fp"
}

# 6. Write Hysteria config file
write_config() {
  obfs_pwd="$1"
  stats_port="$2"
  stats_secret="$3"
  log_info "写入 Hysteria 配置文件 ${CONFIG_PATH}..."
  cat > "${CONFIG_PATH}" <<EOF
listen: :${LISTEN_PORT}

tls:
  cert: ${CERT_PATH}
  key: ${KEY_PATH}

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
  chown "${HYSTERIA_USER}:${HYSTERIA_USER}" "${CONFIG_PATH}"
  chmod 600 "${CONFIG_PATH}"
}

# 7. Start and enable service
start_service() {
  log_info "启动并启用 hysteria-server 服务..."
  case "$INIT_SYSTEM" in
    systemd)
      systemctl enable hysteria-server >/dev/null 2>&1
      systemctl restart hysteria-server >/dev/null
      ;;
    openrc)
      rc-update add hysteria-server default >/dev/null 2>&1 || true
      rc-service hysteria-server restart >/dev/null
      ;;
  esac
}

get_service_status() {
  case "$INIT_SYSTEM" in
    systemd)
      systemctl is-active hysteria-server 2>/dev/null || echo "inactive"
      ;;
    openrc)
      if rc-service hysteria-server status >/dev/null 2>&1; then
        echo "active"
      else
        echo "inactive"
      fi
      ;;
  esac
}

# --- Panel Interaction Functions ---

panel_get_token() {
  log_info "尝试从面板获取授权TOKEN..."
  key="$1"
  fp="$2"
  curl -fsSL "${PANEL_INSTALL_API}?key=${key}&fingerprint=${fp}" | jq -r '.data.token'
}

panel_upload() {
  log_info "上传节点信息到面板..."
  token="$1"
  ip="$2"
  name="$3"
  domain="$4"
  sni="$5"
  obfs_pwd="$6"
  stats_port="$7"
  stats_secret="$8"

  token=$(printf '%s' "$token" | tr -d '\r\n')

  payload=$(jq -n \
    --arg ip "$ip" \
    --arg name "$name" \
    --arg domain "$domain" \
    --arg port "${LISTEN_PORT}" \
    --arg insecure "1" \
    --arg sni "$sni" \
    --arg obfs "salamander" \
    --arg obfs_password "$obfs_pwd" \
    --arg traffic_stats_port "$stats_port" \
    --arg traffic_stats_secret "$stats_secret" \
    '{ip: $ip, name: $name, domain: $domain, port: ($port | tonumber), insecure: ($insecure | tonumber), sni: $sni, obfs: $obfs, obfs_password: $obfs_password, traffic_stats_port: ($traffic_stats_port | tonumber), traffic_stats_secret: $traffic_stats_secret}')

  curl -fsS -X POST "${PANEL_INSTALL_API}" \
    -H "Authorization: ${token}" \
    -H "Content-Type: application/json" \
    -d "$payload" | jq -r '.data.id'
}

prompt_if_empty() {
  var_name="$1"
  prompt_text="$2"
  eval "current_val=\${$var_name}"
  if [ -z "$current_val" ]; then
    if [ "$SILENT" -eq 1 ] || [ ! -t 0 ]; then
      log_error "非交互/静默模式下缺少必填参数: ${var_name} (使用 -h 查看用法)"
    fi
    printf '%s' "$prompt_text"
    read -r input_val
    eval "${var_name}=\$input_val"
  fi
}

# --- Main Logic ---

main() {
  parse_args "$@"
  require_root
  detect_os_pm
  detect_init_system
  ensure_cmds curl jq openssl

  if [ "$SILENT" -eq 0 ] && [ -t 1 ]; then
    clear || true
    printf '%s\n\n' "-- GuaPlus Airport Hysteria2 Installer v${VERSION} --"
  fi

  # 仅在参数未提供时进行交互输入；静默/非交互模式下缺参直接报错退出
  prompt_if_empty PANEL_BASE "请输入机场地址: "
  prompt_if_empty INSTALL_KEY "请输入安装密钥: "
  prompt_if_empty NODE_NAME "请输入节点名称: "
  prompt_if_empty DOMAIN "请输入节点域名: "

  # 去除面板地址末尾多余的斜杠
  PANEL_BASE="${PANEL_BASE%/}"

  if [ -z "$PANEL_BASE" ] || [ -z "$INSTALL_KEY" ] || [ -z "$NODE_NAME" ] || [ -z "$DOMAIN" ]; then
    log_error "所有必填输入项都不能为空"
  fi

  PANEL_INSTALL_API="${PANEL_BASE}/api/v1/install"
  PANEL_VERIFY_API="${PANEL_BASE}/api/v1/verify"

  # 1. Installation Steps
  setup_hysteria
  write_selfsigned_cert

  # 2. Get necessary parameters
  FINGERPRINT=$(get_machine_fingerprint)
  TOKEN=$(panel_get_token "$INSTALL_KEY" "$FINGERPRINT")
  [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ] || log_error "获取授权TOKEN失败，请检查机场地址、密钥和指纹"

  IP=$(get_public_ip)
  OBFS_PWD=$(openssl rand -hex 16)
  STATS_PORT=$(rand_port)
  STATS_SECRET=$(openssl rand -hex 16)

  # 3. Write config and start service
  write_config "$OBFS_PWD" "$STATS_PORT" "$STATS_SECRET"
  start_service

  # 4. Upload to panel
  NODE_ID=$(panel_upload "$TOKEN" "$IP" "$NODE_NAME" "$DOMAIN" "$SNI_DEFAULT" "$OBFS_PWD" "$STATS_PORT" "$STATS_SECRET")
  [ -n "$NODE_ID" ] && [ "$NODE_ID" != "null" ] || log_error "上传节点信息到面板失败"

  # 5. Success Message
  if [ "$SILENT" -eq 0 ]; then
    echo
    echo "-------------------------------------"
    echo "✅ Hysteria2 服务器安装和配置完成!"
    echo "-------------------------------------"
    echo "系统/服务管理器: ${OS_FAMILY} / ${INIT_SYSTEM}"
    echo "服务状态: $(get_service_status)"
    echo "节点 ID: ${NODE_ID}"
    echo "面板 API 地址: ${PANEL_BASE}"
    echo "Hysteria2 配置路径: ${CONFIG_PATH}"
    echo "-------------------------------------"
  fi
}

main "$@"