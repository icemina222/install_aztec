#!/bin/bash  
# ============================================  
# Aztec 2.1.2 节点批量安装脚本  
# 支持 Docker Compose 部署 + 自动监控 + Screen 会话  
# ============================================  
  
# 颜色输出  
RED='\033[0;31m'  
GREEN='\033[0;32m'  
YELLOW='\033[1;33m'  
BLUE='\033[0;34m'  
NC='\033[0m'  
  
echo_info() { echo -e "$${GREEN}[INFO]$${NC} $1"; }  
echo_warn() { echo -e "$${YELLOW}[WARN]$${NC} $1"; }  
echo_error() { echo -e "$${RED}[ERROR]$${NC} $1"; }  
echo_step() { echo -e "$${BLUE}[STEP]$${NC} $1"; }  
  
SCREEN_NAME="aztec_install"  
SCRIPT_PATH="/root/install_aztec.sh"  
  
# ============================================  
# 检查是否在 Screen 中运行  
# ============================================  
if [ -z "$STY" ]; then  
    # 不在 screen 中，需要创建 screen 会话  
      
    echo_info "========================================="  
    echo_info "    Aztec 节点安装脚本"  
    echo_info "========================================="  
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
      
    # 在 screen 中重新运行自己  
    echo_info "创建 screen 会话: $SCREEN_NAME"  
    sleep 1  
    screen -S $$SCREEN_NAME -L -Logfile /root/install_aztec.log bash "$$0" --in-screen  
      
    # screen 退出后的提示  
    echo ""  
    echo_info "========================================="  
    echo_info "安装脚本已在 screen 中运行"  
    echo_info "========================================="  
    echo ""  
    echo_info "如需重新连接，使用命令："  
    echo "  screen -r $SCREEN_NAME"  
    echo ""  
    exit 0  
fi  
  
# ============================================  
# 以下是在 Screen 中执行的主安装流程  
# ============================================  
  
set -e  
  
echo_info "========================================="  
echo_info "    Aztec 2.1.2 节点安装脚本"  
echo_info "    (运行在 Screen 会话中)"  
echo_info "========================================="  
echo ""  
  
# 检查是否root  
if [ "$EUID" -ne 0 ]; then   
    echo_error "请使用 root 用户运行此脚本"  
    exit 1  
fi  
  
# 检查配置文件  
CONFIG_FILE="/root/aztec_start_command.txt"  
if [ ! -f "$CONFIG_FILE" ]; then  
    echo_error "未找到配置文件: $CONFIG_FILE"  
    echo_error "请确保配置文件存在后再运行脚本"  
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
echo_step "步骤1/13: 清理旧环境..."  
  
echo_info "关闭监控脚本..."  
pkill -f monitor_aztec_node.sh 2>/dev/null || true  
sleep 2  
  
echo_info "检查残留的监控进程..."  
MONITOR_COUNT=$(ps aux | grep monitor_aztec_node.sh | grep -v grep | wc -l)  
if [ $MONITOR_COUNT -gt 0 ]; then  
    echo_warn "发现 $MONITOR_COUNT 个残留进程，强制终止..."  
    pkill -9 -f monitor_aztec_node.sh 2>/dev/null || true  
else  
    echo_info "无残留进程"  
fi  
  
echo_info "杀死所有 tmux 会话..."  
tmux kill-server 2>/dev/null || true  
  
echo_info "停止并删除旧的 Docker 容器..."  
if [ -d "/root/.aztec" ]; then  
    cd /root/.aztec 2>/dev/null && docker compose down 2>/dev/null || true  
fi  
docker rm -f aztec-sequencer 2>/dev/null || true  
  
echo_info "删除旧的 aztec 数据..."  
rm -rf ~/.aztec  
  
echo_info "环境清理完成"  
echo ""  
  
# ============================================  
# 步骤2: 安装 Docker  
# ============================================  
echo_step "步骤2/13: 检查并安装 Docker..."  
  
if ! command -v docker &> /dev/null; then  
    echo_info "Docker 未安装，开始安装..."  
    curl -fsSL https://get.docker.com | sh  
    systemctl enable docker  
    systemctl start docker  
    echo_info "Docker 安装完成"  
else  
    DOCKER_VERSION=$(docker --version)  
    echo_info "Docker 已安装: $DOCKER_VERSION"  
fi  
echo ""  
  
# ============================================  
# 步骤3: 安装 Aztec  
# ============================================  
echo_step "步骤3/13: 安装 Aztec 2.1.2..."  
  
