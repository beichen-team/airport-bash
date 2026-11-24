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

  echo
  echo "-------------------------------------"
  echo "VLESS (Xray + Gateway) 节点安装完成!"
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
}

# --- Main Logic ---

main() {
  parse_args "$@"
  require_root
  detect_os_pm
  detect_init_system

  printf '%s\n\n' "-- GuaPlus Airport Unified Installer v${VERSION} --"

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

  echo
  echo "安装参数确认:"
  echo "  协议类型: ${PROTOCOL}"
  echo "  面板地址: ${PANEL_BASE}"
  echo "  节点名称: ${NODE_NAME}"
  echo "  节点域名: ${DOMAIN}"
  echo "  监听端口: ${LISTEN_PORT}"
  echo "  自动解析: ${AUTO_DNS_BOOL}"
  echo

  case "$PROTOCOL" in
    hysteria2) run_hysteria2_install ;;
    vless)     run_vless_install ;;
  esac
}

main "$@"
