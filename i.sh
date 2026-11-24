#!/bin/sh

set -eu

export LANG=C.UTF-8

# --- Global Variables ---
VERSION="2.0.0"
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
GATEWAY_DL_BASE="https://github.com/beichen-team/airport-gateway/releases/download/latest"

# 通用可配置参数（支持环境变量或命令行传入）
PROTOCOL="${PROTOCOL:-}"
PANEL_BASE="${PANEL_BASE:-}"
INSTALL_KEY="${INSTALL_KEY:-}"
NODE_NAME="${NODE_NAME:-}"
DOMAIN="${DOMAIN:-}"
LISTEN_PORT="${LISTEN_PORT:-3389}"
SNI_DEFAULT="${SNI:-www.bing.com}"
AUTO_DNS="${AUTO_DNS:-}"
SILENT="${SILENT:-0}"

AUTO_DNS_BOOL="true"
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
GuaPlus Airport Unified Installer v${VERSION} (Hysteria2 & VLESS)

用法:
  $0 [选项]

选项:
  -t, --type <PROTO>       协议类型: hy2|hysteria2|vless (环境变量: PROTOCOL，静默模式默认 hysteria2)
  -u, --url <URL>          机场面板地址 (环境变量: PANEL_BASE)
  -k, --key <KEY>          安装密钥 (环境变量: INSTALL_KEY)
  -n, --name <NAME>        节点名称 (环境变量: NODE_NAME)
  -d, --domain <DOMAIN>    节点域名 (环境变量: DOMAIN)
  -p, --port <PORT>        对外监听端口，默认 3389 (环境变量: LISTEN_PORT)
      --sni <SNI>          自签名证书 SNI，默认 www.bing.com (环境变量: SNI)
      --prefix <PREFIX>    [仅 VLESS] 鉴权路径前缀，默认 /w/ (环境变量: PATH_PREFIX)
      --auto-dns <1|0>     是否自动解析域名 (Cloudflare)，默认 1 (环境变量: AUTO_DNS)
      --no-dns             关闭自动域名解析，等同于 --auto-dns 0
  -s, --silent             静默安装模式，禁止交互与常规输出 (环境变量: SILENT=1)
  -h, --help               显示此帮助信息
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
        SNI_DEFAULT="$2"; shift 2 ;;
      --prefix)
        [ $# -ge 2 ] || log_error "选项 $1 需要参数"
        PATH_PREFIX="$2"; shift 2 ;;
      --auto-dns)
        [ $# -ge 2 ] || log_error "选项 $1 需要参数"
        AUTO_DNS="$2"; shift 2 ;;
      --no-dns)
        AUTO_DNS="0"; shift ;;
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
  $PM_UPDATE >/dev/null 2>&1 || true
  # shellcheck disable=SC2086
  $PM_INSTALL $missing >/dev/null 2>&1 || log_error "依赖安装失败，请检查系统包管理器"
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

write_selfsigned_cert() {
  c_dir="$1"
  c_cert="$2"
  c_key="$3"
  c_user="$4"

  mkdir -p "${c_dir}"
  if [ -f "${c_cert}" ] && [ -f "${c_key}" ]; then
    log_info "证书文件已存在 (${c_cert})，跳过生成."
    return
  fi
  log_info "生成自签名证书 (CN=${SNI_DEFAULT})..."
  openssl ecparam -genkey -name prime256v1 -out "${c_key}" >/dev/null 2>&1
  openssl req -new -x509 -days 36500 -key "${c_key}" -out "${c_cert}" -subj "/CN=${SNI_DEFAULT}" >/dev/null 2>&1
  chown "root:${c_user}" "${c_cert}" "${c_key}"
  chmod 640 "${c_cert}" "${c_key}"
}

get_machine_fingerprint() {
  c_cert="$1"
  c_fp="$2"
  if [ -f "${c_fp}" ]; then
    cat "${c_fp}"
    return
  fi
  fp=$(openssl x509 -in "${c_cert}" -noout -fingerprint -sha256 | awk -F= '{print $2}' | tr -d ':' | tr 'A-Z' 'a-z')
  printf '%s\n' "$fp" > "${c_fp}"
  chmod 644 "${c_fp}"
  printf '%s\n' "$fp"
}

