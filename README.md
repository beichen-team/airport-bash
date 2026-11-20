# airport-bash
【呱呱机场】hysteria2一键安装脚本

## 安装脚本
```
# 静默安装（推荐）
# Debian / Ubuntu / CentOS
curl -fsSL https://raw.githubusercontent.com/beichen-team/airport-bash/main/hysteria2/install.sh | sh -s -- -s \
  -u "https://airport.beichen.de" \
  -k "your_install_key" \
  -n "JP-Node-01" \
  -d "jp1.example.com"

# Alpine Linux
wget -qO- https://raw.githubusercontent.com/beichen-team/airport-bash/main/hysteria2/install.sh | sh -s -- -s \
  -u "https://airport.beichen.de" \
  -k "your_install_key" \
  -n "JP-Node-01" \
  -d "jp1.example.com"

# 交互式安装
# Debian / Ubuntu / CentOS
curl -fsSL https://raw.githubusercontent.com/beichen-team/airport-bash/main/hysteria2/install.sh -o install.sh && sh install.sh

# Alpine Linux
wget -qO install.sh https://raw.githubusercontent.com/beichen-team/airport-bash/main/hysteria2/install.sh && sh install.sh
```

## 卸载脚本
```
# 静默卸载（无常规输出）
# Debian / Ubuntu / CentOS
curl -fsSL https://raw.githubusercontent.com/beichen-team/airport-bash/main/hysteria2/uninstall.sh | sh -s -- -s

# Alpine Linux
wget -qO- https://raw.githubusercontent.com/beichen-team/airport-bash/main/hysteria2/uninstall.sh | sh -s -- -s


#普通卸载（显示卸载日志）
# Debian / Ubuntu / CentOS
curl -fsSL https://raw.githubusercontent.com/beichen-team/airport-bash/main/hysteria2/uninstall.sh | sh

# Alpine Linux
wget -qO- https://raw.githubusercontent.com/beichen-team/airport-bash/main/hysteria2/uninstall.sh | sh
```