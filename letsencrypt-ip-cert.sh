#!/usr/bin/env bash
#
# Let's Encrypt 证书申请 & 自动续期脚本 (支持 IP + 域名)
# 基于 acme.sh，适用于 Linux 系统
# 内置 XrayR 部署支持
#
# 用法:
#   chmod +x letsencrypt-ip-cert.sh
#   # IP 证书 (有效期 ~6.66 天，自动频繁续期)
#   sudo ./letsencrypt-ip-cert.sh --ip 1.2.3.4 --deploy xrayr --cert-name node1.test.com
#   # 域名证书 (有效期 90 天)
#   sudo ./letsencrypt-ip-cert.sh --domain node1.test.com --deploy xrayr

set -euo pipefail

# ============================================================
#  颜色输出
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ============================================================
#  默认配置
# ============================================================
TARGET=""                  # IP 或域名
TARGET_TYPE=""             # ip | domain
MODE="standalone"          # standalone | webroot | alpn | dns
WEBROOT_PATH=""
DEPLOY_TYPE=""             # xrayr | nginx | apache | custom | 留空不部署
CERT_NAME=""               # 证书文件名前缀（如 node1.test.com）
CERT_INSTALL_PATH=""
KEY_INSTALL_PATH=""
RELOAD_CMD=""
ACME_HOME="${HOME}/.acme.sh"
ACME_BIN="${ACME_HOME}/acme.sh"
EMAIL=""
RENEW_DAYS=""              # 提前续期天数，IP 默认 3，域名默认 30
FORCE_INSTALL=false
FORCE_ISSUE=false
ECC_KEY=""                 # 留空使用 RSA，设置如 ec-256 使用 ECC
XRAYR_CERT_DIR="/etc/XrayR/cert"

# ============================================================
#  帮助信息
# ============================================================
usage() {
    cat <<'USAGE'
┌──────────────────────────────────────────────────────────────────┐
│       Let's Encrypt 证书申请 & 自动续期脚本 (IP + 域名)          │
├──────────────────────────────────────────────────────────────────┤
│  目标 (二选一):                                                  │
│    --ip <IP>              为公网 IP 申请证书                      │
│    --domain <DOMAIN>      为域名申请证书                          │
│                                                                  │
│  验证模式:                                                       │
│    --mode standalone      内置 HTTP 服务器 (默认, 需 80 端口)     │
│    --mode webroot         使用已有 Web 服务器                     │
│    --mode alpn            TLS-ALPN-01 验证 (需 443 端口)          │
│    --mode dns             DNS 验证 (仅域名可用)                   │
│                                                                  │
│  部署选项:                                                       │
│    --deploy xrayr         部署到 XrayR (/etc/XrayR/cert)         │
│    --deploy nginx         部署到 Nginx                            │
│    --deploy apache        部署到 Apache                           │
│    --deploy custom        自定义路径                              │
│                                                                  │
│  XrayR 部署参数:                                                 │
│    --cert-name <NAME>     证书文件名前缀 (如 node1.test.com)      │
│                           默认使用 IP/域名作为文件名              │
│    --xrayr-cert-dir <DIR> XrayR 证书目录 (默认 /etc/XrayR/cert)  │
│                                                                  │
│  自定义部署参数:                                                 │
│    --cert-path <PATH>     证书安装路径                            │
│    --key-path  <PATH>     私钥安装路径                            │
│    --reload   <CMD>       续期后执行的重载命令                    │
│                                                                  │
│  可选参数:                                                       │
│    --webroot <PATH>       webroot 模式的 Web 根目录               │
│    --email <EMAIL>        注册邮箱（推荐填写）                    │
│    --ecc                  使用 ECC 证书 (ec-256)                  │
│    --force                强制重新申请证书                        │
│    --renew-days <N>       提前 N 天续期                           │
│    -h, --help             显示帮助信息                            │
│                                                                  │
│  XrayR 部署示例:                                                 │
│    # IP 证书，文件名用 node1.test.com                             │
│    sudo ./letsencrypt-ip-cert.sh --ip 1.2.3.4 \                  │
│         --deploy xrayr --cert-name node1.test.com                 │
│                                                                  │
│    # 域名证书                                                     │
│    sudo ./letsencrypt-ip-cert.sh --domain node1.test.com \        │
│         --deploy xrayr                                            │
└──────────────────────────────────────────────────────────────────┘
USAGE
    exit 0
}

