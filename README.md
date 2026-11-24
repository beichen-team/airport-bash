# airport-bash
【北辰机场】hysteria2一键安装脚本

## 特性

- **双协议二合一**：支持 Hysteria2（UDP）与 VLESS WS 网关模式（TCP），配置目录、运行用户、证书指纹与服务完全隔离，支持同机共存。
- **按需动态鉴权**：VLESS 通过前置 `airport-gateway` 对接面板 `/api/v1/verify` 实现类 Hy2 的 HTTP Auth，Xray 仅监听本地随机固定 UUID，无需轮询或维护用户表。
- **跨发行版支持**：兼容 Debian / Ubuntu（`systemd`）与 Alpine Linux（`OpenRC`）；Hysteria2 额外兼容 RHEL 系。
- **交互与静默双模式**：支持终端交互式向导与全参数静默自动化部署。
- **可选自动解析**：支持通过 `--auto-dns` / `--no-dns` 控制是否由面板自动写入 Cloudflare DNS 记录。

## 环境要求

| 协议 | 支持系统 | 服务管理器 | 支持架构 | 默认监听端口 |
| :--- | :--- | :--- | :--- | :--- |
| **Hysteria2** | Debian / Ubuntu / Alpine / RHEL 系 | systemd / OpenRC | `amd64` / `arm64` / `arm` / `386` | `3389` (UDP) |
| **VLESS (Xray + Gateway)** | Debian / Ubuntu / Alpine | systemd / OpenRC | `amd64` / `arm64` | `3389` (TCP) |

> 请使用 `root` 权限运行脚本，并确保云厂商安全组与系统防火墙已放行对应端口。

---

## 快速开始

> **注意**：交互式安装请先下载到 `/tmp/install.sh` 再执行，避免 `curl | sh` 占用标准输入导致非交互校验退出。

### 1. Debian / Ubuntu

#### 交互式安装

```sh
curl -fsSL https://raw.githubusercontent.com/beichen-team/airport-bash/refs/heads/main/i.sh -o /tmp/install.sh && sh /tmp/install.sh && rm -f /tmp/install.sh
```

> 若极简系统未预装 `curl`，请先执行 `apt-get update && apt-get install -y curl`。

#### 静默安装

```sh
# 安装 VLESS（默认 3389 端口 + 自动解析 Cloudflare）
curl -fsSL https://raw.githubusercontent.com/beichen-team/airport-bash/refs/heads/main/i.sh | sh -s -- \
  -s -t vless \
  -u "https://airport.beichen.de" \
  -k "你的安装密钥" \
  -n "HK-VLESS-01" \
  -d "vl-hk1.yourdomain.com" \
  -p 3389

# 安装 Hysteria2（--no-dns 关闭自动域名解析）
curl -fsSL https://raw.githubusercontent.com/beichen-team/airport-bash/refs/heads/main/i.sh | sh -s -- \
  -s -t hy2 --no-dns \
  -u "https://airport.beichen.de" \
  -k "你的安装密钥" \
  -n "HK-HY2-01" \
  -d "hy-hk1.yourdomain.com" \
  -p 3389
```

---

### 2. Alpine Linux

最小化 Alpine 默认不含 `curl` 与 CA 根证书，执行前需先安装基础依赖。

#### 交互式安装

```sh
apk add --no-cache curl ca-certificates && curl -fsSL https://raw.githubusercontent.com/beichen-team/airport-bash/refs/heads/main/i.sh -o /tmp/install.sh && sh /tmp/install.sh && rm -f /tmp/install.sh
```

#### 静默安装

```sh
# 安装 VLESS（默认 3389 端口 + 自动解析 Cloudflare）
apk add --no-cache curl ca-certificates && curl -fsSL https://raw.githubusercontent.com/beichen-team/airport-bash/refs/heads/main/i.sh | sh -s -- \
  -s -t vless \
  -u "https://airport.beichen.de" \
  -k "你的安装密钥" \
  -n "HK-VLESS-01" \
  -d "vl-hk1.yourdomain.com" \
  -p 3389

# 安装 Hysteria2（--no-dns 关闭自动域名解析）
apk add --no-cache curl ca-certificates && curl -fsSL https://raw.githubusercontent.com/beichen-team/airport-bash/refs/heads/main/i.sh | sh -s -- \
  -s -t hy2 --no-dns \
  -u "https://airport.beichen.de" \
  -k "你的安装密钥" \
  -n "HK-HY2-01" \
  -d "hy-hk1.yourdomain.com" \
  -p 3389
```

---

### 3. Windows PowerShell 远程一键部署

可直接从本地 Windows PowerShell 通过 SSH 远程触发目标节点安装：