echo_info "下载并执行 Aztec 安装脚本..."  
bash -i <(curl -s https://install.aztec.network) 2>/dev/null || true  
  
echo_info "加载环境变量..."  
[ -f "$$HOME/.bash_profile" ] && source "$$HOME/.bash_profile"  
[ -f "$$HOME/.bashrc" ] && source "$$HOME/.bashrc"  
  
echo_info "安装 Aztec 2.1.2..."  
aztec-up latest  
  
echo_info "Aztec 安装完成"  
echo ""  
  
# ============================================  
# 步骤4: 安装 Cast (Foundry) - 已修复  
# ============================================  
echo_step "步骤4/13: 安装 Cast (Foundry)..."  
  
if ! command -v cast &> /dev/null; then  
    echo_info "Cast 未安装，开始安装..."  
      
    # 下载并执行 foundryup 安装脚本  
    curl -L https://foundry.paradigm.xyz | bash  
      
    # 多次尝试加载环境变量  
    [ -f "$$HOME/.bashrc" ] && source "$$HOME/.bashrc"  
    [ -f "$$HOME/.bash_profile" ] && source "$$HOME/.bash_profile"  
      
    # 手动添加到 PATH  
    if [ -d "$HOME/.foundry/bin" ]; then  
        export PATH="$$HOME/.foundry/bin:$$PATH"  
    fi  
      
    # 执行 foundryup  
    if command -v foundryup &> /dev/null; then  
        foundryup  
    elif [ -f "$HOME/.foundry/bin/foundryup" ]; then  
        $HOME/.foundry/bin/foundryup  
    else  
        echo_error "foundryup 安装失败，尝试手动安装..."  
        mkdir -p $HOME/.foundry/bin  
        curl -L https://foundry.paradigm.xyz | bash  
        $HOME/.foundry/bin/foundryup  
    fi  
      
    # 再次确保 PATH 正确  
    export PATH="$$HOME/.foundry/bin:$$PATH"  
      
    echo_info "Cast 安装完成"  
else  
    CAST_VERSION=$(cast --version 2>/dev/null | head -n 1)  
    echo_info "Cast 已安装: $CAST_VERSION"  
fi  
  
# 确保 cast 可用  
export PATH="$$HOME/.foundry/bin:$$PATH"  
echo ""  
  
# ============================================  
# 步骤5: 解析配置文件  
# ============================================  
echo_step "步骤5/13: 解析配置文件..."  
  
echo_info "读取配置文件: $CONFIG_FILE"  
  
# 提取参数（兼容带引号和不带引号的格式）  
L1_RPC=$$(grep -oP '(?<=--l1-rpc-urls ")[^"]*' "$$CONFIG_FILE" 2>/dev/null || grep -oP "(?<=--l1-rpc-urls )\S+" "$CONFIG_FILE")  
L1_CONSENSUS=$$(grep -oP '(?<=--l1-consensus-host-urls ")[^"]*' "$$CONFIG_FILE" 2>/dev/null || grep -oP "(?<=--l1-consensus-host-urls )\S+" "$CONFIG_FILE")  
VALIDATOR_PRIVATE_KEY=$$(grep -oP '(?<=--sequencer.validatorPrivateKeys )[^\s\\]*' "$$CONFIG_FILE")  
COINBASE=$$(grep -oP '(?<=--sequencer.coinbase )[^\s\\]*' "$$CONFIG_FILE")  
P2P_IP=$$(grep -oP '(?<=--p2p.p2pIp )[^\s\\]*' "$$CONFIG_FILE")  
  
echo ""  
echo_info "========== 解析到的配置 =========="  
echo "  L1 RPC URL      : $L1_RPC"  
echo "  L1 Consensus URL: $L1_CONSENSUS"  
echo "  Validator PK    : $${VALIDATOR_PRIVATE_KEY:0:10}...$${VALIDATOR_PRIVATE_KEY: -4}"  
echo "  Coinbase        : $COINBASE"  
echo "  P2P IP          : $P2P_IP"  
echo_info "=================================="  
echo ""  
  
# 验证必需参数  
if [ -z "$$L1_RPC" ] || [ -z "$$L1_CONSENSUS" ] || [ -z "$$VALIDATOR_PRIVATE_KEY" ] || [ -z "$$COINBASE" ] || [ -z "$P2P_IP" ]; then  
    echo_error "配置文件解析失败，缺少必需参数"  
    echo_error "请检查 $CONFIG_FILE 文件格式是否正确"  
    echo ""  
    read -p "按任意键退出..."  
    exit 1  
fi  
  
# ============================================  
# 步骤6: 生成 Keystore  
# ============================================  
echo_step "步骤6/13: 生成 Keystore..."  
  
echo ""  
echo_warn "========================================="  
echo_warn "  请输入此节点的 12 个单词助记词"  
echo_warn "  助记词之间用空格分隔"  
echo_warn "========================================="  
echo ""  
read -p "请输入助记词: " MNEMONIC  
echo ""  
  
if [ -z "$MNEMONIC" ]; then  
    echo_error "助记词不能为空"  
    read -p "按任意键退出..."  
    exit 1  
fi  
  
# 统计单词数量  
WORD_COUNT=$$(echo "$$MNEMONIC" | wc -w)  
if [ $WORD_COUNT -ne 12 ]; then  
    echo_warn "助记词应该是 12 个单词，当前输入了 $WORD_COUNT 个"  
    read -p "是否继续？(y/n): " CONTINUE  
    if [ "$$CONTINUE" != "y" ] && [ "$$CONTINUE" != "Y" ]; then  
        exit 1  
    fi  
fi  
  
echo_info "生成 Keystore..."  
aztec validator-keys new \  
  --fee-recipient 0x0000000000000000000000000000000000000000 \  
  --mnemonic "$MNEMONIC"  
  
# 验证生成的文件  
if [ ! -f ~/.aztec/keystore/key1.json ]; then  
    echo_error "Keystore 生成失败"  
    read -p "按任意键退出..."  
    exit 1  
fi  
  
echo_info "Keystore 已生成: ~/.aztec/keystore/key1.json"  
  
# 检查是否安装了 jq  
if ! command -v jq &> /dev/null; then  
    echo_info "安装 jq 工具..."  
    apt-get update -qq && apt-get install -y jq -qq  
fi  
  
# 提取密钥信息  
BLS_SECRET_KEY=$(cat ~/.aztec/keystore/key1.json | jq -r '.validators[0].attester.bls')  
ETH_ADDRESS=$(cat ~/.aztec/keystore/key1.json | jq -r '.validators[0].attester.eth')  
  
echo ""  
echo_info "========== 生成的密钥信息 =========="  
echo "  ETH 地址    : $ETH_ADDRESS"  
echo "  BLS 密钥    : $${BLS_SECRET_KEY:0:10}...$${BLS_SECRET_KEY: -10}"  
echo_info "===================================="  
echo ""  
  
# ============================================  
# 步骤7: 质押 (Approve)  
# ============================================  
echo_step "步骤7/13: 执行质押 (Approve)..."  
  
echo_info "向合约地址发送 approve 交易..."  
  
# 确保 cast 命令可用  
export PATH="$$HOME/.foundry/bin:$$PATH"  
  
cast send 0x139d2a7a0881e16332d7D1F8DB383A4507E1Ea7A \  
  "approve(address,uint256)" \  
  0xebd99ff0ff6677205509ae73f93d0ca52ac85d67 \  
  200000ether \  
  --private-key "$VALIDATOR_PRIVATE_KEY" \  
  --rpc-url "$L1_RPC"  
  
echo_info "质押完成"  
echo ""  
  
# ============================================  
# 步骤8: 注册验证者  
# ============================================  
echo_step "步骤8/13: 注册验证者..."  
  
echo_info "向 Aztec 网络注册验证者..."  
aztec add-l1-validator \  
  --l1-rpc-urls "$L1_RPC" \  
  --network testnet \  
  --private-key "$VALIDATOR_PRIVATE_KEY" \  
  --attester "$COINBASE" \  
  --withdrawer "$COINBASE" \  
  --bls-secret-key "$BLS_SECRET_KEY" \  
  --rollup 0xebd99ff0ff6677205509ae73f93d0ca52ac85d67  
  
echo_info "验证者注册完成"  
echo ""  
  
# ============================================  
# 步骤9: 生成 .env 文件  
# ============================================  
echo_step "步骤9/13: 生成 .env 文件..."  
  
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
echo_info ".env 文件已创建: /root/.aztec/.env"  
echo ""  
  
# ============================================  
# 步骤10: 生成 docker-compose.yml  
# ============================================  
echo_step "步骤10/13: 生成 docker-compose.yml..."  
  
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
  
echo_info "docker-compose.yml 已创建: /root/.aztec/docker-compose.yml"  
echo ""  
  
# ============================================  
# 步骤11: 启动节点  
# ============================================  
echo_step "步骤11/13: 启动 Aztec 节点..."  
  
cd /root/.aztec  
docker compose up -d  
  
echo_info "节点已启动，等待 15 秒后检查状态..."  
sleep 15  
echo ""  
  
# ============================================  
# 步骤12: 检查节点状态  
# ============================================  
echo_step "步骤12/13: 检查节点状态..."  
  
for i in {1..3}; do  
    echo_info "第 $i 次检查..."  
    RESULT=$(curl -s -X POST -H 'Content-Type: application/json' \  
      -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' \  
      http://localhost:8080 | jq -r ".result.proven.number" 2>/dev/null || echo "")  
      
    if [[ "$$RESULT" =~ ^[0-9]+$$ ]]; then  
        echo_info "✓ 节点运行正常！当前区块高度: $RESULT"  
        break  
    else  
        if [ $i -lt 3 ]; then  
            echo_warn "检查失败，等待 10 秒后重试..."  
            sleep 10  
        else  
            echo_warn "节点可能还在启动中，监控脚本会持续检查"  
        fi  
    fi  
done  
echo ""  
  
# ============================================  
# 步骤13: 部署监控脚本  
# ============================================  
echo_step "步骤13/13: 部署监控脚本..."  
  
cat > /root/monitor_aztec_node.sh << 'MONITOR_EOF'  
#!/bin/bash  
  
LOG_FILE="/root/aztec_monitor.log"  
CHECK_INTERVAL=30        # 每30秒检查一次  
FAIL_THRESHOLD=3         # 连续失败3次才重启  
  
FAIL_COUNT=0  
  
log() {  
    echo "[$$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $$1" | tee -a "$LOG_FILE"  
}  
  
# 计算距离下一个整点或半点的秒数  
wait_for_next_half_hour() {  
    CURRENT_MINUTE=$(date -u +%M)  
    CURRENT_SECOND=$(date -u +%S)  
      
    # 计算当前分钟数对30的余数  
    MINUTE_MOD=$((CURRENT_MINUTE % 30))  
      
    # 计算需要等待的分钟数  
    if [ $$MINUTE_MOD -eq 0 ] && [ $$CURRENT_SECOND -eq 0 ]; then  
        # 正好在整点或半点  
        WAIT_MINUTES=0  
        WAIT_SECONDS=0  
    else  
        WAIT_MINUTES=$((30 - MINUTE_MOD - 1))  
        WAIT_SECONDS=$((60 - CURRENT_SECOND))  
          
        # 如果秒数为60，需要调整  
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
        return 0  # 成功  
    else  
        return 1  # 失败  
    fi  
}  
  
restart_node() {  
    log "======== 开始重启节点 ========"  
    cd /root/.aztec  
    docker compose down  
    sleep 5  
    docker compose up -d  
    log "节点已重启，等待30秒稳定..."  
    sleep 30  
    log "======== 重启完成 ========"  
}  
  
log "==================== 监控脚本启动 ===================="  
log "配置: 每$${CHECK_INTERVAL}秒检测一次，连续$${FAIL_THRESHOLD}次失败后重启"  
log "监测时间点: UTC 时间每个整点和半点 (00:00, 00:30, 01:00, 01:30...)"  
  
# 等待到下一个整点或半点  
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
              
            # 重启后等待并再次检查  
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
  
# 在 tmux 中启动监控  
tmux new-session -d -s aztec_monitor "bash /root/monitor_aztec_node.sh"  
  
echo_info "监控脚本已启动（tmux 会话: aztec_monitor）"  
echo ""  
  
# ============================================  
# 完成  
# ============================================  
echo ""  
echo_info "========================================="  
echo_info "✓✓✓ Aztec 节点安装完成！✓✓✓"  
echo_info "========================================="  
echo ""  
echo_info "节点信息:"  
echo "  Coinbase 地址   : $COINBASE"  
echo "  ETH 地址        : $ETH_ADDRESS"  
echo "  P2P IP         : $P2P_IP"  
echo "  区块链端口      : 8080"  
echo "  管理端口        : 8880"  
echo "  P2P 端口       : 40400"  
echo ""  
echo_info "监控配置:"  
echo "  监测对齐       : UTC 时间整点和半点"  
echo "  检测频率       : 每 30 秒"  
echo "  重启条件       : 连续 3 次失败 (90秒)"  
echo ""  
echo_info "常用命令:"  
echo "  查看节点日志   : docker logs -f aztec-sequencer"  
echo "  查看节点状态   : docker ps"  
echo "  重启节点       : cd /root/.aztec && docker compose restart"  
echo "  停止节点       : cd /root/.aztec && docker compose down"  
echo "  查看监控日志   : tail -f /root/aztec_monitor.log"  
echo "  查看监控进程   : tmux attach -t aztec_monitor"  
echo "  退出监控界面   : Ctrl+B 然后按 D"  
echo ""  
echo_info "Screen 会话管理:"  
echo "  断开此会话     : Ctrl+A 然后按 D"  
echo "  重新连接       : screen -r $SCREEN_NAME"  
echo "  查看所有会话   : screen -ls"  
echo ""  
echo_info "========================================="  
echo_info "安装完成！节点正在后台运行"  
echo_info "========================================="  
echo ""  
echo_warn "按 Ctrl+A 然后按 D 断开 screen 会话（脚本继续运行）"  
echo_warn "或按任意键退出..."  
read -n 1  
