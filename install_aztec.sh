#!/bin/bash  
# ============================================  
# Aztec 2.1.2 节点批量安装脚本  
# 版本: v1.0.2  
# 更新日期: 2025-01-08  
# 支持: Docker Compose + 自动监控 + Screen 会话  
# ============================================  
  
SCRIPT_VERSION="v1.0.2"  
  
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
      
    # 保存脚本路径  
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
    echo "--l1-consensus-host-urls*_