```powershell
$NodeIP = "1.2.3.4"
$RawUrl = "https://raw.githubusercontent.com/beichen-team/airport-bash/refs/heads/main/i.sh"

# Debian 远程静默安装 VLESS
ssh "root@$NodeIP" "curl -fsSL $RawUrl | sh -s -- -s -t vless -u 'https://airport.beichen.de' -k '你的安装密钥' -n 'HK-VLESS-01' -d 'vl-hk1.yourdomain.com' -p 3389"

# Alpine 远程静默安装 VLESS
ssh "root@$NodeIP" "apk add --no-cache curl ca-certificates && curl -fsSL $RawUrl | sh -s -- -s -t vless -u 'https://airport.beichen.de' -k '你的安装密钥' -n 'HK-VLESS-01' -d 'vl-hk1.yourdomain.com' -p 3389"

# Debian 远程交互式安装（需带 -t 分配终端）
ssh -t "root@$NodeIP" "curl -fsSL $RawUrl -o /tmp/install.sh && sh /tmp/install.sh && rm -f /tmp/install.sh"
```

---

## 参数与环境变量说明

所有选项均支持**命令行参数**与**环境变量**两种传入方式（命令行参数优先级更高）：

| 命令行选项 | 环境变量 | 必填 | 默认值 | 说明 |
| :--- | :--- | :---: | :--- | :--- |
| `-t, --type <PROTO>` | `PROTOCOL` | 否 | `hysteria2`（静默） | 协议类型：`hy2` / `hysteria2` / `vless` |
| `-u, --url <URL>` | `PANEL_BASE` | 是 | - | 机场面板基础地址（无需末尾 `/`） |
| `-k, --key <KEY>` | `INSTALL_KEY` | 是 | - | 面板安装密钥 |
| `-n, --name <NAME>` | `NODE_NAME` | 是 | - | 节点展示名称 |
| `-d, --domain <DOMAIN>` | `DOMAIN` | 是 | - | 节点域名（同机双协议请使用不同域名） |
| `-p, --port <PORT>` | `LISTEN_PORT` | 否 | `3389` | 对外监听端口 |
| `--sni <SNI>` | `SNI` | 否 | `www.bing.com` | 自签名证书 CN / 伪装 SNI |
| `--prefix <PREFIX>` | `PATH_PREFIX` | 否 | `/w/` | `[仅 VLESS]` 鉴权路径前缀 |
| `--auto-dns <1\|0>` | `AUTO_DNS` | 否 | `1` | 是否通知面板自动更新 Cloudflare 解析 |
| `--no-dns` | - | 否 | - | 关闭自动域名解析，等同于 `--auto-dns 0` |
| `-s, --silent` | `SILENT` | 否 | `0` | 静默安装模式，禁止交互与常规日志输出 |
| `-h, --help` | - | 否 | - | 查看帮助信息 |

---

## 目录与服务结构

| 协议 | 配置目录 | 可执行文件 | 系统服务名 | 运行用户 |
| :--- | :--- | :--- | :--- | :--- |
| **Hysteria2** | `/etc/hysteria` | `/usr/local/bin/hysteria` | `hysteria-server` | `hysteria` |
| **VLESS** | `/etc/xray-gate` | `/usr/local/bin/xray`<br>`/usr/local/bin/airport-gateway` | `xray-backend`<br>`airport-gateway` | `xraygate` |

- VLESS 模式下，Xray 仅监听 `127.0.0.1:18086`（明文 WS，路径 `/ws`），所有外部连接必须经过 `airport-gateway` 完成 TLS 终结与后端 HTTP Auth 校验。
- 证书指纹分别持久化保存在 `/etc/hysteria/fingerprint.sha256` 与 `/etc/xray-gate/fingerprint.sha256`。

---

## 日常运维与日志排查

### Debian / Ubuntu (`systemd`)

```sh
# 查看服务状态
systemctl status hysteria-server
systemctl status xray-backend airport-gateway

# 查看实时日志
journalctl -u hysteria-server -f
journalctl -u airport-gateway -f
journalctl -u xray-backend -f

# 重启服务
systemctl restart xray-backend airport-gateway
```

### Alpine Linux (`OpenRC`)

```sh
# 查看服务状态
rc-service hysteria-server status
rc-service xray-backend status
rc-service airport-gateway status

# 查看日志
tail -f /var/log/hysteria-server.log /var/log/hysteria-server.err
tail -f /var/log/airport-gateway.log /var/log/airport-gateway.err
tail -f /var/log/xray-backend.log /var/log/xray-backend.err

# 重启服务
rc-service xray-backend restart && rc-service airport-gateway restart
```