# ============================================================
#  参数解析
# ============================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --ip)
            TARGET="$2"; TARGET_TYPE="ip"; shift 2 ;;
        --domain)
            TARGET="$2"; TARGET_TYPE="domain"; shift 2 ;;
        --mode)         MODE="$2";              shift 2 ;;
        --webroot)      WEBROOT_PATH="$2";      shift 2 ;;
        --deploy)       DEPLOY_TYPE="$2";       shift 2 ;;
        --cert-name)    CERT_NAME="$2";         shift 2 ;;
        --cert-path)    CERT_INSTALL_PATH="$2"; shift 2 ;;
        --key-path)     KEY_INSTALL_PATH="$2";  shift 2 ;;
        --reload)       RELOAD_CMD="$2";        shift 2 ;;
        --email)        EMAIL="$2";             shift 2 ;;
        --ecc)          ECC_KEY="ec-256";       shift   ;;
        --force)        FORCE_ISSUE=true;       shift   ;;
        --force-install) FORCE_INSTALL=true;    shift   ;;
        --renew-days)   RENEW_DAYS="$2";        shift 2 ;;
        --xrayr-cert-dir) XRAYR_CERT_DIR="$2"; shift 2 ;;
        -h|--help)      usage ;;
        *)
            error "未知参数: $1"
            usage
            ;;
    esac
done

# ============================================================
#  自动获取公网 IP
# ============================================================
detect_public_ip() {
    local ip=""
    local services=(
        "https://api.ipify.org"
        "https://ifconfig.me"
        "https://ip.sb"
        "https://api.ip.sb/ip"
        "https://icanhazip.com"
        "https://checkip.amazonaws.com"
    )

    for svc in "${services[@]}"; do
        ip=$(curl -s --max-time 5 "$svc" 2>/dev/null | tr -d '[:space:]')
        if [[ -n "$ip" ]] && echo "$ip" | grep -qP '^(\d{1,3}\.){3}\d{1,3}$' 2>/dev/null; then
            echo "$ip"
            return 0
        fi
    done

    return 1
}

# ============================================================
#  校验
# ============================================================
# 未指定目标时，自动检测公网 IP
if [[ -z "$TARGET" ]]; then
    info "未指定 --ip 或 --domain，正在自动检测本机公网 IP ..."
    detected_ip=$(detect_public_ip) || true
    if [[ -n "$detected_ip" ]]; then
        TARGET="$detected_ip"
        TARGET_TYPE="ip"
        info "检测到公网 IP: $TARGET"
    else
        error "无法自动获取公网 IP，请手动指定 --ip 或 --domain"
        exit 1
    fi
fi

if [[ -z "$TARGET_TYPE" ]]; then
    if echo "$TARGET" | grep -qP '^(\d{1,3}\.){3}\d{1,3}$' 2>/dev/null; then
        TARGET_TYPE="ip"
    else
        TARGET_TYPE="domain"
    fi
fi

if [[ "$TARGET_TYPE" == "ip" ]]; then
    if ! echo "$TARGET" | grep -qP '^(\d{1,3}\.){3}\d{1,3}$' 2>/dev/null &&
       ! echo "$TARGET" | grep -qP '^[0-9a-fA-F:]+$' 2>/dev/null; then
        error "IP 地址格式不正确: $TARGET"
        exit 1
    fi
    RENEW_DAYS="${RENEW_DAYS:-3}"
else
    RENEW_DAYS="${RENEW_DAYS:-30}"
fi

if [[ "$MODE" == "webroot" && -z "$WEBROOT_PATH" ]]; then
    error "webroot 模式必须指定 --webroot 参数"
    exit 1
fi

if [[ "$MODE" == "dns" && "$TARGET_TYPE" == "ip" ]]; then
    error "IP 证书不支持 DNS 验证模式，请使用 standalone / webroot / alpn"
    exit 1
fi

if [[ "$DEPLOY_TYPE" == "custom" ]]; then
    if [[ -z "$CERT_INSTALL_PATH" || -z "$KEY_INSTALL_PATH" ]]; then
        error "自定义部署必须指定 --cert-path 和 --key-path"
        exit 1
    fi
fi

CERT_NAME="${CERT_NAME:-$TARGET}"

if [[ $EUID -ne 0 ]]; then
    warn "建议以 root 权限运行此脚本"
fi

