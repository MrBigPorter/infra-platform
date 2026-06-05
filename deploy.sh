#!/usr/bin/env bash
# ============================================================
# infra-platform — 本地部署脚本
# ============================================================
# 参考 JoyMini_Nest_Monorepo/deploy/deploy.sh 模式
#
# 使用方法:
#   ./deploy.sh                    # 全量部署（同步配置 + 重启服务）
#   ./deploy.sh --sync             # 仅同步配置文件
#   ./deploy.sh --restart          # 仅重启服务
# ============================================================
set -euo pipefail

# ---- 配置 ----
if [ -z "${VPS_IP:-}" ]; then
    read -rp "请输入 VPS IP 地址: " VPS_IP
fi
if [ -z "${VPS_IP:-}" ]; then
    echo "ERROR: VPS_IP 不能为空"
    exit 1
fi
VPS_USER="root"
VPS_DIR="/opt/infra-platform"
SSH_TARGET="${VPS_USER}@${VPS_IP}"

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[DEPLOY]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

# ---- 解析参数 ----
SYNC_ONLY=false
RESTART_ONLY=false

for arg in "$@"; do
    case $arg in
        --sync)    SYNC_ONLY=true ;;
        --restart) RESTART_ONLY=true ;;
        --help)
            echo "用法: ./deploy.sh [选项]"
            echo "  --sync      仅同步配置文件"
            echo "  --restart   仅重启服务"
            exit 0
            ;;
        *) echo "未知参数: $arg"; exit 1 ;;
    esac
done

# ---- 检查 .env.prod ----
if [ ! -f ".env.prod" ] && [ "$RESTART_ONLY" = false ]; then
    echo "ERROR: .env.prod 不存在！"
    echo "请先复制 .env.example 并填入生产环境值："
    echo "  cp .env.example .env.prod"
    echo "  vi .env.prod"
    exit 1
fi

# ---- SSH 连通性检查 ----
log "检查 SSH 连接 → $SSH_TARGET..."
ssh -o ConnectTimeout=5 "$SSH_TARGET" "echo 'SSH OK'" || { echo "ERROR: 无法连接到 $SSH_TARGET"; exit 1; }

# ============================================================
# Step 1: 同步配置文件到 VPS
# ============================================================
sync_configs() {
    log "同步配置文件..."

    # 确保目录存在
    ssh "$SSH_TARGET" "mkdir -p $VPS_DIR"

    # 核心配置
    scp compose.monitoring.yml           "$SSH_TARGET:$VPS_DIR/"
    scp Makefile                         "$SSH_TARGET:$VPS_DIR/"
    scp .env.prod                        "$SSH_TARGET:$VPS_DIR/.env"
    scp loki-config.yml                  "$SSH_TARGET:$VPS_DIR/"
    scp promtail-config.yml              "$SSH_TARGET:$VPS_DIR/"

    # Auth Service
    ssh "$SSH_TARGET" "mkdir -p $VPS_DIR/auth-service"
    scp auth-service/package.json        "$SSH_TARGET:$VPS_DIR/auth-service/"
    scp auth-service/server.js           "$SSH_TARGET:$VPS_DIR/auth-service/"

    # Grafana provisioning
    if [ -d "grafana-provisioning" ]; then
        ssh "$SSH_TARGET" "mkdir -p $VPS_DIR/grafana-provisioning"
        scp -r grafana-provisioning/     "$SSH_TARGET:$VPS_DIR/grafana-provisioning/"
    fi

    # Docs
    if [ -d "docs" ]; then
        ssh "$SSH_TARGET" "mkdir -p $VPS_DIR/docs"
        scp -r docs/                     "$SSH_TARGET:$VPS_DIR/docs/"
    fi

    log "配置文件同步完成"
}

if [ "$RESTART_ONLY" = false ]; then
    sync_configs
fi

if [ "$SYNC_ONLY" = true ]; then
    log "仅同步模式，退出"
    exit 0
fi

# ============================================================
# Step 2: 在 VPS 上重启服务
# ============================================================
log "在 VPS 上重启服务..."

ssh "$SSH_TARGET" << REMOTE_SCRIPT
    set -e
    cd $VPS_DIR

    echo "→ 当前状态:"
    docker compose -f compose.monitoring.yml ps 2>/dev/null || true

    echo "→ 启动/更新所有服务..."
    docker compose -f compose.monitoring.yml up -d

    echo "→ 服务状态:"
    docker compose -f compose.monitoring.yml ps

    echo "→ 清理旧镜像..."
    docker image prune -f
REMOTE_SCRIPT

log "部署完成！"
echo ""
echo -e "${CYAN}验证:${NC}"
echo "  Grafana:    https://monitor.joyminins.com"
echo "  Loki:       http://$VPS_IP:3100/ready"
echo "  Auth:       http://$VPS_IP:3004/health"
echo "  Logs:       ssh $SSH_TARGET 'docker compose -f $VPS_DIR/compose.monitoring.yml logs -f'"
echo ""
