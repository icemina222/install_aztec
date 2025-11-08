#!/bin/bash  
# ============================================  
# Aztec 2.1.2 节点批量安装脚本  
# 版本: v1.0.3  
# 更新日期: 2025-01-08  
# 支持: Docker Compose + 自动监控 + Screen 会话  
# ============================================  
  
SCRIPT_VERSION="v1.0.3"  
  
# 颜色输出  
RED='\033[0;31m'  
GREEN='\033[0;32m'  
YELLOW='\033[1;33m'  
BLUE='\033[0;34m'  
CYAN='\033[0;36m'  
NC='\033[0m'  
  
echo_info() { echo -e "$${GREEN}[INFO]$${NC} $1"; }  
echo_warn() { echo -e "$${YELLOW}[WARN]$${NC} $1"; }  
echo_error() { echo -e "$${RED}[ERROR]$${NC} $1"; }  
echo_step() { echo -e "$${BLUE}[STEP]$${NC} $1"; }  
echo_version() { echo -e "$${CYAN}[VERSION]$${NC} $1"; }  
  
SCREEN_NAME="aztec_install"  
  
# ============================================  
# 检查是否在 Screen 中运行  
# ============================================  
if [ -z "$STY" ]; then  
    # 不在 screen 中，需要创建 screen 会话  
      
    clear  
    echo_version "========================================="  
    echo_version "    Aztec 节点安装脚本 $SCRIPT_VERSION"  
    echo_version "========================================="  
    echo ""  
      
    # 检查是否 root  
    if [ "$EUID" -ne 0 ]; then   
        echo_error "请使用 root 用户运行此脚本"  
        exit 1  
    fi  
      
    # 安装 screen  
    if ! command -v screen &> /dev/null; then  
        echo_info "安装 screen..."  
        apt-get update -qq && apt-get install -y screen -qq  
        echo_info "screen 安装完成"  
        echo ""  
    fi  
      
    # 检查是否已有运行中的 screen 会话  
    if screen -list | grep -q "$SCREEN_NAME"; then  
        echo_warn "发现已有安装进程正在运行"  
        echo ""  
        echo "请选择操作："  
        echo "  1) 重新连接到现有进程"  
        echo "  2) 终止现有进程并重新开始"  
        echo "  3) 退出"  
        echo ""  
        read -p "请输入选项 (1/2/3): " choice  
          
        case $choice in  
            1)  
                echo_info "重新连接到安装进程..."  
                screen -r $SCREEN_NAME  
                exit 0  
                ;;  
            2)  
                echo_warn "终止现有进程..."  
                screen -S $SCREEN_NAME -X quit  
                sleep 2  
                ;;  
            3)  
                echo_info "退出"  
                exit 0  
                ;;  
            *)  
                echo_error "无效选项"  
                exit 1  
                ;;  
        esac  
    fi  
      
    # 显示提示信息  
    echo_info "========================================="  
    echo_info "即将在 screen 会话中启动安装"  
    echo_info "========================================="  
    echo ""  
    echo_info "Screen 使用说明："  
    echo "  • 断开连接（脚本继续运行）: Ctrl+A 然后按 D"  
    echo "  • 重新连接: screen -r $SCREEN_NAME"  
    echo "  • 查看所有会话: screen -ls"  
    echo ""  
    echo_warn "注意："  
    echo "  • 脚本运行过程中需要输入助记词，请提前准备！"  
    echo "  • 安装过程约 10-15 分钟"  
    echo "  • 日志将保存到: /root/install_aztec.log"  
    echo ""  
      
    read -p "按 Enter 键开始安装..."   
    echo ""  
      
    # 保存脚本路径（修复语法错误）  
    SCRIPT_FULL_PATH="$$(cd "$$(dirname "$$0")" && pwd)/$$(basename "$0")"  
      
    # 在 screen 中重新运行自己  
    echo_info "创建 screen 会话: $SCREEN_NAME"  
    sleep 1  
      
    # 使用更简单直接的方式  
    screen -dmS $$SCREEN_NAME bash -c "exec bash '$$SCRIPT_FULL_PATH' --in-screen 2>&1 | tee /root/install_aztec.log"  
      
    sleep 2  
      
    # 检查 screen 是否成功创建  
    if screen -list | grep -q "$SCREEN_NAME"; then  
        echo ""  
        echo_info "Screen 会话已成功创建，正在连接..."  
        sleep 1  
        screen -r $SCREEN_NAME  
    else  
        echo_error "Screen 会话创建失败"  
        echo ""  
        echo "尝试直接运行脚本..."  
        bash "$SCRIPT_FULL_PATH" --in-screen  
    fi  
      
    exit 0  