enable_and_restart_service() {
  svc="$1"
  case "$INIT_SYSTEM" in
    systemd)
      systemctl enable "$svc" >/dev/null 2>&1
      systemctl restart "$svc" >/dev/null
      ;;
    openrc)
      rc-update add "$svc" default >/dev/null 2>&1 || true
      rc-service "$svc" restart >/dev/null
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
  curl -fsSL "${PANEL_INSTALL_API}?key=${key}&fingerprint=${fp}" | jq -r '.data.token'
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

resolve_protocol() {
  if [ -z "$PROTOCOL" ]; then
    if [ "$SILENT" -eq 1 ] || [ ! -t 0 ]; then
      PROTOCOL="hysteria2"
    else
      printf '请选择要安装的协议:\n'
      printf '  1) Hysteria2 (默认)\n'
      printf '  2) VLESS (Xray + Gateway)\n'
      printf '请输入选项 [1-2]: '
      read -r proto_ans
      PROTOCOL="${proto_ans:-1}"
    fi
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
    if [ "$SILENT" -eq 1 ] || [ ! -t 0 ]; then
      AUTO_DNS="1"
    else
      printf '是否自动解析域名 (Cloudflare)? [Y/n]: '
      read -r ans
      case "$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')" in
        n|no|0|false|off) AUTO_DNS="0" ;;
        *) AUTO_DNS="1" ;;
      esac
    fi
  fi

  case "$(printf '%s' "$AUTO_DNS" | tr '[:upper:]' '[:lower:]')" in
    0|false|no|off) AUTO_DNS_BOOL="false" ;;
    *) AUTO_DNS_BOOL="true" ;;
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

  curl -fsSL -o /tmp/hysteria "$url" || log_error "下载 Hysteria2 失败"
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
  log_info "上传 Hysteria2 节点信息到面板 (auto_dns=${AUTO_DNS_BOOL})..."
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
    --arg insecure "1" \
    --arg sni "${SNI_DEFAULT}" \
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
  ensure_cmds curl jq openssl
  ensure_system_user "${HY2_USER}" "${HY2_HOME_DIR}"
  [ -x "${HY2_BIN}" ] || hy2_install_binary
  hy2_install_service
  write_selfsigned_cert "${HY2_CONFIG_DIR}" "${HY2_CERT_PATH}" "${HY2_KEY_PATH}" "${HY2_USER}"

  FINGERPRINT=$(get_machine_fingerprint "${HY2_CERT_PATH}" "${HY2_FP_PATH}")
  TOKEN=$(panel_get_token "${INSTALL_KEY}" "${FINGERPRINT}")
  [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ] || log_error "获取授权TOKEN失败，请检查机场地址、密钥和指纹"

  IP=$(get_public_ip)
  OBFS_PWD=$(openssl rand -hex 16)
  STATS_PORT=$(rand_port)
  STATS_SECRET=$(openssl rand -hex 16)

  hy2_write_config "$OBFS_PWD" "$STATS_PORT" "$STATS_SECRET"
  log_info "启动并启用 hysteria-server 服务..."
  enable_and_restart_service "hysteria-server"

  NODE_ID=$(hy2_panel_upload "$TOKEN" "$IP" "$OBFS_PWD" "$STATS_PORT" "$STATS_SECRET")
  [ -n "$NODE_ID" ] && [ "$NODE_ID" != "null" ] || log_error "上传节点信息到面板失败"

  if [ "$SILENT" -eq 0 ]; then
    echo
    echo "-------------------------------------"
    echo "✅ Hysteria2 节点安装和配置完成!"
    echo "-------------------------------------"
    echo "系统/服务管理器: ${OS_FAMILY} / ${INIT_SYSTEM}"
    echo "服务状态: $(get_service_status hysteria-server)"
    echo "节点 ID: ${NODE_ID}"
    echo "自动解析域名: ${AUTO_DNS_BOOL}"
    echo "监听端口 (UDP): ${LISTEN_PORT}"
    echo "配置路径: ${HY2_CONFIG_PATH}"
    echo "-------------------------------------"
  fi
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
  curl -fsSL -o "${tmpdir}/xray.zip" "$url" || { rm -rf "$tmpdir"; log_error "下载 Xray-core 失败: ${url}"; }
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
  log_info "下载并安装最新版 airport-gateway (${OS_FAMILY}-${arch})..."
  url="${GATEWAY_DL_BASE}/airport-gateway-${OS_FAMILY}-${arch}"

  curl -fsSL -o /tmp/airport-gateway "$url" || log_error "下载 airport-gateway 失败: ${url}"
  mkdir -p "$(dirname "${GATEWAY_BIN}")"
  mv -f /tmp/airport-gateway "${GATEWAY_BIN}"
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
  log_info "上传 VLESS 节点信息到面板 (auto_dns=${AUTO_DNS_BOOL})..."
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
    --arg insecure "1" \
    --arg sni "${SNI_DEFAULT}" \
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

  ensure_cmds curl jq openssl unzip
  vless_normalize_prefix
  ensure_system_user "${VLESS_USER}" "${VLESS_HOME_DIR}"

  [ -x "${XRAY_BIN}" ] || vless_install_xray_binary "$arch"
  vless_install_gateway_binary "$arch"
  vless_install_services
  write_selfsigned_cert "${VLESS_CONFIG_DIR}" "${VLESS_CERT_PATH}" "${VLESS_KEY_PATH}" "${VLESS_USER}"

  FINGERPRINT=$(get_machine_fingerprint "${VLESS_CERT_PATH}" "${VLESS_FP_PATH}")
  TOKEN=$(panel_get_token "${INSTALL_KEY}" "${FINGERPRINT}")
  [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ] || log_error "获取授权TOKEN失败，请检查机场地址、密钥和指纹"

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

  if [ "$SILENT" -eq 0 ]; then
    echo
    echo "-------------------------------------"
    echo "✅ VLESS (Xray + Gateway) 节点安装完成!"
    echo "-------------------------------------"
    echo "系统/服务管理器: ${OS_FAMILY} / ${INIT_SYSTEM}"
    echo "Xray 服务状态: $(get_service_status xray-backend)"
    echo "Gateway 服务状态: $(get_service_status airport-gateway)"
    echo "节点 ID: ${NODE_ID}"
    echo "自动解析域名: ${AUTO_DNS_BOOL}"
    echo "监听端口 (TCP): ${LISTEN_PORT}"
    echo "节点 UUID: ${NODE_UUID}"
    echo "鉴权前缀: ${PATH_PREFIX}"
    echo "配置目录: ${VLESS_CONFIG_DIR}"
    echo "-------------------------------------"
  fi
}

# --- Main Logic ---

main() {
  parse_args "$@"
  require_root
  detect_os_pm
  detect_init_system

  if [ "$SILENT" -eq 0 ] && [ -t 1 ]; then
    clear || true
    printf '%s\n\n' "-- GuaPlus Airport Unified Installer v${VERSION} --"
  fi

  resolve_protocol
  prompt_if_empty PANEL_BASE "请输入机场地址: "
  prompt_if_empty INSTALL_KEY "请输入安装密钥: "
  prompt_if_empty NODE_NAME "请输入节点名称: "
  prompt_if_empty DOMAIN "请输入节点域名: "
  resolve_auto_dns

  PANEL_BASE="${PANEL_BASE%/}"

  if [ -z "$PANEL_BASE" ] || [ -z "$INSTALL_KEY" ] || [ -z "$NODE_NAME" ] || [ -z "$DOMAIN" ]; then
    log_error "所有必填输入项都不能为空"
  fi

  PANEL_INSTALL_API="${PANEL_BASE}/api/v1/install"
  PANEL_VERIFY_API="${PANEL_BASE}/api/v1/verify"

  case "$PROTOCOL" in
    hysteria2) run_hysteria2_install ;;
    vless)     run_vless_install ;;
  esac
}

main "$@"