# ============================================================
#  根据部署类型设置默认路径
# ============================================================
setup_deploy_defaults() {
    case "$DEPLOY_TYPE" in
        xrayr)
            CERT_INSTALL_PATH="${CERT_INSTALL_PATH:-${XRAYR_CERT_DIR}/${CERT_NAME}.cert}"
            KEY_INSTALL_PATH="${KEY_INSTALL_PATH:-${XRAYR_CERT_DIR}/${CERT_NAME}.key}"
            RELOAD_CMD="${RELOAD_CMD:-systemctl restart XrayR}"
            ;;
        nginx)
            CERT_INSTALL_PATH="${CERT_INSTALL_PATH:-/etc/nginx/ssl/${CERT_NAME}.pem}"
            KEY_INSTALL_PATH="${KEY_INSTALL_PATH:-/etc/nginx/ssl/${CERT_NAME}.key}"
            RELOAD_CMD="${RELOAD_CMD:-systemctl reload nginx}"
            ;;
        apache)
            CERT_INSTALL_PATH="${CERT_INSTALL_PATH:-/etc/apache2/ssl/${CERT_NAME}.pem}"
            KEY_INSTALL_PATH="${KEY_INSTALL_PATH:-/etc/apache2/ssl/${CERT_NAME}.key}"
            RELOAD_CMD="${RELOAD_CMD:-systemctl reload apache2}"
            ;;
        custom)
            ;;
    esac
}

# ============================================================
#  安装 acme.sh
# ============================================================
install_acme() {
    if [[ -f "$ACME_BIN" ]] && [[ "$FORCE_INSTALL" != true ]]; then
        info "acme.sh 已安装: $ACME_BIN"
        info "更新到最新版本..."
        "$ACME_BIN" --upgrade
        return
    fi

    info "正在安装 acme.sh ..."

    if command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y -qq curl socat cron openssl >/dev/null 2>&1
    elif command -v yum &>/dev/null; then
        yum install -y -q curl socat cronie openssl >/dev/null 2>&1
    elif command -v dnf &>/dev/null; then
        dnf install -y -q curl socat cronie openssl >/dev/null 2>&1
    elif command -v apk &>/dev/null; then
        apk add --quiet curl socat openssl
    fi

    local install_cmd="curl -fsSL https://get.acme.sh | sh -s"
    if [[ -n "$EMAIL" ]]; then
        install_cmd+=" email=$EMAIL"
    fi

    eval "$install_cmd"

    if [[ ! -f "$ACME_BIN" ]]; then
        error "acme.sh 安装失败"
        exit 1
    fi

    info "acme.sh 安装成功"
    "$ACME_BIN" --set-default-ca --server letsencrypt
}

# ============================================================
#  申请证书
# ============================================================
issue_cert() {
    if [[ "$TARGET_TYPE" == "ip" ]]; then
        info "正在为 IP $TARGET 申请证书 (shortlived, 有效期 ~6.66 天)..."
    else
        info "正在为域名 $TARGET 申请证书 (有效期 90 天)..."
    fi
    info "验证模式: $MODE"

    local cmd=("$ACME_BIN" --issue -d "$TARGET")
    cmd+=(--server letsencrypt)
    cmd+=(--days "$RENEW_DAYS")

    # IP 证书必须使用 shortlived 配置
    if [[ "$TARGET_TYPE" == "ip" ]]; then
        cmd+=(--certificate-profile shortlived)
    fi

    if [[ -n "$ECC_KEY" ]]; then
        cmd+=(--keylength "$ECC_KEY")
        info "密钥类型: ECC ($ECC_KEY)"
    fi

    if [[ "$FORCE_ISSUE" == true ]]; then
        cmd+=(--force)
    fi

    case "$MODE" in
        standalone)
            cmd+=(--standalone)
            info "使用独立 HTTP 服务器验证（需要 80 端口空闲）"
            ;;
        webroot)
            cmd+=(--webroot "$WEBROOT_PATH")
            info "使用 webroot 验证: $WEBROOT_PATH"
            ;;
        alpn)
            cmd+=(--alpn)
            info "使用 TLS-ALPN-01 验证（需要 443 端口空闲）"
            ;;
        dns)
            cmd+=(--dns)
            info "使用手动 DNS 验证"
            ;;
        *)
            error "不支持的验证模式: $MODE"
            exit 1
            ;;
    esac

    info "执行: ${cmd[*]}"
    echo ""

    if "${cmd[@]}"; then
        info "证书申请成功!"
    else
        local exit_code=$?
        if [[ $exit_code -eq 2 ]]; then
            info "证书已存在且未过期，跳过（使用 --force 强制重新申请）"
        else
            error "证书申请失败 (exit code: $exit_code)"
            error "常见原因:"
            error "  1. 80/443 端口被占用"
            error "  2. IP/域名无法从外部访问"
            error "  3. 防火墙阻挡了验证请求"
            if [[ "$TARGET_TYPE" == "domain" ]]; then
                error "  4. DNS 未正确解析到此服务器"
            fi
            exit 1
        fi
    fi
}