fi  
  
# ============================================  
# 以下是在 Screen 中执行的主安装流程  
# ============================================  
  
# 确保在 /root 目录下工作  
cd /root || exit 1  
  
# 使用简单的 echo，不使用颜色（避免在 screen 中出问题）  
echo ""  
echo "========================================="  
echo "  Aztec 2.1.2 节点安装脚本 $SCRIPT_VERSION"  
echo "  (运行在 Screen 会话中)"  
echo "========================================="  
echo ""  
  
# 检查是否root  
if [ "$EUID" -ne 0 ]; then   
    echo "[ERROR] 请使用 root 用户运行此脚本"  
    read -p "按任意键退出..."  
    exit 1  
fi  
  
# 检查配置文件  
CONFIG_FILE="/root/aztec_start_command.txt"  
if [ ! -f "$CONFIG_FILE" ]; then  
    echo "[ERROR] 未找到配置文件: $CONFIG_FILE"  
    echo ""  
    echo "配置文件示例格式："  
    echo "aztec start --node --archiver --sequencer \\"  
    echo "--network testnet \\"  
    echo "--l1-rpc-urls \"http://your-rpc-url\" \\"  
    echo "--l1-consensus-host-urls \"http://your-consensus-url\" \\"  
    echo "--sequencer.validatorPrivateKeys 0xyour-private-key \\"  
    echo "--sequencer.coinbase 0xyour-address \\"  
    echo "--p2p.p2pIp your-vps-ip"  
    echo ""  
    read -p "按任意键退出..."  
    exit 1  
fi  
  
# ============================================  
# 步骤1: 清理环境  
# ============================================  
echo ""  
echo "[步骤 1/13] 清理旧环境..."  
  
echo "[INFO] 关闭监控脚本..."  
pkill -f monitor_aztec_node.sh 2>/dev/null || true  
sleep 2  
  
echo "[INFO] 检查残留的监控进程..."  
MONITOR_COUNT=$(ps aux | grep monitor_aztec_node.sh | grep -v grep | wc -l)  
if [ $MONITOR_COUNT -gt 0 ]; then  
    echo "[WARN] 发现 $MONITOR_COUNT 个残留进程，强制终止..."  
    pkill -9 -f monitor_aztec_node.sh 2>/dev/null || true  
fi  
  
echo "[INFO] 杀死所有 tmux 会话..."  
tmux kill-server 2>/dev/null || true  
  
echo "[INFO] 停止并删除旧的 Docker 容器..."  
if [ -d "/root/.aztec" ]; then  
    cd /root/.aztec 2>/dev/null && docker compose down 2>/dev/null || true  
    cd /root  
fi  
docker rm -f aztec-sequencer 2>/dev/null || true  
  
echo "[INFO] 删除旧的 aztec 数据..."  
rm -rf ~/.aztec  
  
echo "[INFO] 环境清理完成"  
  
# ============================================  
# 步骤2: 安装 Docker  
# ============================================  
echo ""  
echo "[步骤 2/13] 检查并安装 Docker..."  
  
if ! command -v docker &> /dev/null; then  
    echo "[INFO] Docker 未安装，开始安装..."  
    curl -fsSL https://get.docker.com | sh  
    systemctl enable docker  
    systemctl start docker  
    echo "[INFO] Docker 安装完成"  
else  
    echo "[INFO] Docker 已安装: $(docker --version)"  
fi  
  
# ============================================  
# 步骤3: 安装 Aztec  
# ============================================  
echo ""  
echo "[步骤 3/13] 安装 Aztec 2.1.2..."  
  
