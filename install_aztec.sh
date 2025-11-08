#!/bin/bash  
# Aztec 2.1.2 安装脚本 v1.0.5 - 极简版  
  
VERSION="v1.0.5"  
  
echo "========================================"  
echo "  Aztec 节点安装脚本 $VERSION"  
echo "========================================"  
echo ""  
  
# 检查 root  
if [ "$EUID" -ne 0 ]; then  
    echo "错误: 需要 root 权限"  
    exit 1  
fi  
  
# 检查配置文件  
CONFIG_FILE="/root/aztec_start_command.txt"  
if [ ! -f "$CONFIG_FILE" ]; then  
    echo "错误: 未找到配置文件 $CONFIG_FILE"  
    exit 1  
fi  
  
cd /root || exit 1  
  
echo "[1/13] 清理环境..."  
pkill -f monitor_aztec 2>/dev/null || true  
tmux kill-server 2>/dev/null || true  
if [ -d "/root/.aztec" ]; then  
    cd /root/.aztec && docker compose down 2>/dev/null || true  
    cd /root  
fi  
docker rm -f aztec-sequencer 2>/dev/null || true  
rm -rf ~/.aztec  
echo "完成"  
  
echo ""  
echo "[2/13] 安装 Docker..."  
if ! command -v docker &> /dev/null; then  
    echo "安装 Docker..."  
    curl -fsSL https://get.docker.com | sh  
    systemctl enable docker  
    systemctl start docker  
fi  
echo "Docker 已就绪"  
  
