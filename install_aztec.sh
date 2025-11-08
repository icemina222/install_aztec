#!/bin/bash  
# Aztec 2.1.2 安装脚本 v1.0.4  
SCRIPT_VERSION="v1.0.4"  
SCREEN_NAME="aztec_install"  
  
# 检查参数，如果是 --in-screen 就跳过 screen 创建  
if [ "$1" != "--in-screen" ]; then  
    # 第一次运行，创建 screen  
    clear  
    echo "========================================="  
    echo "  Aztec 节点安装脚本 $SCRIPT_VERSION"  
    echo "========================================="  
    echo ""  
      
    [ "$EUID" -ne 0 ] && { echo "错误: 需要 root 权限"; exit 1; }  
      
    command -v screen &> /dev/null || { echo "安装 screen..."; apt-get update -qq && apt-get install -y screen -qq; }  
      
    if screen -list | grep -q "$SCREEN_NAME"; then  
        echo "发现已有安装进程"  
        echo "1) 重新连接  2) 终止并重新开始  3) 退出"  
        read -p "选择: " choice  
        case $choice in  
            1) screen -r $SCREEN_NAME; exit 0 ;;  
            2) screen -S $SCREEN_NAME -X quit; sleep 2 ;;  
            3) exit 0 ;;  
        esac  
    fi  
      
    echo "即将在 screen 中启动安装"  
    echo ""  
    echo "Screen 使用:"  
    echo "  断开: Ctrl+A 然后按 D"  
    echo "  重连: screen -r $SCREEN_NAME"  
    echo ""  
    echo "准备好助记词！"  
    echo ""  
    read -p "按 Enter 开始..."   
      
<<<<<<< HEAD
    SCRIPT_PATH="$$(realpath "$$0")"  
=======
    read -p "按 Enter 键开始安装..."   
    echo ""  
      
    # 保存脚本路径（修复语法错误）  
    SCRIPT_FULL_PATH="$(realpath "$0")"  
  
      
    # 在 screen 中重新运行自己  
    echo_info "创建 screen 会话: $SCREEN_NAME"  
    sleep 1  
      
    # 使用更简单直接的方式  
    screen -dmS $$SCREEN_NAME bash -c "exec bash '$$SCRIPT_FULL_PATH' --in-screen 2>&1 | tee /root/install_aztec.log"  
>>>>>>> f0fdada46896148072abadd6d85aecd01206d9ea
      
    # 创建 screen 并传递 --in-screen 参数  
    screen -dmS $$SCREEN_NAME bash -c "bash '$$SCRIPT_PATH' --in-screen 2>&1 | tee /root/install_aztec.log"  
    sleep 2  
      
    if screen -list | grep -q "$SCREEN_NAME"; then  
        echo "正在连接到 screen..."  
        sleep 1  
        screen -r $SCREEN_NAME  
    else  
        echo "Screen 创建失败，直接运行..."  
        bash "$SCRIPT_PATH" --in-screen  
    fi  
    exit 0  
fi  
  
# ============================================  
# 以下是真正的安装流程（在 screen 中执行）  
# ============================================  
  
cd /root || exit 1  
  
echo ""  
echo "===== Aztec 安装 $SCRIPT_VERSION ====="  
echo ""  
  
[ "$EUID" -ne 0 ] && { echo "错误: 需要 root"; exit 1; }  
  
CONFIG_FILE="/root/aztec_start_command.txt"  
[ ! -f "$$CONFIG_FILE" ] && { echo "错误: 未找到配置文件 $$CONFIG_FILE"; read -p "按任意键退出..."; exit 1; }  
  
echo "[1/13] 清理环境..."  
pkill -f monitor_aztec_node.sh 2>/dev/null || true  
tmux kill-server 2>/dev/null || true  
[ -d "/root/.aztec" ] && { cd /root/.aztec && docker compose down 2>/dev/null || true; cd /root; }  
docker rm -f aztec-sequencer 2>/dev/null || true  
rm -rf ~/.aztec  
echo "完成"  
  
echo ""  
echo "[2/13] 安装 Docker..."  
if ! command -v docker &> /dev/null; then  
    curl -fsSL https://get.docker.com | sh  
    systemctl enable docker  
    systemctl start docker  
fi  
echo "Docker 已就绪"  
  
