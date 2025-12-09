#!/usr/bin/env bash
set -euo pipefail
export LANG=en_US.UTF-8

SNI="www.bing.com"

VERSION="1.0.0"

CONFIG_DIR="/etc/hysteria"
CERT_PATH="${CONFIG_DIR}/cert.crt"
KEY_PATH="${CONFIG_DIR}/private.key"
CONFIG_PATH="${CONFIG_DIR}/config.yaml"

EXECUTABLE_INSTALL_PATH="/usr/local/bin/hysteria"
SYSTEMD_SERVICES_DIR="/etc/systemd/system"
HYSTERIA_USER="hysteria"
HYSTERIA_HOME_DIR="/var/lib/${HYSTERIA_USER}"

REPO_API="https://api.github.com/repos/apernet/hysteria"
REPO_DL_BASE="https://github.com/apernet/hysteria/releases/download"

require_root() { [[ ${EUID:-1000} -eq 0 ]] || { echo "Please run this script as root."; exit 1; }; }
need_cmd() { command -v "$1" >/dev/null 2>&1; }
trim() { echo "${1:-}" | tr -d '[:space:]'; }

detect_os_pm() {
  local sys s
  sys="$( (grep -i pretty_name /etc/os-release 2>/dev/null | cut -d '"' -f2) || true )"
  sys="${sys:-$( (cat /etc/issue 2>/dev/null | head -n1 | cut -d '\' -f1) || true )}"
  s="$(echo "${sys}" | tr '[:upper:]' '[:lower:]')"
  if [[ "$s" =~ debian|ubuntu ]]; then
    PM_UPDATE="apt-get update -y"
    PM_INSTALL="apt-get install -y"
  elif [[ "$s" =~ centos|red\ hat|alma|rocky|oracle\ linux|amazon\ linux|fedora ]]; then
    PM_UPDATE="yum -y update"
    PM_INSTALL="yum -y install"
  else
    echo "Unsupported OS: ${sys}"
    exit 1
  fi
}

ensure_pkgs() { ${PM_UPDATE} >/dev/null 2>&1 || true; ${PM_INSTALL} "$@" >/dev/null 2>&1; }

ensure_cmds() {
  local missing=() c
  for c in "$@"; do need_cmd "$c" || missing+=("$c"); done
  ((${#missing[@]}==0)) && return 0

  echo "Missing commands: ${missing[*]}" >&2
  echo "Attempting to install dependencies..." >&2

  local pkgs=()
  for c in "${missing[@]}"; do
    case "$c" in
      curl) pkgs+=(curl) ;;
      wget) pkgs+=(wget) ;;
      openssl) pkgs+=(openssl) ;;
      jq) pkgs+=(jq) ;;
      awk) pkgs+=(gawk) ;;
      getent) pkgs+=(libc-bin) ;;
      *) pkgs+=("$c") ;;
    esac
  done

  ensure_pkgs "${pkgs[@]}"

  for c in "$@"; do
    need_cmd "$c" || { echo "Still missing: $c (please install it manually)"; exit 1; }
  done
}

detect_arch() {
  case "$(uname -m)" in
    i386|i686) echo "386" ;;
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64|armv8*) echo "arm64" ;;
    armv7*|armv6*|armv5*) echo "arm" ;;
    s390x) echo "s390x" ;;
    mips*|mips64*|mipsel*|mipsle*) echo "mipsle" ;;
    *) echo "unsupported" ;;
  esac
}

# Input: aaaa.cccc.com or cccc.com
# Output: DNS_DOMAIN / DNS_SUB
split_fqdn() {
  local fqdn="$1"
  fqdn="$(trim "$fqdn")"
  [[ -n "$fqdn" ]] || return 1

  [[ "$fqdn" == *.* ]] || { echo "Invalid domain format: $fqdn"; return 1; }
  fqdn="${fqdn%.}"

  local dots
  dots="$(awk -F. '{print NF-1}' <<<"$fqdn")"
  if [[ "$dots" -eq 1 ]]; then
    DNS_DOMAIN="$fqdn"
    DNS_SUB="@"
  else
    DNS_DOMAIN="${fqdn#*.}"
    DNS_SUB="${fqdn%%.*}"
  fi
}