echo ""  
echo "[3/13] 安装 Aztec..."  
bash -i <(curl -s https://install.aztec.network) 2>/dev/null || true  
if [ -f "$HOME/.bashrc" ]; then  
    source "$HOME/.bashrc"  
fi  
if [ -f "$HOME/.bash_profile" ]; then  
    source "$HOME/.bash_profile"  
fi  
aztec-up latest  
echo "Aztec 已安装"  
  
echo ""  
echo "[4/13] 安装 Cast (Foundry)..."  
FOUNDRY_BIN="$HOME/.foundry/bin"  
if ! command -v cast &> /dev/null; then  
    echo "下载 Foundry..."  
    curl -L https://foundry.paradigm.xyz | bash 2>/dev/null || true  
    mkdir -p "$FOUNDRY_BIN"  
      
    if [ ! -f "$FOUNDRY_BIN/foundryup" ]; then  
        curl -L https://raw.githubusercontent.com/foundry-rs/foundry/master/foundryup/foundryup -o "$FOUNDRY_BIN/foundryup"  
        chmod +x "$FOUNDRY_BIN/foundryup"  
    fi  
      
    "$FOUNDRY_BIN/foundryup"  
fi  
export PATH="$$FOUNDRY_BIN:$$PATH"  
echo "Cast 已安装"  
  
echo ""  
echo "[5/13] 解析配置文件..."  
L1_RPC=$$(grep -oP '(?<=--l1-rpc-urls ")[^"]*' "$$CONFIG_FILE" 2>/dev/null || grep -oP '(?<=--l1-rpc-urls )\S+' "$CONFIG_FILE")  
L1_CONSENSUS=$$(grep -oP '(?<=--l1-consensus-host-urls ")[^"]*' "$$CONFIG_FILE" 2>/dev/null || grep -oP '(?<=--l1-consensus-host-urls )\S+' "$CONFIG_FILE")  
VALIDATOR_KEY=$$(grep -oP '(?<=--sequencer.validatorPrivateKeys )[^\s\\]*' "$$CONFIG_FILE")  
COINBASE=$$(grep -oP '(?<=--sequencer.coinbase )[^\s\\]*' "$$CONFIG_FILE")  
P2P_IP=$$(grep -oP '(?<=--p2p.p2pIp )[^\s\\]*' "$$CONFIG_FILE")  
  
echo "  L1 RPC: $L1_RPC"  
echo "  Coinbase: $COINBASE"  
echo "  P2P IP: $P2P_IP"  
  
if [ -z "$$L1_RPC" ] || [ -z "$$VALIDATOR_KEY" ]; then  
    echo "错误: 配置解析失败"  
    exit 1  
fi  
  
echo ""  
echo "[6/13] 生成 Keystore..."  
echo ""  
echo "请输入此节点的 12 个单词助记词（空格分隔）："  
read -p "助记词: " MNEMONIC  
echo ""  
  
if [ -z "$MNEMONIC" ]; then  
    echo "错误: 助记词不能为空"  
    exit 1  
fi  
  
aztec validator-keys new --fee-recipient 0x0000000000000000000000000000000000000000 --mnemonic "$MNEMONIC"  
  
if [ ! -f ~/.aztec/keystore/key1.json ]; then  
    echo "错误: Keystore 生成失败"  
    exit 1  
fi  
  
if ! command -v jq &> /dev/null; then  
    echo "安装 jq..."  
    apt-get update -qq && apt-get install -y jq -qq  
fi  
  
BLS_KEY=$(jq -r '.validators[0].attester.bls' ~/.aztec/keystore/key1.json)  
ETH_ADDR=$(jq -r '.validators[0].attester.eth' ~/.aztec/keystore/key1.json)  
  
echo "  ETH 地址: $ETH_ADDR"  
echo "  BLS 密钥: ${BLS_KEY:0:10}..."  
  
echo ""  
echo "[7/13] 执行质押..."  
export PATH="$$FOUNDRY_BIN:$$PATH"  
  
if command -v cast &> /dev/null; then  
    CAST_CMD="cast"  
else  
    CAST_CMD="$FOUNDRY_BIN/cast"  
fi  
  
$$CAST_CMD send 0x139d2a7a0881e16332d7D1F8DB383A4507E1Ea7A "approve(address,uint256)" 0xebd99ff0ff6677205509ae73f93d0ca52ac85d67 200000ether --private-key "$$VALIDATOR_KEY" --rpc-url "$L1_RPC"  
echo "质押完成"  
  
echo ""  
echo "[8/13] 注册验证者..."  
aztec add-l1-validator --l1-rpc-urls "$$L1_RPC" --network testnet --private-key "$$VALIDATOR_KEY" --attester "$$COINBASE" --withdrawer "$$COINBASE" --bls-secret-key "$BLS_KEY" --rollup 0xebd99ff0ff6677205509ae73f93d0ca52ac85d67  
echo "注册完成"  
  
echo ""  
echo "[9/13] 生成 .env 文件..."  
mkdir -p /root/.aztec/data  
  
cat > /root/.aztec/.env << ENVEND  
DATA_DIRECTORY=./data  
KEY_STORE_DIRECTORY=./keystore  
LOG_LEVEL=info  
ETHEREUM_HOSTS=$L1_RPC  
L1_CONSENSUS_HOST_URLS=$L1_CONSENSUS  
P2P_IP=$P2P_IP  
P2P_PORT=40400  
AZTEC_PORT=8080  
AZTEC_ADMIN_PORT=8880  
ENVEND  
  
chmod 600 /root/.aztec/.env  
echo "配置完成"  
  
echo ""  
echo "[10/13] 生成 docker-compose.yml..."  
cat > /root/.aztec/docker-compose.yml << 'COMPOSEEND'  
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
      node --no-warnings /usr/src/yarn-project/aztec/dest/bin/index.js start --node --archiver --sequencer --network testnet  
    networks:  
      - aztec  
    restart: always  
networks:  
  aztec:  
COMPOSEEND  
  
echo "完成"  
  
echo ""  
echo "[11/13] 启动节点..."  
cd /root/.aztec  
docker compose up -d  
echo "等待 15 秒..."  
sleep 15  
  
echo ""  
echo "[12/13] 检查节点状态..."  
for i in 1 2 3; do  
    echo "第 $i 次检查..."  
    RESULT=$(curl -s -X POST -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' http://localhost:8080 | jq -r '.result.proven.number' 2>/dev/null || echo "")  
      
    if echo "$$RESULT" | grep -qE '^[0-9]+$$'; then  
        echo "✓ 节点运行正常！区块高度: $RESULT"  
        break  
    else  
        if [ $i -lt 3 ]; then  
            echo "检查失败，10秒后重试..."  
            sleep 10  
        fi  
    fi  
done  
  
echo ""  
echo "[13/13] 部署监控脚本..."  
cat > /root/monitor_aztec_node.sh << 'MONITOREND'  
#!/bin/bash  
  
LOG_FILE="/root/aztec_monitor.log"  
CHECK_INTERVAL=30  
FAIL_THRESHOLD=3  
FAIL_COUNT=0  
  
log() {  
    echo "[$$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $$1" | tee -a "$LOG_FILE"  
}  
  
wait_for_half_hour() {  
    CURRENT_MINUTE=$(date -u +%M)  
    CURRENT_SECOND=$(date -u +%S)  
    MINUTE_MOD=$((CURRENT_MINUTE % 30))  
      
    if [ $$MINUTE_MOD -eq 0 ] && [ $$CURRENT_SECOND -eq 0 ]; then  
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
        NEXT_TIME=$$(date -u -d "+$${WAIT_SECONDS} seconds" '+%H:%M:%S')  
        log "等待到 $${NEXT_TIME} UTC 开始监控 ($${WAIT_SECONDS}秒)"  
        sleep $WAIT_SECONDS  
    fi  
}  
  
check_node() {  
    RESULT=$(curl -s -X POST -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' http://localhost:8080 | jq -r '.result.proven.number' 2>/dev/null || echo "")  
      
    if echo "$$RESULT" | grep -qE '^[0-9]+$$'; then  
        return 0  
    else  
        return 1  
    fi  
}  
  
restart_node() {  
    log "======== 开始重启节点 ========"  
    cd /root/.aztec  
    docker compose down  
    sleep 5  
    if docker ps -a | grep -q aztec-sequencer; then  
        docker rm -f aztec-sequencer  
    fi  
    docker compose up -d  
    log "等待 30 秒..."  
    sleep 30  
    log "======== 重启完成 ========"  
}  
  
log "==================== 监控脚本启动 ===================="  
log "配置: 每$${CHECK_INTERVAL}秒检测一次，连续$${FAIL_THRESHOLD}次失败后重启"  
  
wait_for_half_hour  
  
log "========== 开始监控节点 =========="  
  
while true; do  
    if check_node; then  
        RESULT=$(curl -s -X POST -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' http://localhost:8080 | jq -r '.result.proven.number' 2>/dev/null)  
          
        if [ $FAIL_COUNT -gt 0 ]; then  
            log "✓ 节点恢复正常 | 区块高度: $RESULT"  
        else  
            log "✓ 节点正常 | 区块高度: $RESULT"  
        fi  
        FAIL_COUNT=0  
    else  
        FAIL_COUNT=$((FAIL_COUNT + 1))  
        log "✗ 节点检测失败 ($$FAIL_COUNT/$$FAIL_THRESHOLD)"  
          
        if [ $$FAIL_COUNT -ge $$FAIL_THRESHOLD ]; then  
            log "⚠ 连续失败 ${FAIL_COUNT} 次，触发重启..."  
            restart_node  
            FAIL_COUNT=0  
              
            log "重启后等待 60 秒验证..."  
            sleep 60  
              
            if check_node; then  
                RESULT=$(curl -s -X POST -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' http://localhost:8080 | jq -r '.result.proven.number' 2>/dev/null)  
                log "✓ 重启后验证成功 | 区块高度: $RESULT"  
            else  
                log "✗ 重启后验证失败"  
            fi  
        fi  
    fi  
      
    sleep $CHECK_INTERVAL  
done  
MONITOREND  
  
chmod +x /root/monitor_aztec_node.sh  
tmux new-session -d -s aztec_monitor "bash /root/monitor_aztec_node.sh"  
  
echo "监控脚本已启动"  
  
echo ""  
echo "========================================"  
echo "✓✓✓ 安装完成！ ✓✓✓"  
echo "========================================"  
echo ""  
echo "脚本版本: $VERSION"  
echo "节点地址: $COINBASE"  
echo "ETH 地址: $ETH_ADDR"  
echo ""  
echo "常用命令:"  
echo "  docker logs -f aztec-sequencer"  
echo "  tail -f /root/aztec_monitor.log"  
echo "  cd /root/.aztec && docker compose restart"  
echo ""  
echo "========================================"  
