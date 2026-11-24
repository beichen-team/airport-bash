# airport-bash
【北辰机场】hysteria2一键安装脚本

## Debian / Ubuntu 安装

### 1. 准备下载工具

```bash
apt-get update
apt-get install -y curl ca-certificates
```

脚本运行时会按所选协议检查并安装其他依赖：

- Hysteria2：`curl`、`jq`、`openssl`
- VLESS：`curl`、`jq`、`openssl`、`unzip`

### 2. 在线交互式安装

直接执行以下命令：

```bash
curl -fsSL https://raw.githubusercontent.com/beichen-team/airport-bash/refs/heads/main/i.sh | sh -s
```

按照提示选择协议并填写面板地址、安装密钥、节点名称和域名，最后选择是否自动解析域名。

### 3. 在线指定参数安装

**安装 Hysteria2：**

```bash
curl -fsSL https://raw.githubusercontent.com/beichen-team/airport-bash/refs/heads/main/i.sh | sh -s -- \
  --type hysteria2 \
  --url "https://airport.example.com" \
  --key "你的安装密钥" \
  --name "HK-HY2-01" \
  --domain "hy2-hk1.example.com" \
  --port 3389 \
  --auto-dns 1
```

**安装 VLESS：**

```bash
curl -fsSL https://raw.githubusercontent.com/beichen-team/airport-bash/refs/heads/main/i.sh | sh -s -- \
  --type vless \
  --url "https://airport.example.com" \
  --key "你的安装密钥" \
  --name "HK-VLESS-01" \
  --domain "vl-hk1.example.com" \
  --port 3389 \
  --auto-dns 1
```

`--auto-dns 1` 表示启用自动解析；改为 `--auto-dns 0` 或使用 `--no-dns` 表示关闭。若不指定该参数，脚本仍会询问是否启用自动解析。

### 4. 下载脚本后本地安装

适合需要先保存脚本、检查内容或重复执行的场景：

```bash
curl -fL https://raw.githubusercontent.com/beichen-team/airport-bash/refs/heads/main/i.sh -o /root/i.sh
chmod +x /root/i.sh
```

交互式安装：

```bash
sh /root/i.sh
```

指定参数安装：

```bash
sh /root/i.sh \
  --type vless \
  --url "https://airport.example.com" \
  --key "你的安装密钥" \
  --name "HK-VLESS-01" \
  --domain "vl-hk1.example.com" \
  --port 3389 \
  --auto-dns 1
```

## Alpine Linux 安装

### 1. 准备下载工具

```sh
apk update
apk add --no-cache curl ca-certificates
```

脚本运行时会按所选协议检查并安装其他依赖：

- Hysteria2：`curl`、`jq`、`openssl`
- VLESS：`curl`、`jq`、`openssl`、`unzip`

### 2. 在线交互式安装

```sh
curl -fsSL https://raw.githubusercontent.com/beichen-team/airport-bash/refs/heads/main/i.sh | sh -s
```

按照终端提示完成协议、面板信息、节点信息和 DNS 选项的填写。

### 3. 在线指定参数安装

**安装 Hysteria2：**

```sh
curl -fsSL https://raw.githubusercontent.com/beichen-team/airport-bash/refs/heads/main/i.sh | sh -s -- \
  --type hysteria2 \
  --url "https://airport.example.com" \
  --key "你的安装密钥" \
  --name "HK-HY2-01" \
  --domain "hy2-hk1.example.com" \
  --port 3389 \
  --auto-dns 1
```

**安装 VLESS：**

```sh
curl -fsSL https://raw.githubusercontent.com/beichen-team/airport-bash/refs/heads/main/i.sh | sh -s -- \
  --type vless \
  --url "https://airport.example.com" \
  --key "你的安装密钥" \
  --name "HK-VLESS-01" \
  --domain "vl-hk1.example.com" \
  --port 3389 \
  --auto-dns 1
```

### 4. 下载脚本后本地安装

```sh
curl -fL https://raw.githubusercontent.com/beichen-team/airport-bash/refs/heads/main/i.sh -o /root/i.sh
chmod +x /root/i.sh
```

交互式安装：

```sh
sh /root/i.sh
```

指定参数安装：

```sh
sh /root/i.sh \
  --type vless \
  --url "https://airport.example.com" \
  --key "你的安装密钥" \
  --name "HK-VLESS-01" \
  --domain "vl-hk1.example.com" \
  --port 3389 \
  --auto-dns 1
```

## 命令行参数

所有参数均可在在线管道安装和本地脚本安装时使用。