ensure_hysteria_user() {
  if ! id "${HYSTERIA_USER}" >/dev/null 2>&1; then
    useradd -r -d "${HYSTERIA_HOME_DIR}" -m "${HYSTERIA_USER}"
  fi
}

get_latest_version() {
  local tag
  tag="$(curl -fsSL -H 'Accept: application/vnd.github+json' "${REPO_API}/releases/latest" | jq -r '.tag_name' | head -n1)"
  [[ -n "$tag" && "$tag" != "null" ]] || return 1
  echo "${tag#app/}"
}

install_hysteria_binary() {
  local os="linux"
  local arch ver url
  arch="$(detect_arch)"
  [[ "$arch" != "unsupported" ]] || { echo "Unsupported architecture: $(uname -m)"; exit 1; }

  ver="$(get_latest_version)" || { echo "Failed to fetch the latest hysteria version (GitHub API)."; exit 1; }
  url="${REPO_DL_BASE}/app/${ver}/hysteria-${os}-${arch}"

  echo "Downloading hysteria: ${url}"
  curl -fsSL -o /tmp/hysteria.bin "${url}"
  install -Dm755 /tmp/hysteria.bin "${EXECUTABLE_INSTALL_PATH}"
  rm -f /tmp/hysteria.bin

  "${EXECUTABLE_INSTALL_PATH}" version || true
}

install_systemd_service() {
  mkdir -p "${SYSTEMD_SERVICES_DIR}"
  cat > "${SYSTEMD_SERVICES_DIR}/hysteria-server.service" <<EOF
[Unit]
Description=Hysteria Server Service (config.yaml)
After=network.target

[Service]
Type=simple
ExecStart=${EXECUTABLE_INSTALL_PATH} server --config ${CONFIG_DIR}/config.yaml
WorkingDirectory=${HYSTERIA_HOME_DIR}
User=${HYSTERIA_USER}
Group=${HYSTERIA_USER}
Environment=HYSTERIA_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload >/dev/null 2>&1 || true
}

install_hysteria_all() {
  ensure_hysteria_user
  if [[ ! -x "${EXECUTABLE_INSTALL_PATH}" ]]; then
    install_hysteria_binary
  fi
  install_systemd_service
  [[ -x "${EXECUTABLE_INSTALL_PATH}" ]] || { echo "Hysteria installation failed: ${EXECUTABLE_INSTALL_PATH} not found."; exit 1; }
}

rand_port() {
  local min_=1024 max_=65535 range_ n port
  range_=$((max_ - min_ + 1))
  is_free() {
    local p="$1"
    if command -v ss >/dev/null 2>&1; then
      ss -lnt | awk '{print $4}' | grep -qE "[:.]$p$" && return 1 || return 0
    elif command -v netstat >/dev/null 2>&1; then
      netstat -lnt 2>/dev/null | awk '{print $4}' | grep -qE "[:.]$p$" && return 1 || return 0
    else
      return 0
    fi
  }
  while :; do
    if [[ -r /dev/urandom ]]; then
      n="$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')"
    else
      n="$RANDOM"
    fi
    port=$((min_ + (n % range_)))
    is_free "$port" && { printf '%s\n' "$port"; return 0; }
  done
}


write_selfsigned_cert() {
  mkdir -p "${CONFIG_DIR}"
  openssl ecparam -genkey -name prime256v1 -out "${KEY_PATH}" >/dev/null 2>&1
  openssl req -new -x509 -days 36500 -key "${KEY_PATH}" -out "${CERT_PATH}" -subj "/CN=${SNI}" >/dev/null 2>&1

  # service runs as hysteria user => allow group read key
  chown root:"${HYSTERIA_USER}" "${CERT_PATH}" "${KEY_PATH}" 2>/dev/null || true
  chmod 644 "${CERT_PATH}" "${KEY_PATH}"
}

