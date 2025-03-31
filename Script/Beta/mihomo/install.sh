#!/bin/bash
#!name = mihomo 一键安装脚本
#!desc = 安装 & 配置
#!date = 2025-03-31 16:45:22
#!author = ChatGPT

# 终止脚本执行遇到错误时退出，并启用管道错误检测
set -e -o pipefail

#############################
#         颜色变量         #
#############################
red="\033[31m"    # 红色
green="\033[32m"  # 绿色
yellow="\033[33m" # 黄色
blue="\033[34m"   # 蓝色
cyan="\033[36m"   # 青色
reset="\033[0m"   # 重置颜色

#############################
#       全局变量定义       #
#############################
sh_ver="1.0.0"
use_cdn=false
distro="unknown"  # 系统类型：debian, ubuntu, alpine, fedora
arch=""           # 系统架构
arch_raw=""       # 原始架构信息

#############################
#       系统检测函数       #
#############################
check_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            debian|ubuntu)
                distro="$ID"
                pkg_update="apt update && apt upgrade -y"
                pkg_install="apt install -y"
                service_enable() { systemctl enable mihomo; }
                service_restart() { systemctl daemon-reload; systemctl start mihomo; }
                ;;
            alpine)
                distro="alpine"
                pkg_update="apk update && apk upgrade"
                pkg_install="apk add"
                service_enable() { rc-update add mihomo default; }
                service_restart() { rc-service mihomo restart; }
                ;;
            fedora)
                distro="fedora"
                pkg_update="dnf upgrade --refresh -y"
                pkg_install="dnf install -y"
                service_enable() { systemctl enable mihomo; }
                service_restart() { systemctl restart mihomo; }
                ;;
            *)
                echo -e "${red}不支持的系统：${ID}${reset}"
                exit 1
                ;;
        esac
    else
        echo -e "${red}无法识别当前系统类型${reset}"
        exit 1
    fi
}

#############################
#       网络检测函数       #
#############################
check_network() {
    if ! curl -s --head --fail --connect-timeout 3 -o /dev/null "https://www.facebook.com"; then
        use_cdn=true
    fi
}

#############################
#        URL 处理函数       #
#############################
get_url() {
    local url=$1
    local final_url
    if [ "$use_cdn" = true ]; then
        final_url="https://gh-proxy.com/${url#http*://}"
    else
        final_url="$url"
    fi
    if ! curl --silent --head --fail --connect-timeout 3 -L "$final_url" -o /dev/null; then
        echo -e "${red}连接失败，可能是网络或代理站点不可用，请检查后重试${reset}" >&2
        return 1
    fi

    echo "$final_url"
}

#############################
#     系统架构检测函数     #
#############################
get_schema() {
    arch_raw=$(uname -m)
    case "$arch_raw" in
        x86_64)
            arch="amd64"
            ;;
        x86|i686|i386)
            arch="386"
            ;;
        aarch64|arm64)
            arch="arm64"
            ;;
        armv7l)
            arch="armv7"
            ;;
        s390x)
            arch="s390x"
            ;;
        *)
            echo -e "${red}不支持的架构：${arch_raw}${reset}"
            exit 1
            ;;
    esac
}

#############################
#    系统更新及安装函数    #
#############################
update_system() {
    eval "$pkg_update"
    eval "$pkg_install curl git gzip wget nano iptables tzdata jq unzip"
}

#############################
#    IPv4/IPv6 转发检查    #
#############################
check_ip_forward() {
    local sysctl_file="/etc/sysctl.conf"
    # 检查 IPv4 转发
    sysctl net.ipv4.ip_forward | grep -q "1" || {
        sysctl -w net.ipv4.ip_forward=1
        echo "net.ipv4.ip_forward=1" >> "$sysctl_file"
    }
    # 检查 IPv6 转发
    sysctl net.ipv6.conf.all.forwarding | grep -q "1" || {
        sysctl -w net.ipv6.conf.all.forwarding=1
        echo "net.ipv6.conf.all.forwarding=1" >> "$sysctl_file"
    }
    sysctl -p > /dev/null
}

