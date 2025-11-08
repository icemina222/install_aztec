#!/bin/bash  
# install_aztec.sh - Aztec 2.1.2 节点批量安装脚本  
  
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
    curl -L https://foundry.paradigm.xyz | bash  
    source /root/.bashrc  
    foundryup  
    echo_info "Cast 安装完成"  
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
# 步骤6: 生成 Keystore  
# ============================================  
echo_info "步骤6: 生成 Keystore..."  
  
echo ""  
echo_warn "========================================="  
echo_warn "请输入此节点的12个单词助记词"  
echo_warn "助记词之间用空格分隔"  
echo_warn "========================================="  
echo ""  
read -p "助记词: " MNEMONIC  
echo ""  
  
if [ -z "$MNEMONIC" ]; then  
    echo_error "助记词不能为空"  
    read -p "按任意键退出..."  
    exit 1  
fi  
  
# 统计单词数量  
WORD_COUNT=$(echo "$MNEMONIC" | wc -w)  
if [ $WORD_COUNT -ne 12 ]; then  
    echo_warn "助记词应该是 12 个单词，当前输入了 $WORD_COUNT 个"  
    read -p "是否继续？(y/n): " CONTINUE  
    if [ "$CONTINUE" != "y" ] && [ "$CONTINUE" != "Y" ]; then  
        exit 1  
    fi  
fi  
  
echo_info "生成 Keystore..."  
  
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
echo "  BLS 密钥    : ${BLS_SECRET_KEY:0:10}...${BLS_SECRET_KEY: -10}"  
echo_info "===================================="  
echo ""  

  
# 可选：验证 ETH 地址是否与配置文件中的 COINBASE 一致  
# （如果助记词正确，应该会生成相同的地址）  
  
# ============================================  
# 步骤7: 执行质押 (Approve)  
# ============================================  
echo_info "步骤7: 执行质押 (Approve)..."  
  
echo ""  
echo_warn "质押操作只能执行一次，重复执行会失败"  
read -p "是否执行质押？(y/n，默认 y): " DO_APPROVE  
DO_APPROVE=${DO_APPROVE:-y}  
  
if [ "$DO_APPROVE" = "y" ] || [ "$DO_APPROVE" = "Y" ]; then  
    echo_info "向合约地址发送 approve 交易..."  
    echo_info "使用 RPC: $L1_RPC"  
      
    export PATH="$FOUNDRY_BIN_DIR:$PATH"  
      
    if command -v cast &> /dev/null; then  
        CAST_CMD="cast"  
    else  
        CAST_CMD="$FOUNDRY_BIN_DIR/cast"  
    fi  
      
    if [ -z "$L1_RPC" ] || [ -z "$VALIDATOR_PRIVATE_KEY" ]; then  
        echo_error "参数缺失"  
        exit 1  
    fi  
      
    echo_info "执行 cast send..."  
    $CAST_CMD send 0x139d2a7a0881e16332d7D1F8DB383A4507E1Ea7A "approve(address,uint256)" 0xebd99ff0ff6677205509ae73f93d0ca52ac85d67 200000ether --private-key "$VALIDATOR_PRIVATE_KEY" --rpc-url "$L1_RPC"  
      
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
# ============================================  
# 步骤8: 注册验证者  
# ============================================  
echo_info "步骤8: 注册验证者..."  
  
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
# 步骤9: 生成 .env 文件  
# ============================================  
echo_info "步骤9: 生成 .env 文件..."  
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
# 步骤10: 生成 docker-compose.yml  
# ============================================  
echo_info "步骤10: 生成 docker-compose.yml..."  
  
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
# 步骤11: 启动节点  
# ============================================  
echo_info "步骤11: 启动 Aztec 节点..."  
  
cd /root/.aztec  
docker compose up -d  
  
echo_info "节点已启动，等待10秒后检查状态..."  
sleep 10  
  
# ============================================  
# 步骤12: 检查节点状态  
# ============================================  
echo_info "步骤12: 检查节点状态..."  
  
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
# 步骤13: 部署监控脚本  
# ============================================  
echo_info "步骤13: 部署监控脚本..."  
  
cat > /root/monitor_aztec_node.sh <<'MONEOF'
#!/bin/bash  
  
LOG_FILE="/root/aztec_monitor.log"  
CHECK_INTERVAL=30  
FAIL_THRESHOLD=3  
FAIL_COUNT=0  
  
log() {  
    echo "[$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $1" | tee -a "$LOG_FILE"  
}  
  
wait_for_half_hour() {  
    CURRENT_MINUTE=$(date -u +%M)  
    CURRENT_SECOND=$(date -u +%S)  
    MINUTE_MOD=$((CURRENT_MINUTE % 30))  
    if [ $MINUTE_MOD -eq 0 ] && [ $CURRENT_SECOND -eq 0 ]; then  
        WAIT_SECONDS=0  
    else  
        WAIT_MINUTES=$((30 - MINUTE_MOD - 1))  
        WAIT_SECONDS=$((60 - CURRENT_SECOND))  
        if [ $WAIT_SECONDS -eq 60 ]; then  
            WAIT_MINUTES=$((WAIT_MINUTES + 1))  
            WAIT_SECONDS=0  
        fi  
        WAIT_SECONDS=$((WAIT_MINUTES * 60 + WAIT_SECONDS))  
    fi  
    if [ $WAIT_SECONDS -gt 0 ]; then  
        NEXT_TIME=$(date -u -d "+${WAIT_SECONDS} seconds" '+%H:%M:%S')  
        log "等待到 ${NEXT_TIME} UTC 开始监控"  
        sleep $WAIT_SECONDS  
    fi  
}  
  
check_node() {  
    RESULT=$(curl -s -X POST -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' http://localhost:8080 | jq -r ".result.proven.number" 2>/dev/null || echo "")  
    if echo "$RESULT" | grep -qE '^[0-9]+$'; then  
        return 0  
    else  
        return 1  
    fi  
}  
  
restart_node() {  
    log "======== 开始重启 ========"  
    cd /root/.aztec  
    docker compose down  
    sleep 5  
    if docker ps -a | grep -q aztec-sequencer; then  
        docker rm -f aztec-sequencer  
    fi  
    docker compose up -d  
    sleep 30  
    log "======== 完成 ========"  
}  
  
log "==================== 监控启动 ===================="  
wait_for_half_hour  
log "========== 开始监控 =========="  
  
while true; do  
    if check_node; then  
        RESULT=$(curl -s -X POST -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' http://localhost:8080 | jq -r ".result.proven.number" 2>/dev/null)  
        if [ $FAIL_COUNT -gt 0 ]; then  
            log "✓ 恢复 | 区块: $RESULT"  
        else  
            log "✓ 正常 | 区块: $RESULT"  
        fi  
        FAIL_COUNT=0  
    else  
        FAIL_COUNT=$((FAIL_COUNT + 1))  
        log "✗ 失败 ($FAIL_COUNT/$FAIL_THRESHOLD)"  
        if [ $FAIL_COUNT -ge $FAIL_THRESHOLD ]; then  
            log "⚠ 触发重启..."  
            restart_node  
            FAIL_COUNT=0  
            sleep 60  
            if check_node; then  
                log "✓ 重启成功"  
            else  
                log "✗ 重启后仍失败"  
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