| 参数 | 说明 | 默认值 |
| --- | --- | --- |
| `-t`, `--type` | 协议：`hy2`、`hysteria2` 或 `vless` | 未指定时交互选择，默认 Hysteria2 |
| `-u`, `--url` | 机场面板地址 | 交互输入 |
| `-k`, `--key` | 安装密钥 | 交互输入 |
| `-n`, `--name` | 节点名称 | 交互输入 |
| `-d`, `--domain` | 节点域名 | 交互输入 |
| `-p`, `--port` | 对外监听端口 | `3389` |
| `--sni` | 自签名证书 SNI | `www.bing.com` |
| `--prefix` | VLESS 鉴权路径前缀 | `/w/` |
| `--auto-dns 1\|0` | 是否启用 Cloudflare 自动解析 | 未指定时交互询问 |
| `--no-dns` | 关闭自动解析，等同于 `--auto-dns 0` | - |
| `-h`, `--help` | 显示帮助 | - |

注意：

- `curl ... | sh -s -- 参数...` 中，`sh -s --` 的 `-s` 是 Shell 从标准输入读取脚本的语法，**不是静默安装参数，不要删除**。
- 脚本没有静默安装模式，安装过程会显示日志和下载进度。
- 如果希望全程不再询问，请提供全部必填参数，并明确指定 `--auto-dns 1` 或 `--no-dns`。
- 未提供必填参数时，脚本会尝试从终端读取输入；在没有可用终端的环境中会报错退出。

查看当前脚本支持的完整帮助：

```bash
sh i.sh --help
```

## 环境变量安装

除了命令行参数，也可以通过环境变量传入配置。命令行参数与环境变量均受脚本支持。

| 环境变量 | 对应参数 | 说明 |
| --- | --- | --- |
| `PROTOCOL` | `--type` | `hysteria2` 或 `vless` |
| `PANEL_BASE` | `--url` | 面板地址 |
| `INSTALL_KEY` | `--key` | 安装密钥 |
| `NODE_NAME` | `--name` | 节点名称 |
| `DOMAIN` | `--domain` | 节点域名 |
| `LISTEN_PORT` | `--port` | 对外监听端口，默认 `3389` |
| `SNI` | `--sni` | 证书 SNI，默认 `www.bing.com` |
| `PATH_PREFIX` | `--prefix` | VLESS 鉴权路径前缀，默认 `/w/` |
| `AUTO_DNS` | `--auto-dns` | 自动解析开关，`1` 开启、`0` 关闭 |
| `XRAY_INTERNAL_PORT` | 无命令行参数 | VLESS 的 Xray 本机监听端口，默认 `18086` |
| `XRAY_WS_PATH` | 无命令行参数 | VLESS 的 Xray WebSocket 路径，默认 `/ws` |

示例：

```bash
curl -fsSL https://raw.githubusercontent.com/beichen-team/airport-bash/refs/heads/main/i.sh | \
  PROTOCOL=vless \
  PANEL_BASE="https://airport.example.com" \
  INSTALL_KEY="你的安装密钥" \
  NODE_NAME="HK-VLESS-01" \
  DOMAIN="vl-hk1.example.com" \
  LISTEN_PORT=3389 \
  AUTO_DNS=1 \
  sh -s
```

## 服务管理与日志查询

安装完成后，服务会设置为开机启动并立即启动。根据系统使用的服务管理器选择对应命令。

### Debian / Ubuntu（systemd）

#### Hysteria2

| 操作 | 命令 |
| --- | --- |
| 查看服务状态 | `systemctl status hysteria-server --no-pager` |
| 仅查看运行状态 | `systemctl is-active hysteria-server` |
| 实时跟踪日志 | `journalctl -u hysteria-server -f` |
| 查看最近 100 行日志 | `journalctl -u hysteria-server -n 100 --no-pager` |
| 查看本次启动以来的日志 | `journalctl -u hysteria-server -b --no-pager` |
| 重启服务 | `systemctl restart hysteria-server` |
| 启动服务 | `systemctl start hysteria-server` |
| 停止服务 | `systemctl stop hysteria-server` |
| 设置开机启动 | `systemctl enable hysteria-server` |
| 取消开机启动 | `systemctl disable hysteria-server` |

#### VLESS（Xray + Gateway）

VLESS 由两个服务组成：`xray-backend` 是本机 WebSocket 后端，`airport-gateway` 是对外入口网关。

| 操作 | 命令 |
| --- | --- |
| 查看 Xray 状态 | `systemctl status xray-backend --no-pager` |
| 查看 Gateway 状态 | `systemctl status airport-gateway --no-pager` |
| 同时查看两个服务状态 | `systemctl status xray-backend airport-gateway --no-pager` |
| 查看 Xray 实时日志 | `journalctl -u xray-backend -f` |
| 查看 Gateway 实时日志 | `journalctl -u airport-gateway -f` |
| 同时跟踪两个服务日志 | `journalctl -u xray-backend -u airport-gateway -f` |
| 查看 Xray 最近 100 行日志 | `journalctl -u xray-backend -n 100 --no-pager` |
| 查看 Gateway 最近 100 行日志 | `journalctl -u airport-gateway -n 100 --no-pager` |
| 重启两个服务 | `systemctl restart xray-backend && systemctl restart airport-gateway` |
| 启动两个服务 | `systemctl start xray-backend && systemctl start airport-gateway` |
| 停止两个服务 | `systemctl stop airport-gateway && systemctl stop xray-backend` |
| 设置两个服务开机启动 | `systemctl enable xray-backend airport-gateway` |
| 取消两个服务开机启动 | `systemctl disable xray-backend airport-gateway` |

