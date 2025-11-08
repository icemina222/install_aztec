#!/bin/bash  
# install_aztec.sh - Aztec 2.1.2 节点批量安装脚本  
# 优化版：自动从 mnemonic.txt 读取助记词
  
set -e  
  
# 颜色输出  
RED='\033[0;31m'  
GREEN='\033[0;32m'  
YELLOW='\033[1;33m'  
NC='\033[0m'  
  
echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }  
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }  
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }  
  
# 检查是否root  
if [ "$EUID" -ne 0 ]; then   
    echo_error "请使用 root 用户运行此脚本"  
    exit 1  
fi  
  
# 检查配置文件  
CONFIG_FILE="/root/aztec_start_command.txt"  
if [ ! -f "$CONFIG_FILE" ]; then  
    echo_error "未找到配置文件: $CONFIG_FILE"  
    exit 1  
fi

# 检查助记词文件
MNEMONIC_FILE="/root/mnemonic.txt"
if [ ! -f "$MNEMONIC_FILE" ]; then  
    echo_error "未找到助记词文件: $MNEMONIC_FILE"  
    exit 1  
fi
  
echo_info "========================================="  
echo_info "Aztec 2.1.2 节点自动安装脚本"  
echo_info "========================================="  
  
# ============================================  
# 步骤1: 清理环境  
# ============================================  
echo_info "步骤1: 清理旧环境..."  
  
echo_info "关闭监控脚本..."  
pkill -f monitor_aztec_node.sh || true  
  
echo_info "检查残留的监控进程..."  
ps aux | grep monitor_aztec_node.sh | grep -v grep || echo "无残留进程"  
  
echo_info "杀死所有 tmux 会话..."  
tmux kill-server 2>/dev/null || true  
  
echo_info "删除旧的 aztec 数据..."  
rm -rf ~/.aztec  
  
echo_info "停止并删除旧的 Docker 容器..."  
cd /root/.aztec 2>/dev/null && docker compose down 2>/dev/null || true  
docker rm -f aztec-sequencer 2>/dev/null || true  
  
# ============================================  
# 步骤2: 安装 Docker  
# ============================================  
echo_info "步骤2: 检查并安装 Docker..."  
  
if ! command -v docker &> /dev/null; then  
    echo_info "Docker 未安装，开始安装..."  
    curl -fsSL https://get.docker.com | sh  
    systemctl enable docker  
    systemctl start docker  
    echo_info "Docker 安装完成"  
else  
    echo_info "Docker 已安装，跳过..."  
fi  
  
# ============================================  
# 步骤3: 安装 Aztec  
# ============================================  
echo_info "步骤3: 安装 Aztec 2.1.2..."  
  