# ============================================================
#  安装/部署证书
# ============================================================
install_cert() {
    if [[ -z "$DEPLOY_TYPE" ]]; then
        show_cert_paths
        return
    fi

    setup_deploy_defaults

    local cert_dir
    cert_dir=$(dirname "$CERT_INSTALL_PATH")
    mkdir -p "$cert_dir"

    info "正在部署证书到 $DEPLOY_TYPE ..."
    info "  证书: $CERT_INSTALL_PATH"
    info "  私钥: $KEY_INSTALL_PATH"
    info "  重载: $RELOAD_CMD"

    local cmd=("$ACME_BIN" --install-cert -d "$TARGET")
    cmd+=(--key-file "$KEY_INSTALL_PATH")
    cmd+=(--fullchain-file "$CERT_INSTALL_PATH")

    if [[ -n "$ECC_KEY" ]]; then
        cmd+=(--ecc)
    fi

    if [[ -n "$RELOAD_CMD" ]]; then
        cmd+=(--reloadcmd "$RELOAD_CMD")
    fi

    if "${cmd[@]}"; then
        info "证书部署成功!"
    else
        error "证书部署失败"
        exit 1
    fi

    # 验证文件是否已生成
    if [[ -f "$CERT_INSTALL_PATH" && -f "$KEY_INSTALL_PATH" ]]; then
        info "确认文件已生成:"
        info "  $(ls -la "$CERT_INSTALL_PATH")"
        info "  $(ls -la "$KEY_INSTALL_PATH")"
    fi
}

# ============================================================
#  显示证书路径
# ============================================================
show_cert_paths() {
    local cert_dir="$ACME_HOME/${TARGET}"
    if [[ -n "$ECC_KEY" ]]; then
        cert_dir="${cert_dir}_ecc"
    fi

    echo ""
    info "========================================="
    info "  证书文件位置 (acme.sh 内部)"
    info "========================================="
    info "  证书:     ${cert_dir}/${TARGET}.cer"
    info "  私钥:     ${cert_dir}/${TARGET}.key"
    info "  CA 证书:  ${cert_dir}/ca.cer"
    info "  全链证书: ${cert_dir}/fullchain.cer"
    info "========================================="
}

# ============================================================
#  配置自动续期
# ============================================================
setup_auto_renew() {
    info "正在配置自动续期..."

    local renew_cmd="$ACME_BIN --cron --home $ACME_HOME"

    local cron_marker="# acme.sh-cert-renew"

    # IP 证书有效期短，需要更频繁检查
    local cron_schedule
    if [[ "$TARGET_TYPE" == "ip" ]]; then
        cron_schedule="0 */4 * * *"    # 每 4 小时
        info "IP 证书模式: 每 4 小时检查续期"
    else
        cron_schedule="0 2 * * *"      # 每天凌晨 2 点
        info "域名证书模式: 每天凌晨 2:00 检查续期"
    fi

    # 清除旧的同标记 cron 任务，添加新的
    (crontab -l 2>/dev/null | grep -v "$cron_marker") | crontab - 2>/dev/null || true
    (crontab -l 2>/dev/null; echo "$cron_schedule $renew_cmd $cron_marker") | crontab -

    info "cron 任务已配置"

    # systemd timer
    if command -v systemctl &>/dev/null && [[ -d /etc/systemd/system ]]; then
        setup_systemd_timer
    fi

    echo ""
    info "当前 crontab 中的续期任务:"
    crontab -l 2>/dev/null | grep "acme" || true
}