重启 VLESS 时先重启 Xray 后端，再重启 Gateway；停止时建议先停止 Gateway，再停止 Xray。

### Alpine Linux（OpenRC）

OpenRC 的服务管理命令使用 `rc-service`，开机启动项使用 `rc-update`。脚本将标准输出和错误输出分别写入日志文件。

#### Hysteria2

| 操作 | 命令 |
| --- | --- |
| 查看服务状态 | `rc-service hysteria-server status` |
| 查看最近 100 行标准日志 | `tail -n 100 /var/log/hysteria-server.log` |
| 查看最近 100 行错误日志 | `tail -n 100 /var/log/hysteria-server.err` |
| 实时跟踪标准和错误日志 | `tail -f /var/log/hysteria-server.log /var/log/hysteria-server.err` |
| 重启服务 | `rc-service hysteria-server restart` |
| 启动服务 | `rc-service hysteria-server start` |
| 停止服务 | `rc-service hysteria-server stop` |
| 设置开机启动 | `rc-update add hysteria-server default` |
| 取消开机启动 | `rc-update del hysteria-server default` |

#### VLESS（Xray + Gateway）

| 操作 | 命令 |
| --- | --- |
| 查看 Xray 状态 | `rc-service xray-backend status` |
| 查看 Gateway 状态 | `rc-service airport-gateway status` |
| 查看 Xray 标准日志 | `tail -n 100 /var/log/xray-backend.log` |
| 查看 Xray 错误日志 | `tail -n 100 /var/log/xray-backend.err` |
| 查看 Gateway 标准日志 | `tail -n 100 /var/log/airport-gateway.log` |
| 查看 Gateway 错误日志 | `tail -n 100 /var/log/airport-gateway.err` |
| 实时跟踪 VLESS 全部日志 | `tail -f /var/log/xray-backend.log /var/log/xray-backend.err /var/log/airport-gateway.log /var/log/airport-gateway.err` |
| 重启两个服务 | `rc-service xray-backend restart && rc-service airport-gateway restart` |
| 启动两个服务 | `rc-service xray-backend start && rc-service airport-gateway start` |
| 停止两个服务 | `rc-service airport-gateway stop && rc-service xray-backend stop` |
| 设置两个服务开机启动 | `rc-update add xray-backend default && rc-update add airport-gateway default` |
| 取消两个服务开机启动 | `rc-update del airport-gateway default && rc-update del xray-backend default` |

查看 OpenRC 当前运行级别中的服务：

```sh
rc-update show
```

### 常用排查命令

查看端口监听情况（系统已安装 `ss` 时）：

```sh
ss -lntup
```

查看进程：

```sh
ps aux | grep -E 'hysteria|xray|airport-gateway' | grep -v grep
```

如果只需要确认服务是否运行，优先使用 `systemctl status`（systemd）或 `rc-service <服务名> status`（OpenRC）；排查启动失败时，再查看对应日志。

## 配置文件与端口

### Hysteria2

| 项目 | 路径 / 默认值 |
| --- | --- |
| 程序 | `/usr/local/bin/hysteria` |
| 配置目录 | `/etc/hysteria/` |
| 主配置文件 | `/etc/hysteria/config.yaml` |
| 自签名证书 | `/etc/hysteria/cert.crt` |
| 私钥 | `/etc/hysteria/private.key` |
| 服务名 | `hysteria-server` |
| 默认监听端口 | `3389/UDP` |

### VLESS（Xray + Gateway）

| 项目 | 路径 / 默认值 |
| --- | --- |
| Xray 程序 | `/usr/local/bin/xray` |
| Gateway 程序 | `/usr/local/bin/airport-gateway` |
| 配置目录 | `/etc/xray-gate/` |
| Xray 配置 | `/etc/xray-gate/xray.json` |
| Gateway 环境配置 | `/etc/xray-gate/gateway.env` |
| 自签名证书 | `/etc/xray-gate/cert.crt` |
| 私钥 | `/etc/xray-gate/private.key` |
| 服务名 | `xray-backend`、`airport-gateway` |
| 对外默认监听端口 | `3389/TCP` |
| Xray 本机上游端口 | `127.0.0.1:18086` |
| Xray WebSocket 路径 | `/ws` |
| VLESS 鉴权路径前缀 | `/w/` |

脚本还会为流量统计服务随机生成一个 `20000` 至 `60000` 范围内的端口，并将其写入对应配置文件。需要核对该端口时，可查看：

```bash
# Hysteria2
cat /etc/hysteria/config.yaml

# VLESS
cat /etc/xray-gate/gateway.env
```

请勿随意删除或覆盖配置目录中的证书、私钥和配置文件。重新安装时脚本会在证书文件已存在的情况下复用现有证书。