#############################
#      远程版本获取函数     #
#############################
download_version() {
    local version_url
    version_url=$(get_url "https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/version.txt")
    version=$(curl -sSL "$version_url") || {
        echo -e "${red}获取 mihomo 远程版本失败${reset}"
        exit 1
    }
}

#############################
#     mihomo 下载函数      #
#############################
download_mihomo() {
    local download_url
    local version_file="/root/mihomo/version.txt"
    local filename="mihomo-linux-${arch}-${version}.gz"

    # 获取远程版本信息
    download_version

    # 针对 amd64 架构使用兼容性文件
    if [ "$arch" == "amd64" ]; then
        filename="mihomo-linux-${arch}-compatible-${version}.gz"
    fi

    download_url=$(get_url "https://github.com/MetaCubeX/mihomo/releases/download/Prerelease-Alpha/${filename}")
    wget -t 3 -T 30 -O "$filename" "$download_url" || {
        echo -e "${red}mihomo 下载失败，请检查网络后重试${reset}"
        exit 1
    }

    gunzip "$filename" || {
        echo -e "${red}mihomo 解压失败${reset}"
        exit 1
    }

    # 检测解压后的文件并移动到 mihomo 可执行文件
    if [ -f "mihomo-linux-${arch}-compatible-${version}" ]; then
        mv "mihomo-linux-${arch}-compatible-${version}" mihomo
    elif [ -f "mihomo-linux-${arch}-${version}" ]; then
        mv "mihomo-linux-${arch}-${version}" mihomo
    else
        echo -e "${red}找不到解压后的文件${reset}"
        exit 1
    fi

    chmod +x mihomo
    echo "$version" > "$version_file"
}

#############################
#   系统服务配置下载函数    #
#############################
download_service() {
    if [ "$distro" = "alpine" ]; then
        local service_file="/etc/init.d/mihomo"
        local service_url
        service_url=$(get_url "https://raw.githubusercontent.com/Abcd789JK/Tools/refs/heads/main/Service/mihomo.openrc")
        wget -t 3 -T 30 -O "$service_file" "$service_url" || {
            echo -e "${red}Alpine 服务下载失败${reset}"
            exit 1
        }
        chmod +x "$service_file"
        service_enable
    else
        local system_file="/etc/systemd/system/mihomo.service"
        local service_url
        service_url=$(get_url "https://raw.githubusercontent.com/Abcd789JK/Tools/refs/heads/main/Service/mihomo.service")
        wget -t 3 -T 30 -O "$system_file" "$service_url" || {
            echo -e "${red}系统服务下载失败，请检查网络后重试${reset}"
            exit 1
        }
        chmod +x "$system_file"
        service_enable
    fi
}

#############################
#     管理面板文件下载      #
#############################
download_wbeui() {
    local wbe_file="/root/mihomo/ui"
    local wbe_url="https://github.com/metacubex/metacubexd.git"
    git clone "$wbe_url" -b gh-pages "$wbe_file" || {
        echo -e "${red}管理面板下载失败，请检查网络后重试${reset}"
        exit 1
    }
}

#############################
#    管理脚本下载函数      #
#############################
download_shell() {
    local shell_file="/usr/bin/mihomo"
    local sh_url
    sh_url=$(get_url "https://raw.githubusercontent.com/Abcd789JK/Tools/refs/heads/main/Script/Beta/mihomo/mihomo.sh")
    [ -f "$shell_file" ] && rm -f "$shell_file"
    wget -t 3 -T 30 -O "$shell_file" "$sh_url" || {
        echo -e "${red}mihomo 管理脚本下载失败，请检查网络后重试${reset}"
        exit 1
    }
    chmod +x "$shell_file"
    hash -r
}