echo ""  
echo "[3/13] 安装 Aztec..."  
cd /root  
bash -i <(curl -s https://install.aztec.network) 2>/dev/null || true  
[ -f "$$HOME/.bash_profile" ] && source "$$HOME/.bash_profile"  
[ -f "$$HOME/.bashrc" ] && source "$$HOME/.bashrc"  
aztec-up latest  
echo "Aztec 已安装"  
  
echo ""  
echo "[4/13] 安装 Cast..."  
FOUNDRY_BIN="$HOME/.foundry/bin"  
if ! command -v cast &> /dev/null; then  
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
echo "[5/13] 解析配置..."  
L1_RPC=$$(grep -oP '(?<=--l1-rpc-urls ")[^"]*' "$$CONFIG_FILE" 2>/dev/null || grep -oP "(?<=--l1-rpc-urls )\S+" "$CONFIG_FILE")  
L1_CONSENSUS=$$(grep -oP '(?<=--l1-consensus-host-urls ")[^"]*' "$$CONFIG_FILE" 2>/dev/null || grep -oP "(?<=--l1-consensus-host-urls )\S+" "$CONFIG_FILE")  
VALIDATOR_KEY=$$(grep -oP '(?<=--sequencer.validatorPrivateKeys )[^\s\\]*' "$$CONFIG_FILE")  
COINBASE=$$(grep -oP '(?<=--sequencer.coinbase )[^\s\\]*' "$$CONFIG_FILE")  
P2P_IP=$$(grep -oP '(?<=--p2p.p2pIp )[^\s\\]*' "$$CONFIG_FILE")  
  
echo "  L1 RPC: $L1_RPC"  
echo "  Coinbase: $COINBASE"  
echo "  P2P IP: $P2P_IP"  
  
[ -z "$$L1_RPC" ] || [ -z "$$VALIDATOR_KEY" ] && { echo "错误: 配置解析失败"; read -p "按任意键退出..."; exit 1; }  
  
echo ""  
echo "[6/13] 生成 Keystore..."  
echo ""  
echo "请输入 12 个单词助记词（空格分隔）："  
read -p "助记词: " MNEMONIC  
echo ""  
  
[ -z "$MNEMONIC" ] && { echo "错误: 助记词为空"; read -p "按任意键退出..."; exit 1; }  
  
aztec validator-keys new --fee-recipient 0x0000000000000000000000000000000000000000 --mnemonic "$MNEMONIC"  
  
[ ! -f ~/.aztec/keystore/key1.json ] && { echo "错误: Keystore 生成失败"; read -p "按任意键退出..."; exit 1; }  
  
command -v jq &> /dev/null || { apt-get update -qq && apt-get install -y jq -qq; }  
  
BLS_KEY=$(jq -r '.validators[0].attester.bls' ~/.aztec/keystore/key1.json)  
ETH_ADDR=$(jq -r '.validators[0].attester.eth' ~/.aztec/keystore/key1.json)  
  
echo "  ETH 地址: $ETH_ADDR"  
echo "  BLS 密钥: ${BLS_KEY:0:10}..."  
  
echo ""  
echo "[7/13] 执行质押..."  
export PATH="$$FOUNDRY_BIN:$$PATH"  
CAST_CMD=$$(command -v cast || echo "$$FOUNDRY_BIN/cast")  
$$CAST_CMD send 0x139d2a7a0881e16332d7D1F8DB383A4507E1Ea7A "approve(address,uint256)" 0xebd99ff0ff6677205509ae73f93d0ca52ac85d67 200000ether --private-key "$$VALIDATOR_KEY" --rpc-url "$L1_RPC"  
echo "质押完成"  
  
echo ""  
echo "[8/13] 注册验证者..."  
aztec add-l1-validator --l1-rpc-urls "$$L1_RPC" --network testnet --private-key "$$VALIDATOR_KEY" --attester "$$COINBASE" --withdrawer "$$COINBASE" --bls-secret-key "$BLS_KEY" --rollup 0xebd99ff0ff6677205509ae73f93d0ca52ac85d67  
echo "注册完成"  
  
echo ""  
echo "[9/13] 生成配置文件..."  
mkdir -p /root/.aztec/data  
cat > /root/.aztec/.env << ENVEOF  
DATA_DIRECTORY=./data  
KEY_STORE_DIRECTORY=./keystore  
LOG_LEVEL=info  
ETHEREUM_HOSTS=$L1_RPC  
L1_CONSENSUS_HOST_URLS=$L1_CONSENSUS  
P2P_IP=$P2P_IP  
P2P_PORT=40400  
AZTEC_PORT=8080  
AZTEC_ADMIN_PORT=8880  
ENVEOF  
chmod 600 /root/.aztec/.env  
echo "配置完成"  
  
echo ""  
echo "[10/13] 生成 docker-compose.yml..."  
cat > /root/.aztec/docker-compose.yml << 'DCEOF'  
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
DCEOF  
echo "完成"  
  
echo ""  
echo "[11/13] 启动节点..."  
cd /root/.aztec  
docker compose up -d  
echo "等待 15 秒..."  
sleep 15  
  
echo ""  
echo "[12/13] 检查节点状态..."  
for i in {1..3}; do  
    echo "第 $i 次检查..."  
    RESULT=$(curl -s -X POST -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' http://localhost:8080 | jq -r ".result.proven.number" 2>/dev/null || echo "")  
    if [[ "$$RESULT" =~ ^[0-9]+$$ ]]; then  
        echo "✓ 节点正常！区块高度: $RESULT"  
        break  
    else  
        [ $i -lt 3 ] && { echo "检查失败，10秒后重试..."; sleep 10; }  
    fi  
done  
  
echo ""  
echo "[13/13] 部署监控脚本..."  
cat > /root/monitor_aztec_node.sh << 'MONEOF'  
#!/bin/bash  
LOG="/root/aztec_monitor.log"  
log() { echo "[$$(date -u '+%Y-%m-%d %H:%M:%S UTC')] $$1" | tee -a "$LOG"; }  
  
wait_half_hour() {  
    M=$(date -u +%M)  
    S=$(date -u +%S)  
    MOD=$((M % 30))  
    if [ $$MOD -eq 0 ] && [ $$S -eq 0 ]; then  
        W=0  
    else  
        W=$(( (30 - MOD - 1) * 60 + 60 - S ))  
    fi  
    [ $$W -gt 0 ] && { T=$$(date -u -d "+$${W} seconds" '+%H:%M:%S'); log "等待到 $$T UTC"; sleep $W; }  
}  
  
check() {  
    R=$(curl -s -X POST -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' http://localhost:8080 | jq -r ".result.proven.number" 2>/dev/null || echo "")  
    [[ "$$R" =~ ^[0-9]+$$ ]]  
}  
  
restart() {  
    log "======== 开始重启 ========"  
    cd /root/.aztec  
    docker compose down  
    sleep 5  
    docker ps -a | grep -q aztec-sequencer && docker rm -f aztec-sequencer  
    docker compose up -d  
    sleep 30  
    log "======== 重启完成 ========"  
}  
  
log "==================== 监控启动 ===================="  
wait_half_hour  
log "========== 开始监控 =========="  
  
FC=0  
while true; do  
    if check; then  
        R=$(curl -s -X POST -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","method":"node_getL2Tips","params":[],"id":67}' http://localhost:8080 | jq -r ".result.proven.number" 2>/dev/null)  
        [ $$FC -gt 0 ] && log "✓ 节点恢复 | 区块: $$R" || log "✓ 节点正常 | 区块: $R"  
        FC=0  
    else  
        FC=$((FC + 1))  
        log "✗ 节点失败 ($FC/3)"  
        if [ $FC -ge 3 ]; then  
            log "⚠ 触发重启..."  
            restart  
            FC=0  
            sleep 60  
            check && log "✓ 重启成功" || log "✗ 重启后仍失败"  
        fi  
    fi  
    sleep 30  
done  
MONEOF  
  
chmod +x /root/monitor_aztec_node.sh  
tmux new-session -d -s aztec_monitor "bash /root/monitor_aztec_node.sh"  
echo "监控已启动"  
  
echo ""  
echo "========================================="  
echo "✓✓✓ 安装完成！ ✓✓✓"  
echo "========================================="  
echo ""  
echo "节点地址: $COINBASE"  
echo "ETH 地址: $ETH_ADDR"  
echo ""  
echo "常用命令:"  
echo "  docker logs -f aztec-sequencer"  
echo "  tail -f /root/aztec_monitor.log"  
echo ""  
echo "按任意键退出 screen..."  
read -n 1  