echo "[INFO] 下载并执行 Aztec 安装脚本..."  
cd /root  
bash -i <(curl -s https://install.aztec.network) 2>/dev/null || true  
  
echo "[INFO] 加载环境变量..."  
[ -f "$$HOME/.bash_profile" ] && source "$$HOME/.bash_profile"  
[ -f "$$HOME/.bashrc" ] && source "$$HOME/.bashrc"  
  
echo "[INFO] 安装 Aztec 2.1.2..."  
aztec-up latest  
  
echo "[INFO] Aztec 安装完成"  
  
# ============================================  
# 步骤4: 安装 Cast (Foundry)  
# ============================================  
echo ""  
echo "[步骤 4/13] 安装 Cast (Foundry)..."  
  
FOUNDRY_DIR="$HOME/.foundry"  
FOUNDRY_BIN_DIR="$FOUNDRY_DIR/bin"  
  
if ! command -v cast &> /dev/null; then  
    echo "[INFO] Cast 未安装，开始安装..."  
      
    cd /root  
    curl -L https://foundry.paradigm.xyz | bash 2>/dev/null || true  
    mkdir -p "$FOUNDRY_BIN_DIR"  
      
    if [ -f "$FOUNDRY_BIN_DIR/foundryup" ]; then  
        echo "[INFO] 执行 foundryup..."  
        "$FOUNDRY_BIN_DIR/foundryup"  
    else  
        echo "[INFO] 手动下载 foundryup..."  
        curl -L https://raw.githubusercontent.com/foundry-rs/foundry/master/foundryup/foundryup -o "$FOUNDRY_BIN_DIR/foundryup"  
        chmod +x "$FOUNDRY_BIN_DIR/foundryup"  
        "$FOUNDRY_BIN_DIR/foundryup"  
    fi  
      
    export PATH="$$FOUNDRY_BIN_DIR:$$PATH"  
    echo "[INFO] Cast 安装完成"  
else  
    echo "[INFO] Cast 已安装"  
fi  
  
export PATH="$$FOUNDRY_BIN_DIR:$$PATH"  
  
# ============================================  
# 步骤5: 解析配置文件  
# ============================================  
echo ""  
echo "[步骤 5/13] 解析配置文件..."  
  
L1_RPC=$$(grep -oP '(?<=--l1-rpc-urls ")[^"]*' "$$CONFIG_FILE" 2>/dev/null || grep -oP "(?<=--l1-rpc-urls )\S+" "$CONFIG_FILE")  
L1_CONSENSUS=$$(grep -oP '(?<=--l1-consensus-host-urls ")[^"]*' "$$CONFIG_FILE" 2>/dev/null || grep -oP "(?<=--l1-consensus-host-urls )\S+" "$CONFIG_FILE")  
VALIDATOR_PRIVATE_KEY=$$(grep -oP '(?<=--sequencer.validatorPrivateKeys )[^\s\\]*' "$$CONFIG_FILE")  
COINBASE=$$(grep -oP '(?<=--sequencer.coinbase )[^\s\\]*' "$$CONFIG_FILE")  
P2P_IP=$$(grep -oP '(?<=--p2p.p2pIp )[^\s\\]*' "$$CONFIG_FILE")  
  
echo ""  
echo "========== 解析到的配置 =========="  
echo "  L1 RPC URL      : $L1_RPC"  
echo "  L1 Consensus URL: $L1_CONSENSUS"  
echo "  Validator PK    : $${VALIDATOR_PRIVATE_KEY:0:10}...$${VALIDATOR_PRIVATE_KEY: -4}"  
echo "  Coinbase        : $COINBASE"  
echo "  P2P IP          : $P2P_IP"  
echo "=================================="  
  
if [ -z "$$L1_RPC" ] || [ -z "$$L1_CONSENSUS" ] || [ -z "$$VALIDATOR_PRIVATE_KEY" ] || [ -z "$$COINBASE" ] || [ -z "$P2P_IP" ]; then  
    echo "[ERROR] 配置文件解析失败"  
    read -p "按任意键退出..."  
    exit 1  
fi  
  
# ============================================  
# 步骤6: 生成 Keystore  
# ============================================  
echo ""  
echo "[步骤 6/13] 生成 Keystore..."  
echo ""  
echo "========================================="  
echo "  请输入此节点的 12 个单词助记词"  
echo "  助记词之间用空格分隔"  
echo "========================================="  
echo ""  
read -p "请输入助记词: " MNEMONIC  
echo ""  
  
if [ -z "$MNEMONIC" ]; then  
    echo "[ERROR] 助记词不能为空"  
    read -p "按任意键退出..."  
    exit 1  
fi  
  
WORD_COUNT=$$(echo "$$MNEMONIC" | wc -w)  
if [ $WORD_COUNT -ne 12 ]; then  
    echo "[WARN] 助记词应该是 12 个单词，当前输入了 $WORD_COUNT 个"  
    read -p "是否继续？(y/n): " CONTINUE  
    if [ "$$CONTINUE" != "y" ] && [ "$$CONTINUE" != "Y" ]; then  
        exit 1  
    fi  
fi  
  
echo "[INFO] 生成 Keystore..."  
aztec validator-keys new \  
  --fee-recipient 0x0000000000000000000000000000000000000000 \  
  --mnemonic "$MNEMONIC"  
  
if [ ! -f ~/.aztec/keystore/key1.json ]; then  
    echo "[ERROR] Keystore 生成失败"  
    read -p "按任意键退出..."  
    exit 1  
fi  
  
if ! command -v jq &> /dev/null; then  
    echo "[INFO] 安装 jq..."  
    apt-get update -qq && apt-get install -y jq -qq  
fi  
  
BLS_SECRET_KEY=$(cat ~/.aztec/keystore/key1.json | jq -r '.validators[0].attester.bls')  
ETH_ADDRESS=$(cat ~/.aztec/keystore/key1.json | jq -r '.validators[0].attester.eth')  
  
echo ""  
echo "========== 生成的密钥信息 =========="  
echo "  ETH 地址    : $ETH_ADDRESS"  
echo "  BLS 密钥    : $${BLS_SECRET_KEY:0:10}...$${BLS_SECRET_KEY: -10}"  
echo "===================================="  
  
# ============================================  
# 步骤7: 质押  
# ============================================  
echo ""  
echo "[步骤 7/13] 执行质押 (Approve)..."  
  
export PATH="$$FOUNDRY_BIN_DIR:$$PATH"  
  
if command -v cast &> /dev/null; then  
    CAST_CMD="cast"  
else  
    CAST_CMD="$FOUNDRY_BIN_DIR/cast"  
fi  
  
$CAST_CMD send 0x139d2a7a0881e16332d7D1F8DB383A4507E1Ea7A \  
  "approve(address,uint256)" \  
  0xebd99ff0ff6677205509ae73f93d0ca52ac85d67 \  
  200000ether \  
  --private-key "$VALIDATOR_PRIVATE_KEY" \  
  --rpc-url "$L1_RPC"  
  
echo "[INFO] 质押完成"  
  
# ============================================  
# 步骤8: 注册验证者  
# ============================================  
echo ""  
echo "[步骤 8/13] 注册验证者..."  
  
aztec add-l1-validator \  
  --l1-rpc-urls "$L1_RPC" \  
  --network testnet \  
  --private-key "$VALIDATOR_PRIVATE_KEY" \  
  --attester "$COINBASE" \  
  --withdrawer "$COINBASE" \  
  --bls-secret-key "$BLS_SECRET_KEY" \  
  --rollup 0xebd99ff0ff6677205509ae73f93d0ca52ac85d67  
  
echo "[INFO] 验证者注册完成"  
  
# ============================================  
# 步骤9: 生成 .env  
# ============================================  
echo ""  
echo "[步骤 9/13] 生成 .env 文件..."  
  
mkdir -p /root/.aztec/data  
  
cat > /root/.aztec/.env << EOF  
DATA_DIRECTORY=./data  
KEY_STORE_DIRECTORY=./keystore  
LOG_LEVEL=info  
ETHEREUM_HOSTS=$L1_RPC  
L1_CONSENSUS_HOST_URLS=$L1_CONSENSUS  
P2P_IP=$P2P_IP  
P2P_PORT=40400  
AZTEC_PORT=8080  
AZTEC_ADMIN_PORT=8880  
EOF  
  
chmod 600 /root/.aztec/.env  
echo "[INFO] .env 文件已创建"  
  
# ============================================  
# 步骤10: 生成 docker-compose.yml  
# ============================================  
echo ""  
echo "[步骤 10/13] 生成 docker-compose.yml..."  
  
cat > /root/.aztec/docker-compose.yml << 'EOF'  
services:  
  aztec-sequencer:  
    image: "aztecprotocol/aztec:2.1.2"  
    container_name: "aztec-sequencer"  
    ports:  
      - $${AZTEC_PORT}:$${AZTEC_PORT}  
      - $${AZTEC_ADMIN_PORT}:$${AZTEC_ADMIN_PORT}  
      - $${P2P_PORT}:$${P2P_PORT}  
      - $${P2P_PORT}:$${P2P_PORT}/udp  
    volumes:  
      - ${DATA_DIRECTORY}:/var/lib/data  
      - ${KEY_STORE_DIRECTORY}:/var/lib/keystore  
    environment:  
      KEY_STORE_DIRECTORY: /var/lib/keystore  
      DATA_DIRECTORY: /var/lib/data  
      LOG_LEVEL: ${LOG_LEVEL}  
      ETHEREUM_HOSTS: ${ETHEREUM_HOSTS}  
      L1_CONSENSUS_HOST_URLS: ${L1_CONSENSUS_HOST_URLS}  
      P2P_IP: ${P2P_IP}  
      P2P_PORT: ${P2P_PORT}  
      AZTEC_PORT: ${AZTEC_PORT}  
      AZTEC_ADMIN_PORT: ${AZTEC_ADMIN_PORT}  
    entrypoint: >-  
      node  
      --no-warnings  
      /usr/src/yarn-project/aztec/dest/bin/index.js  
      start  
      --node  
      --archiver  
      --sequencer  
      --network testnet  
    networks:  
      - aztec  
    restart: always  
networks:  
  aztec:  
    name: aztec  
EOF  
  
echo "[INFO] docker-compose.yml 已创建"  
  
# ============================================  
# 步骤11: 启动节点  
# ============================================  
echo ""  
echo "[步骤 11/13] 启动 Aztec 节点..."  
  
cd /root/.aztec  
docker compose up -d  
  
echo "[INFO] 节点已启动，等待 15 秒..."  
sleep 15  
  
# ============================================  
# 步骤12: 检查节点状态  
# ============================================  
echo ""  
echo "[步骤 12/13] 检查节点状态..."  
  
for i in {1..3}; do  
    echo "[INFO] 第 $i 次检查..."  
    RESULT=$(curl -s -X POST -H 'Content-Type: application/json' \  
      -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' \  
      http://localhost:8080 | jq -r ".result.proven.number" 2>/dev/null || echo "")  
      
    if [[ "$$RESULT" =~ ^[0-9]+$$ ]]; then  
        echo "[INFO] ✓ 节点运行正常！区块高度: $RESULT"  
        break  
    else  
        if [ $i -lt 3 ]; then  
            echo "[WARN] 检查失败，10秒后重试..."  
            sleep 10  
        fi  
    fi  
done  
  
# ============================================  
# 步骤13: 部署监控脚本  
# ============================================  
echo ""  
echo "[步骤 13/13] 部署监控脚本..."  
  
cat > /root/monitor_aztec_node.sh << 'MONITOR_EOF'  
#!/bin/bash  
  
LOG_FILE="/root/aztec_monitor.log"  
CHECK_INTERVAL=30  
FAIL_THRESHOLD=3  
FAIL_COUNT=0  
  
log() {  
    echo "[$$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $$1" | tee -a "$LOG_FILE"  
}  
  
wait_for_next_half_hour() {  
    CURRENT_MINUTE=$(date -u +%M)  
    CURRENT_SECOND=$(date -u +%S)  
    MINUTE_MOD=$((CURRENT_MINUTE % 30))  
      
    if [ $$MINUTE_MOD -eq 0 ] && [ $$CURRENT_SECOND -eq 0 ]; then  
        WAIT_MINUTES=0  
        WAIT_SECONDS=0  
    else  
        WAIT_MINUTES=$((30 - MINUTE_MOD - 1))  
        WAIT_SECONDS=$((60 - CURRENT_SECOND))  
        if [ $WAIT_SECONDS -eq 60 ]; then  
            WAIT_MINUTES=$((WAIT_MINUTES + 1))  
            WAIT_SECONDS=0  
        fi  
    fi  
      
    TOTAL_WAIT_SECONDS=$((WAIT_MINUTES * 60 + WAIT_SECONDS))  
      
    if [ $TOTAL_WAIT_SECONDS -gt 0 ]; then  
        NEXT_TIME=$$(date -u -d "+$${TOTAL_WAIT_SECONDS} seconds" '+%H:%M:%S')  
        log "当前 UTC 时间: $(date -u '+%H:%M:%S')"  
        log "下一个监测时间点: $${NEXT_TIME} UTC (等待 $${TOTAL_WAIT_SECONDS} 秒)"  
        sleep $TOTAL_WAIT_SECONDS  
    fi  
}  
  
check_node() {  
    RESULT=$(curl -s -X POST -H 'Content-Type: application/json' \  
      -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' \  
      http://localhost:8080 | jq -r ".result.proven.number" 2>/dev/null || echo "")  
      
    if [[ "$$RESULT" =~ ^[0-9]+$$ ]]; then  
        return 0  
    else  
        return 1  
    fi  
}  
  
restart_node() {  
    log "======== 开始重启节点 ========"  
      
    cd /root/.aztec  
      
    # 先停止容器  
    log "停止容器..."  
    docker compose down  
      
    # 等待容器完全停止  
    sleep 5  
      
    # 确认容器已停止  
    if docker ps -a | grep -q aztec-sequencer; then  
        log "强制删除残留容器..."  
        docker rm -f aztec-sequencer  
        sleep 2  
    fi  
      
    # 启动新容器  
    log "启动容器..."  
    docker compose up -d  
      
    # 等待容器启动  
    log "等待容器启动稳定（30秒）..."  
    sleep 30  
      
    log "======== 重启完成 ========"  
}  
  
log "==================== 监控脚本启动 ===================="  
log "配置: 每$${CHECK_INTERVAL}秒检测一次，连续$${FAIL_THRESHOLD}次失败后重启"  
  
wait_for_next_half_hour  
log "========== 开始监控节点 =========="  
  
while true; do  
    if check_node; then  
        RESULT=$(curl -s -X POST -H 'Content-Type: application/json' \  
          -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' \  
          http://localhost:8080 | jq -r ".result.proven.number" 2>/dev/null)  
          
        if [ $FAIL_COUNT -gt 0 ]; then  
            log "✓ 节点恢复正常 | 区块高度: $RESULT | 失败计数已重置"  
        else  
            log "✓ 节点正常 | 区块高度: $RESULT"  
        fi  
        FAIL_COUNT=0  
    else  
        FAIL_COUNT=$((FAIL_COUNT + 1))  
        log "✗ 节点检测失败 ($${FAIL_COUNT}/$${FAIL_THRESHOLD})"  
          
        if [ $$FAIL_COUNT -ge $$FAIL_THRESHOLD ]; then  
            log "⚠ 连续失败 ${FAIL_COUNT} 次，触发重启..."  
            restart_node  
            FAIL_COUNT=0  
              
            log "重启后等待60秒进行验证..."  
            sleep 60  
              
            if check_node; then  
                RESULT=$(curl -s -X POST -H 'Content-Type: application/json' \  
                  -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' \  
                  http://localhost:8080 | jq -r ".result.proven.number" 2>/dev/null)  
                log "✓ 重启后验证成功 | 区块高度: $RESULT"  
            else  
                log "✗ 重启后验证失败，将在下个周期继续监控"  
            fi  
        fi  
    fi  
      
    sleep $CHECK_INTERVAL  
done  
MONITOR_EOF  
  
chmod +x /root/monitor_aztec_node.sh  
tmux new-session -d -s aztec_monitor "bash /root/monitor_aztec_node.sh"  
  
echo "[INFO] 监控脚本已启动"  
  
# ============================================  
# 完成  
# ============================================  
echo ""  
echo "========================================="  
echo "✓✓✓ Aztec 节点安装完成！✓✓✓"  
echo "========================================="  
echo ""  
echo "脚本版本: $SCRIPT_VERSION"  
echo ""  
echo "节点信息:"  
echo "  Coinbase: $COINBASE"  
echo "  ETH地址: $ETH_ADDRESS"  
echo "  P2P IP: $P2P_IP"  
echo ""  
echo "常用命令:"  
echo "  查看节点日志: docker logs -f aztec-sequencer"  
echo "  查看监控日志: tail -f /root/aztec_monitor.log"  
echo "  重启节点: cd /root/.aztec && docker compose restart"  
echo "  停止节点: cd /root/.aztec && docker compose down"  
echo ""  
echo "Screen 管理:"  
echo "  断开会话: Ctrl+A 然后按 D"  
echo "  重新连接: screen -r aztec_install"  
echo ""  
echo "========================================="  
echo ""  
read -p "按任意键退出 screen..."  