#############################
#       配置文件生成函数     #
#############################
config_mihomo() {
    local folders="/root/mihomo"
    local config_file="/root/mihomo/config.yaml"
    local iface ipv4 ipv6 config_url

    # 获取默认网络接口及其 IP 地址
    iface=$(ip route | awk '/default/ {print $5}')
    ipv4=$(ip addr show "$iface" | awk '/inet / {print $2}' | cut -d/ -f1)
    ipv6=$(ip addr show "$iface" | awk '/inet6 / {print $2}' | cut -d/ -f1)

    # 提示用户选择运行模式
    echo -e "${cyan}-------------------------${reset}"
    echo -e "${yellow}1. TUN 模式${reset}"
    echo -e "${yellow}2. TProxy 模式${reset}"
    echo -e "${cyan}-------------------------${reset}"
    read -p "$(echo -e "${green}请选择运行模式（推荐使用 TUN 模式）请输入选择(1/2): ${reset}")" confirm
    confirm=${confirm:-1}
    case "$confirm" in
        1)
            config_url="https://raw.githubusercontent.com/Abcd789JK/Tools/refs/heads/main/Config/mihomo.yaml"
            ;;
        2)
            config_url="https://raw.githubusercontent.com/Abcd789JK/Tools/refs/heads/main/Config/mihomotp.yaml"
            ;;
        *)
            echo -e "${red}无效选择，跳过配置文件下载。${reset}"
            return
            ;;
    esac

    config_url=$(get_url "$config_url")
    wget -t 3 -T 30 -q -O "$config_file" "$config_url" || {
        echo -e "${red}配置文件下载失败${reset}"
        exit 1
    }

    # 添加机场订阅配置
    local proxy_providers="proxy-providers:"
    local counter=1
    while true; do
        read -p "请输入机场的订阅连接：" airport_url
        read -p "请输入机场的名称：" airport_name
        proxy_providers="${proxy_providers}
  provider_$(printf "%02d" $counter):
    url: \"${airport_url}\"
    type: http
    interval: 86400
    health-check: {enable: true, url: \"https://www.youtube.com/generate_204\", interval: 300}
    override:
      additional-prefix: \"[${airport_name}]\""
        counter=$((counter + 1))
        read -p "$(echo -e "${yellow}是否继续输入订阅？（输入 n 或 N 结束）：${reset}")" cont
        if [[ "$cont" =~ ^[nN]$ ]]; then
            break
        fi
    done

    # 在配置文件中插入机场配置
    awk -v providers="$proxy_providers" '
      /^# 机场配置/ { print; print providers; next }
      { print }
    ' "$config_file" > temp.yaml && mv temp.yaml "$config_file"

    service_restart

    echo -e "${green}配置完成，配置文件已保存到：${yellow}${config_file}${reset}"
    echo -e "${red}mihomo 管理面板地址和管理命令：${reset}"
    echo -e "${cyan}=========================${reset}"
    echo -e "${green}http://$ipv4:9090/ui${reset}"
    echo -e "${green}命令：mihomo 进入管理菜单${reset}"
    echo -e "${cyan}=========================${reset}"
}

#############################
#       安装主流程函数      #
#############################
install_mihomo() {
    local folders="/root/mihomo"
    rm -rf "$folders"
    mkdir -p "$folders" && cd "$folders"

    check_distro
    echo -e "${yellow}当前系统版本：${reset}[ ${green}${distro}${reset} ]"

    get_schema
    echo -e "${yellow}当前系统架构：${reset}[ ${green}${arch_raw}${reset} ]"

    download_version
    echo -e "${yellow}当前软件版本：${reset}[ ${green}${version}${reset} ]"

    download_mihomo
    download_service
    download_wbeui
    download_shell

    read -p "$(echo -e "${green}安装完成，是否下载配置文件\n${yellow}也可上传自定义配置到 ${folders} (文件名必须为 config.yaml)\n${red}是否继续${green}(y/n): ${reset}")" confirm
    case "$confirm" in
        [Yy]*)
            config_mihomo
            ;;
        [Nn]*)
            echo -e "${green}跳过配置文件下载${reset}"
            ;;
         *)
            echo -e "${red}无效选择，跳过配置文件下载${reset}"
            ;;
    esac

    # 删除安装脚本本身
    rm -f /root/install.sh
}

#############################
#           主流程          #
#############################
check_distro
check_network
update_system
check_ip_forward
install_mihomo