# ============================================================
#  systemd 定时器
# ============================================================
setup_systemd_timer() {
    local timer_interval
    if [[ "$TARGET_TYPE" == "ip" ]]; then
        timer_interval="*-*-* 00/4:00:00"
    else
        timer_interval="*-*-* 02:00:00"
    fi

    cat > /etc/systemd/system/acme-renew.service <<EOF
[Unit]
Description=Renew Let's Encrypt certificates via acme.sh
After=network-online.target

[Service]
Type=oneshot
ExecStart=$ACME_BIN --cron --home $ACME_HOME
SuccessExitStatus=0 2
EOF

    cat > /etc/systemd/system/acme-renew.timer <<EOF
[Unit]
Description=Timer for Let's Encrypt certificate renewal

[Timer]
OnCalendar=$timer_interval
RandomizedDelaySec=600
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now acme-renew.timer 2>/dev/null || true

    info "systemd 定时器已配置: acme-renew.timer"
}

# ============================================================
#  验证证书
# ============================================================
verify_cert() {
    local cert_dir="$ACME_HOME/${TARGET}"
    if [[ -n "$ECC_KEY" ]]; then
        cert_dir="${cert_dir}_ecc"
    fi

    local cert_file="${cert_dir}/${TARGET}.cer"

    if [[ ! -f "$cert_file" ]]; then
        # 部署后的证书路径
        if [[ -n "$CERT_INSTALL_PATH" && -f "$CERT_INSTALL_PATH" ]]; then
            cert_file="$CERT_INSTALL_PATH"
        else
            warn "找不到证书文件"
            return
        fi
    fi

    echo ""
    info "========================================="
    info "  证书信息"
    info "========================================="

    local subject issuer not_before not_after
    subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null || echo "N/A")
    issuer=$(openssl x509 -in "$cert_file" -noout -issuer 2>/dev/null || echo "N/A")
    not_before=$(openssl x509 -in "$cert_file" -noout -startdate 2>/dev/null | cut -d= -f2 || echo "N/A")
    not_after=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2 || echo "N/A")

    info "  主题:     $subject"
    info "  颁发者:   $issuer"
    info "  生效时间: $not_before"
    info "  过期时间: $not_after"
    info "========================================="
}

# ============================================================
#  打印 XrayR 配置提示
# ============================================================
print_xrayr_config() {
    if [[ "$DEPLOY_TYPE" != "xrayr" ]]; then
        return
    fi

    echo ""
    info "========================================="
    info "  XrayR 配置参考"
    info "========================================="
    cat <<EOF

在 XrayR 配置文件 (config.yml) 中设置:

Nodes:
  - ...
    CertConfig:
      CertMode: file
      CertFile: ${CERT_INSTALL_PATH}
      KeyFile: ${KEY_INSTALL_PATH}

EOF
    info "========================================="
    info "证书续期时会自动执行: $RELOAD_CMD"
    info "========================================="
}

# ============================================================
#  主流程
# ============================================================
main() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║   Let's Encrypt 证书申请 & 自动续期工具              ║${NC}"
    echo -e "${CYAN}║   目标: ${TARGET} (${TARGET_TYPE})$(printf '%*s' $((36 - ${#TARGET} - ${#TARGET_TYPE})) '')║${NC}"
    if [[ "$DEPLOY_TYPE" == "xrayr" ]]; then
    echo -e "${CYAN}║   部署: XrayR -> ${CERT_NAME}.cert/.key$(printf '%*s' $((30 - ${#CERT_NAME})) '')║${NC}"
    fi
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
    echo ""

    install_acme
    echo ""

    issue_cert
    echo ""

    install_cert
    echo ""

    setup_auto_renew
    echo ""

    verify_cert

    print_xrayr_config

    echo ""
    info "全部完成!"
    echo ""
    echo -e "${CYAN}重要提示:${NC}"
    if [[ "$TARGET_TYPE" == "ip" ]]; then
        echo -e "  1. IP 证书有效期仅 ${YELLOW}~6.66 天${NC}，已配置每 4 小时自动检查续期"
    else
        echo -e "  1. 域名证书有效期 ${YELLOW}90 天${NC}，已配置每天自动检查续期"
    fi
    echo -e "  2. 续期需要 ${YELLOW}80 端口${NC}可访问（HTTP-01 验证）"
    echo -e "  3. 查看续期日志: ${YELLOW}$ACME_HOME/acme.sh.log${NC}"
    echo -e "  4. 手动续期测试: ${YELLOW}$ACME_BIN --renew -d $TARGET --force${NC}"
    echo -e "  5. 查看已申请证书: ${YELLOW}$ACME_BIN --list${NC}"
    echo ""
}

main