# 自动回答 y，并执行安装  
echo "y" | bash -i <(curl -s https://install.aztec.network)  
  
echo_info "等待安装完成..."  
sleep 5  
  
# 加载所有可能的环境文件  
for rc_file in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do  
    if [ -f "$rc_file" ]; then  
        source "$rc_file"  
    fi  
done  
  
# 手动添加路径  
export PATH="$HOME/.aztec/bin:$HOME/.local/bin:$HOME/.nvm/versions/node/*/bin:$PATH"  
  
# 查找并执行 aztec-up  
echo_info "查找 aztec-up..."  
if command -v aztec-up &> /dev/null; then  
    aztec-up latest  
elif [ -f "$HOME/.aztec/bin/aztec-up" ]; then  
    $HOME/.aztec/bin/aztec-up latest  
else  
    AZTEC_UP=$(find $HOME -name "aztec-up" -type f 2>/dev/null | head -1)  
    if [ -n "$AZTEC_UP" ]; then  
        chmod +x "$AZTEC_UP"  
        "$AZTEC_UP" latest  
    fi  
fi  
  
sleep 3  
  
# 再次加载环境  
for rc_file in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do  
    if [ -f "$rc_file" ]; then  
        source "$rc_file"  
    fi  
done  
export PATH="$HOME/.aztec/bin:$HOME/.local/bin:$PATH"  
  
# 查找 aztec 命令  
echo_info "查找 aztec 命令..."  
AZTEC_CMD=""  
  
if command -v aztec &> /dev/null; then  
    AZTEC_CMD="aztec"  
else  
    # 搜索所有可能的位置  
    for search_path in "$HOME/.aztec/bin" "$HOME/.local/bin" "$HOME/.nvm/versions/node/"*"/bin"; do  
        if [ -f "$search_path/aztec" ]; then  
            AZTEC_CMD="$search_path/aztec"  
            export PATH="$search_path:$PATH"  
            break  
        fi  
    done  
      
    # 如果还没找到，全局搜索  
    if [ -z "$AZTEC_CMD" ]; then  
        AZTEC_CMD=$(find $HOME -name "aztec" -type f -executable 2>/dev/null | grep -v node_modules | head -1)  
        if [ -n "$AZTEC_CMD" ]; then  
            export PATH="$(dirname $AZTEC_CMD):$PATH"  
        fi  
    fi  
fi  
  
if [ -n "$AZTEC_CMD" ]; then  
    echo_info "找到 aztec: $AZTEC_CMD"  
    # 导出供后续使用  
    export AZTEC_BIN="$AZTEC_CMD"  
else  
    echo_error "无法找到 aztec 命令"  
    echo_error "请检查安装是否成功"  
    exit 1  
fi  
  
echo_info "Aztec 安装完成"  

  
# ============================================  
# 步骤4: 安装 Cast (Foundry)  
# ============================================  
echo_info "步骤4: 安装 Cast..."  
  
if ! command -v cast &> /dev/null; then  
    echo_info "下载并安装 Foundry..."
    curl -L https://foundry.paradigm.xyz | bash  
    
    # 添加 Foundry 到当前环境
    export PATH="$HOME/.foundry/bin:$PATH"
    
    # 重新加载所有环境文件
    for rc_file in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do  
        if [ -f "$rc_file" ]; then  
            source "$rc_file" 2>/dev/null || true
        fi  
    done
    
    # 验证 foundryup 是否可用
    if command -v foundryup &> /dev/null; then
        echo_info "执行 foundryup 安装..."
        foundryup
    elif [ -f "$HOME/.foundry/bin/foundryup" ]; then
        echo_info "使用绝对路径执行 foundryup..."
        $HOME/.foundry/bin/foundryup
    else
        echo_warn "foundryup 未找到，尝试直接查找..."
        FOUNDRYUP=$(find $HOME -name "foundryup" -type f 2>/dev/null | head -1)
        if [ -n "$FOUNDRYUP" ]; then
            chmod +x "$FOUNDRYUP"
            "$FOUNDRYUP"
        else
            echo_error "无法找到 foundryup，但将继续安装"
        fi
    fi
    
    # 再次验证 cast 是否安装成功
    export PATH="$HOME/.foundry/bin:$PATH"
    if command -v cast &> /dev/null; then
        echo_info "Cast 安装完成"
    else
        echo_warn "Cast 可能未正确安装，将在后续步骤中尝试使用绝对路径"
    fi
else  
    echo_info "Cast 已安装，跳过..."  
fi  
  
# ============================================  
# 步骤5: 解析配置文件  
# ============================================  
echo_info "步骤5: 解析配置文件 $CONFIG_FILE ..."  
  
# 提取参数  
L1_RPC=$(grep -oP '(?<=--l1-rpc-urls ")[^"]*' "$CONFIG_FILE" || grep -oP "(?<=--l1-rpc-urls )\S+" "$CONFIG_FILE")  
L1_CONSENSUS=$(grep -oP '(?<=--l1-consensus-host-urls ")[^"]*' "$CONFIG_FILE" || grep -oP "(?<=--l1-consensus-host-urls )\S+" "$CONFIG_FILE")  
VALIDATOR_PRIVATE_KEY=$(grep -oP '(?<=--sequencer.validatorPrivateKeys )[^\s\\]*' "$CONFIG_FILE")  
COINBASE=$(grep -oP '(?<=--sequencer.coinbase )[^\s\\]*' "$CONFIG_FILE")  
P2P_IP=$(grep -oP '(?<=--p2p.p2pIp )[^\s\\]*' "$CONFIG_FILE")  
  
echo_info "解析到的配置："  
echo "  L1 RPC: $L1_RPC"  
echo "  L1 Consensus: $L1_CONSENSUS"  
echo "  Validator Private Key: ${VALIDATOR_PRIVATE_KEY:0:10}...${VALIDATOR_PRIVATE_KEY: -4}"  
echo "  Coinbase: $COINBASE"  
echo "  P2P IP: $P2P_IP"  
  
# 验证必需参数  
if [ -z "$L1_RPC" ] || [ -z "$L1_CONSENSUS" ] || [ -z "$VALIDATOR_PRIVATE_KEY" ] || [ -z "$COINBASE" ] || [ -z "$P2P_IP" ]; then  
    echo_error "配置文件解析失败，请检查文件格式"  
    exit 1  
fi  
  
# ============================================  
# 步骤6: 读取并验证助记词  
# ============================================  
echo_info "步骤6: 从 $MNEMONIC_FILE 读取助记词..."  

# 读取助记词并清理空白字符
MNEMONIC=$(cat "$MNEMONIC_FILE" | tr -s '[:space:]' ' ' | xargs)

if [ -z "$MNEMONIC" ]; then  
    echo_error "助记词文件为空: $MNEMONIC_FILE"  
    exit 1  
fi  
  
# 统计单词数量  
WORD_COUNT=$(echo "$MNEMONIC" | wc -w)  
echo_info "检测到 $WORD_COUNT 个助记词"

if [ $WORD_COUNT -ne 12 ]; then  
    echo_error "助记词应该是 12 个单词，当前为 $WORD_COUNT 个"
    echo_error "请检查文件: $MNEMONIC_FILE"
    exit 1
fi  

echo_info "助记词验证通过 (12个单词)"
echo_info "助记词前3个单词: $(echo "$MNEMONIC" | awk '{print $1, $2, $3}')..."
  
# ============================================  
# 步骤7: 生成 Keystore  
# ============================================  
echo_info "步骤7: 生成 Keystore..."  
  
# 使用步骤3中找到的 aztec 命令  
if [ -n "$AZTEC_BIN" ] && [ -f "$AZTEC_BIN" ]; then  
    echo_info "使用找到的 aztec: $AZTEC_BIN"  
    $AZTEC_BIN validator-keys new --fee-recipient 0x0000000000000000000000000000000000000000000000000000000000000000 --mnemonic "$MNEMONIC"  
elif command -v aztec &> /dev/null; then  
    echo_info "使用 PATH 中的 aztec"  
    aztec validator-keys new --fee-recipient 0x0000000000000000000000000000000000000000000000000000000000000000 --mnemonic "$MNEMONIC"  
else  
    echo_warn "再次查找 aztec 命令..."  
    AZTEC_CMD=$(find $HOME -name "aztec" -type f -executable 2>/dev/null | grep -v node_modules | head -1)  
    if [ -n "$AZTEC_CMD" ]; then  
        echo_info "找到: $AZTEC_CMD"  
        $AZTEC_CMD validator-keys new --fee-recipient 0x0000000000000000000000000000000000000000000000000000000000000000 --mnemonic "$MNEMONIC"  
    else  
        echo_error "无法找到 aztec 命令"  
        echo_error "请检查安装是否成功"  
        exit 1  
    fi  
fi  
  
# 验证生成的文件  
if [ ! -f ~/.aztec/keystore/key1.json ]; then  
    echo_error "Keystore 生成失败"  
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
echo "  BLS 密钥    : ${BLS_SECRET_KEY:0:10}...${BLS_SECRET_KEY: -10}"  
echo_info "===================================="  
echo ""  

  
# ============================================  
# 步骤8: 执行质押 (Approve)  
# ============================================  
echo_info "步骤8: 执行质押 (Approve)..."  
  
echo ""  
echo_warn "质押操作只能执行一次，重复执行会失败"  
read -p "是否执行质押？(y/n，默认 y): " DO_APPROVE  
DO_APPROVE=${DO_APPROVE:-y}  
  
if [ "$DO_APPROVE" = "y" ] || [ "$DO_APPROVE" = "Y" ]; then  
    echo_info "向合约地址发送 approve 交易..."  
    echo_info "使用 RPC: $L1_RPC"  
      
    # 确保 Foundry 在 PATH 中
    export PATH="$HOME/.foundry/bin:$PATH"
      
    # 查找 cast 命令
    CAST_CMD=""
    if command -v cast &> /dev/null; then  
        CAST_CMD="cast"
    elif [ -f "$HOME/.foundry/bin/cast" ]; then
        CAST_CMD="$HOME/.foundry/bin/cast"
    else
        CAST_CMD=$(find $HOME -name "cast" -type f -executable 2>/dev/null | head -1)
    fi
    
    if [ -z "$CAST_CMD" ]; then
        echo_error "无法找到 cast 命令，请确保 Foundry 已正确安装"
        exit 1
    fi
    
    echo_info "使用 cast: $CAST_CMD"
      
    if [ -z "$L1_RPC" ] || [ -z "$VALIDATOR_PRIVATE_KEY" ]; then  
        echo_error "参数缺失"  
        exit 1  
    fi  
      
    echo_info "执行 cast send..."  
    $CAST_CMD send 0x139d2a7a0881e16332d7D1F8DB383A4507E1Ea7A \
        "approve(address,uint256)" \
        0xebd99ff0ff6677205509ae73f93d0ca52ac85d67 \
        200000ether \
        --private-key "$VALIDATOR_PRIVATE_KEY" \
        --rpc-url "$L1_RPC"  
      
    if [ $? -eq 0 ]; then  
        echo_info "质押完成"  
    else  
        echo_error "质押失败"  
        read -p "是否继续？(y/n): " CONTINUE  
        if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then  
            exit 1  
        fi  
    fi  
else  
    echo_warn "跳过质押步骤"  
fi  
  
echo ""  


  
# ============================================  
# 步骤9: 注册验证者  
# ============================================  
echo_info "步骤9: 注册验证者..."  
  
echo ""  
echo_warn "注册操作只能执行一次，重复执行会失败"  
read -p "是否执行注册？(y/n，默认 y): " DO_REGISTER  
DO_REGISTER=${DO_REGISTER:-y}  
  
if [ "$DO_REGISTER" = "y" ] || [ "$DO_REGISTER" = "Y" ]; then  
    # 重新从 keystore 提取最新的 BLS 密钥  
    if [ -f ~/.aztec/keystore/key1.json ]; then  
        BLS_SECRET_KEY=$(cat ~/.aztec/keystore/key1.json | jq -r '.validators[0].attester.bls')  
        echo_info "BLS 密钥: ${BLS_SECRET_KEY:0:10}..."  
    else  
        echo_error "找不到 keystore 文件"  
        exit 1  
    fi  
      
    echo_info "向 Aztec 网络注册验证者..."  
    echo_info "使用 RPC: $L1_RPC"  
    echo_info "Attester: $COINBASE"  
      
    if [ -n "$AZTEC_BIN" ] && [ -f "$AZTEC_BIN" ]; then  
        AZTEC_CMD="$AZTEC_BIN"  
    elif command -v aztec &> /dev/null; then  
        AZTEC_CMD="aztec"  
    else  
        AZTEC_CMD=$(find $HOME -name "aztec" -type f -executable 2>/dev/null | grep -v node_modules | head -1)  
    fi  
      
    if [ -z "$AZTEC_CMD" ]; then  
        echo_error "无法找到 aztec 命令"  
        exit 1  
    fi  
      
    $AZTEC_CMD add-l1-validator --l1-rpc-urls "$L1_RPC" --network testnet --private-key "$VALIDATOR_PRIVATE_KEY" --attester "$COINBASE" --withdrawer "$COINBASE" --bls-secret-key "$BLS_SECRET_KEY" --rollup 0xebd99ff0ff6677205509ae73f93d0ca52ac85d67  
      
    if [ $? -eq 0 ]; then  
        echo_info "验证者注册完成"  
    else  
        echo_error "验证者注册失败"  
        read -p "是否继续？(y/n): " CONTINUE  
        if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then  
            exit 1  
        fi  
    fi  
else  
    echo_warn "跳过注册步骤"  
fi  
  
echo ""  


# ============================================  
# 步骤10: 生成 .env 文件  
# ============================================  
echo_info "步骤10: 生成 .env 文件..."  
mkdir -p /root/.aztec/data  
  
{  
    echo "DATA_DIRECTORY=./data"  
    echo "KEY_STORE_DIRECTORY=./keystore"  
    echo "LOG_LEVEL=info"  
    echo "ETHEREUM_HOSTS=$L1_RPC"  
    echo "L1_CONSENSUS_HOST_URLS=$L1_CONSENSUS"  
    echo "P2P_IP=$P2P_IP"  
    echo "P2P_PORT=40400"  
    echo "AZTEC_PORT=8080"  
    echo "AZTEC_ADMIN_PORT=8880"  
} > /root/.aztec/.env  
  
chmod 600 /root/.aztec/.env  
echo_info ".env 文件已创建"  
echo ""  
  
# ============================================  
# 步骤11: 生成 docker-compose.yml  
# ============================================  
echo_info "步骤11: 生成 docker-compose.yml..."  
  
cat > /root/.aztec/docker-compose.yml <<'DCEOF'
services:  
  aztec-sequencer:  
    image: "aztecprotocol/aztec:2.1.2"  
    container_name: "aztec-sequencer"  
    ports:  
      - ${AZTEC_PORT}:${AZTEC_PORT}  
      - ${AZTEC_ADMIN_PORT}:${AZTEC_ADMIN_PORT}  
      - ${P2P_PORT}:${P2P_PORT}  
      - ${P2P_PORT}:${P2P_PORT}/udp  
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
      node --no-warnings /usr/src/yarn-project/aztec/dest/bin/index.js start --node --archiver --sequencer --network testnet  
    networks:  
      - aztec  
    restart: always  
networks:  
  aztec:  
DCEOF
  
echo_info "docker-compose.yml 已创建"  
echo ""  
  
# ============================================  
# 步骤12: 启动节点  
# ============================================  
echo_info "步骤12: 启动 Aztec 节点..."  
  
cd /root/.aztec  
docker compose up -d  
  
echo_info "节点已启动，等待10秒后检查状态..."  
sleep 10  
  
# ============================================  
# 步骤13: 检查节点状态  
# ============================================  
echo_info "步骤13: 检查节点状态..."  
  
for i in {1..3}; do  
    RESULT=$(curl -s -X POST -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' http://localhost:8080 | jq -r ".result.proven.number" 2>/dev/null || echo "")  
      
    if [[ "$RESULT" =~ ^[0-9]+$ ]]; then  
        echo_info "✓ 节点运行正常！当前区块高度: $RESULT"  
        break  
    else  
        echo_warn "第 $i 次检查失败，等待10秒后重试..."  
        sleep 10  
    fi  
done  
  
# ============================================  
# 步骤14: 部署监控脚本  
# ============================================  
echo_info "步骤14: 部署监控脚本..."  
  
cat > /root/monitor_aztec_node.sh <<'MONEOF'
#!/bin/bash  
  
LOG_FILE="/root/aztec_monitor.log"
CHECK_INTERVAL=60           # 每60秒检查一次
FAIL_THRESHOLD=3            # 连续失败3次触发重启
RESTART_COOLDOWN=300        # 重启后冷却5分钟再检查
FAIL_COUNT=0
LAST_BLOCK=0
BLOCK_STUCK_COUNT=0
BLOCK_STUCK_THRESHOLD=5     # 区块高度5分钟不变视为卡住

log() {  
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $1" | tee -a "$LOG_FILE"  
}  
  
# 等待到下一个30分钟整点（如 10:00, 10:30, 11:00）
wait_for_next_checkpoint() {  
    CURRENT_MINUTE=$(date -u +%M)  
    CURRENT_SECOND=$(date -u +%S)  
    
    # 计算到下一个30分钟整点的秒数
    if [ $CURRENT_MINUTE -lt 30 ]; then
        TARGET_MINUTE=30
    else
        TARGET_MINUTE=60
    fi
    
    WAIT_MINUTES=$((TARGET_MINUTE - CURRENT_MINUTE - 1))
    WAIT_SECONDS=$((60 - CURRENT_SECOND))
    
    if [ $WAIT_SECONDS -eq 60 ]; then
        WAIT_MINUTES=$((WAIT_MINUTES + 1))
        WAIT_SECONDS=0
    fi
    
    TOTAL_WAIT_SECONDS=$((WAIT_MINUTES * 60 + WAIT_SECONDS))
    
    if [ $TOTAL_WAIT_SECONDS -gt 0 ]; then
        NEXT_TIME=$(date -u -d "+${TOTAL_WAIT_SECONDS} seconds" '+%H:%M:%S')
        log "⏰ 等待到 ${NEXT_TIME} UTC ($(($TOTAL_WAIT_SECONDS / 60))分钟) 开始监控"
        sleep $TOTAL_WAIT_SECONDS
    fi
}  
  
check_node() {  
    local result=$(curl -s --max-time 10 -X POST -H 'Content-Type: application/json' \
        -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' \
        http://localhost:8080 | jq -r ".result.proven.number" 2>/dev/null || echo "")  
    
    if echo "$result" | grep -qE '^[0-9]+
  
chmod +x /root/monitor_aztec_node.sh  
tmux new-session -d -s aztec_monitor "bash /root/monitor_aztec_node.sh"  
  
echo_info "监控脚本已启动"  
  
# ============================================  
# 完成  
# ============================================  
echo ""  
echo_info "========================================="  
echo_info "✓ Aztec 节点安装完成！"  
echo_info "========================================="  
echo_info "节点信息:"  
echo_info "  Coinbase: $COINBASE"  
echo_info "  P2P IP: $P2P_IP"  
echo_info "  区块链端口: 8080"  
echo_info "  管理端口: 8880"  
echo ""  
echo_info "常用命令:"  
echo_info "  查看日志: docker logs -f aztec-sequencer"  
echo_info "  查看状态: docker ps"  
echo_info "  重启节点: cd /root/.aztec && docker compose restart"  
echo_info "  查看监控: tail -f /root/aztec_monitor.log"  
echo_info "  监控进程: tmux attach -t aztec_monitor"  
echo_info "========================================="; then  
        echo "$result"
        return 0  
    else  
        echo ""
        return 1  
    fi  
}  
  
restart_node() {  
    log "🔄 ======== 开始重启节点 ========"  
    
    cd /root/.aztec || { log "❌ 无法进入 /root/.aztec 目录"; return 1; }
    
    # 停止容器
    log "⏹️  停止容器..."
    docker compose down
    sleep 5  
    
    # 强制清理残留容器
    if docker ps -a | grep -q aztec-sequencer; then  
        log "🗑️  清理残留容器..."
        docker rm -f aztec-sequencer  
    fi  
    
    # 启动容器
    log "▶️  启动容器..."
    docker compose up -d  
    
    log "⏳ 等待 ${RESTART_COOLDOWN} 秒让节点稳定..."
    sleep $RESTART_COOLDOWN
    
    log "✅ ======== 重启完成 ========"  
}  
  
# 检查区块高度是否卡住
check_block_stuck() {
    local current_block=$1
    
    if [ "$current_block" == "$LAST_BLOCK" ]; then
        BLOCK_STUCK_COUNT=$((BLOCK_STUCK_COUNT + 1))
        if [ $BLOCK_STUCK_COUNT -ge $BLOCK_STUCK_THRESHOLD ]; then
            log "⚠️  区块高度卡在 $current_block 已超过 $((BLOCK_STUCK_THRESHOLD * CHECK_INTERVAL / 60)) 分钟"
            return 1
        fi
    else
        BLOCK_STUCK_COUNT=0
        LAST_BLOCK=$current_block
    fi
    return 0
}

log "==================== 监控程序启动 ===================="  
log "📋 配置信息:"
log "   检查间隔: ${CHECK_INTERVAL}秒"
log "   失败阈值: ${FAIL_THRESHOLD}次"
log "   重启冷却: ${RESTART_COOLDOWN}秒"
log "   区块卡住阈值: ${BLOCK_STUCK_THRESHOLD}次"

wait_for_next_checkpoint  
log "========== ✅ 开始监控 =========="  
  
while true; do  
    CURRENT_BLOCK=$(check_node)
    
    if [ $? -eq 0 ] && [ -n "$CURRENT_BLOCK" ]; then
        # 节点响应正常
        if ! check_block_stuck "$CURRENT_BLOCK"; then
            log "⚠️  检测到区块卡住，触发重启..."
            restart_node
            FAIL_COUNT=0
            BLOCK_STUCK_COUNT=0
            LAST_BLOCK=0
            continue
        fi
        
        # 判断是否从失败中恢复
        if [ $FAIL_COUNT -gt 0 ]; then  
            log "✅ 节点恢复 | 区块: $CURRENT_BLOCK"  
        else  
            # 每30次检查输出一次正常日志（避免日志过多）
            CHECK_COUNT=$((CHECK_COUNT + 1))
            if [ $((CHECK_COUNT % 30)) -eq 0 ] || [ $CHECK_COUNT -eq 1 ]; then
                log "✓ 正常运行 | 区块: $CURRENT_BLOCK | 已监控: $((CHECK_COUNT * CHECK_INTERVAL / 60)) 分钟"
            fi
        fi  
        FAIL_COUNT=0  
    else  
        # 节点响应失败
        FAIL_COUNT=$((FAIL_COUNT + 1))  
        log "❌ 检查失败 ($FAIL_COUNT/$FAIL_THRESHOLD) | 节点无响应"  
        
        if [ $FAIL_COUNT -ge $FAIL_THRESHOLD ]; then  
            log "🚨 连续失败 ${FAIL_THRESHOLD} 次，触发重启..."  
            restart_node  
            FAIL_COUNT=0
            BLOCK_STUCK_COUNT=0
            LAST_BLOCK=0
            
            # 重启后验证
            sleep 10
            VERIFY_BLOCK=$(check_node)
            if [ $? -eq 0 ] && [ -n "$VERIFY_BLOCK" ]; then  
                log "✅ 重启成功 | 当前区块: $VERIFY_BLOCK"  
            else  
                log "❌ 重启后节点仍无响应，将继续监控"  
            fi  
        fi  
    fi  
    
    sleep $CHECK_INTERVAL  
done  
MONEOF
  
chmod +x /root/monitor_aztec_node.sh  
tmux new-session -d -s aztec_monitor "bash /root/monitor_aztec_node.sh"  
  
echo_info "监控脚本已启动"  
  
# ============================================  
# 完成  
# ============================================  
echo ""  
echo_info "========================================="  
echo_info "✓ Aztec 节点安装完成！"  
echo_info "========================================="  
echo_info "节点信息:"  
echo_info "  Coinbase: $COINBASE"  
echo_info "  P2P IP: $P2P_IP"  
echo_info "  区块链端口: 8080"  
echo_info "  管理端口: 8880"  
echo ""  
echo_info "常用命令:"  
echo_info "  查看日志: docker logs -f aztec-sequencer"  
echo_info "  查看状态: docker ps"  
echo_info "  重启节点: cd /root/.aztec && docker compose restart"  
echo_info "  查看监控: tail -f /root/aztec_monitor.log"  
echo_info "  监控进程: tmux attach -t aztec_monitor"  
echo_info "========================================="