write_server_config() {
  local auth_addr="$1" obfs_pwd="$2" traffic_stats_port="$3" traffic_stats_secret="$4"
  cat > "${CONFIG_PATH}" <<EOF
listen: :443

tls:
  cert: ${CERT_PATH}
  key: ${KEY_PATH}

auth:
  type: http
  http:
    url: ${auth_addr}
    insecure: false

obfs:
  type: salamander
  salamander:
    password: ${obfs_pwd}

quic:
  initStreamReceiveWindow: 16777216
  maxStreamReceiveWindow: 16777216
  initConnReceiveWindow: 33554432
  maxConnReceiveWindow: 33554432

trafficStats:
  listen: :${traffic_stats_port}
  secret: ${traffic_stats_secret}
EOF
}

start_service() {
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable hysteria-server >/dev/null 2>&1 || true
  systemctl restart hysteria-server >/dev/null 2>&1 || true
  systemctl is-active --quiet hysteria-server || { echo "Service failed to start: please check 'systemctl status hysteria-server'."; exit 1; }
}

tc_sha256_hex(){ openssl dgst -sha256 -hex | awk '{print $2}'; }

tc_auth() {
  local payload="$1" ts="$2"
  local host="dnspod.intl.tencentcloudapi.com" svc="dnspod" ct="application/json; charset=utf-8"
  local d scope req_hash canon canon_hash str2sign k_date_hex k_svc_hex k_sign_hex sig

  d="$(date -u -d "@$ts" +%F)"
  scope="${d}/${svc}/tc3_request"
  req_hash="$(printf '%s' "$payload" | tc_sha256_hex)"
  canon=$(printf "POST\n/\n\ncontent-type:%s\nhost:%s\n\ncontent-type;host\n%s" "$ct" "$host" "$req_hash")
  canon_hash="$(printf '%s' "$canon" | tc_sha256_hex)"
  str2sign=$(printf "TC3-HMAC-SHA256\n%s\n%s\n%s" "$ts" "$scope" "$canon_hash")

  k_date_hex=$(printf '%s' "$d" | openssl dgst -sha256 -mac HMAC -macopt "key:TC3${TC_SECRET_KEY}" -binary | xxd -p -c 9999)
  k_svc_hex=$(printf '%s' "$svc" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:${k_date_hex}" -binary | xxd -p -c 9999)
  k_sign_hex=$(printf '%s' "tc3_request" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:${k_svc_hex}" -binary | xxd -p -c 9999)
  sig=$(printf '%s' "$str2sign" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:${k_sign_hex}" -hex | awk '{print $2}')

  printf 'TC3-HMAC-SHA256 Credential=%s/%s, SignedHeaders=content-type;host, Signature=%s' \
    "$TC_SECRET_ID" "$scope" "$sig"
}

tc_call() {
  local action="$1" payload="$2"
  local host="dnspod.intl.tencentcloudapi.com" ver="2021-03-23" ct="application/json; charset=utf-8"
  local ts auth
  ts="$(date +%s)"
  auth="$(tc_auth "$payload" "$ts")"

  curl -fsS "https://${host}/" -X POST \
    -H "Content-Type: ${ct}" \
    -H "Host: ${host}" \
    -H "X-TC-Action: ${action}" \
    -H "X-TC-Version: ${ver}" \
    -H "X-TC-Timestamp: ${ts}" \
    -H "Authorization: ${auth}" \
    -d "${payload}"
}

dnspod_get_record_id() {
  local domain="$1" sub="$2" payload resp
  payload="$(printf '{"Domain":"%s","Subdomain":"%s","RecordType":"A","RecordLine":"Default","Limit":100,"Offset":0}' "$domain" "$sub")"
  resp="$(tc_call "DescribeRecordList" "$payload")"
  echo "$resp" | jq -r '
    .Response.RecordList // [] |
    (map(select(.Name=="'"$sub"'" and .Type=="A" and .Line=="Default")) | .[0].RecordId) // empty
  '
}

dnspod_upsert_a() {
  local domain="$1" sub="$2" ip="$3"
  local rid payload
  rid="$(dnspod_get_record_id "$domain" "$sub" || true)"

  if [[ -n "${rid:-}" ]]; then
    payload="$(printf '{"Domain":"%s","SubDomain":"%s","RecordType":"A","RecordLine":"Default","Value":"%s","TTL":%s,"RecordId":%s}' \
      "$domain" "$sub" "$ip" "600" "$rid")"
    tc_call "ModifyRecord" "$payload" >/dev/null
    echo "DNSPod: A record updated."
  else
    payload="$(printf '{"Domain":"%s","SubDomain":"%s","RecordType":"A","RecordLine":"Default","Value":"%s","TTL":%s}' \
      "$domain" "$sub" "$ip" "600")"
    tc_call "CreateRecord" "$payload" >/dev/null
    echo "DNSPod: A record created."
  fi
}

main() {
  require_root
  detect_os_pm
  ensure_cmds curl wget openssl jq awk xxd systemctl hostname

  clear || true

  echo "* Welcome to the GuaPlus Airport hysteria2 installer."
  echo "* Version: $VERSION"
  echo

  local HY_DOMAIN AUTH_ADDR ip
  read -r -p "Domain: " HY_DOMAIN
  HY_DOMAIN="$(trim "$HY_DOMAIN")"
  split_fqdn "$HY_DOMAIN" || exit 1

  read -r -p "Auth Server: " AUTH_ADDR
  AUTH_ADDR="$(trim "$AUTH_ADDR")"
  [[ -n "$AUTH_ADDR" ]] || { echo "Auth Server cannot be empty."; exit 1; }

  read -r -p "TencentCloud SECRET ID: " TC_SECRET_ID
  TC_SECRET_ID="$(trim "$TC_SECRET_ID")"
  [[ -n "$TC_SECRET_ID" ]] || { echo "SECRET ID cannot be empty."; exit 1; }

  read -r -p "TencentCloud SECRET KEY: " TC_SECRET_KEY
  TC_SECRET_KEY="$(trim "$TC_SECRET_KEY")"
  [[ -n "$TC_SECRET_KEY" ]] || { echo "SECRET KEY cannot be empty."; exit 1; }

  ip="$(curl -fsS https://whatismyip.akamai.com)"
  echo "Public IP: $ip"
  dnspod_upsert_a "$DNS_DOMAIN" "$DNS_SUB" "$ip"

  OBFS_PWD="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)"
  TRAFFIC_STATS_SECRET="$(openssl rand -base64 48 | tr -dc 'A-Za-z0-9' | head -c 32)"
  TRAFFIC_STATS_PORT="$(rand_port)"
  
  install_hysteria_all
  write_selfsigned_cert
  write_server_config "$AUTH_ADDR" "$OBFS_PWD" "$TRAFFIC_STATS_PORT" "$TRAFFIC_STATS_SECRET"
  start_service

  echo
  echo "Installation completed."
  echo
  echo "Regional information:"
  echo "Domain: ${HY_DOMAIN}"
  echo "Port: 443"
  echo "SNI: ${SNI}"
  echo "INSECURE: 1"
  echo "OBFS: salamander"
  echo "OBFS_PWD: ${OBFS_PWD}"
  echo "TRAFFIC_STATS_PORT: ${TRAFFIC_STATS_PORT}"
  echo "TRAFFIC_STATS_SECRET: ${TRAFFIC_STATS_SECRET}"
  echo
  echo "Command:"
  echo "Edit the configuration file: ${CONFIG_PATH}"
  echo "Hysteria2 service status: systemctl status hysteria-server --no-pager -l"
}

main "$@"
