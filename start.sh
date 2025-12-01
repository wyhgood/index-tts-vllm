#!/bin/bash

# 遇到错误立即停止 (除了特定的检查命令)
set -e

# --- 基础配置 ---
PROJECT_NAME="index-tts-vllm"
ENV_NAME="index-tts-vllm"
MODEL_DIR="./checkpoints/IndexTTS-2-vLLM"
LOG_FILE="api_server.log"

# --- 权限检测 ---
if [ "$EUID" -eq 0 ]; then
  SUDO_CMD=""
else
  SUDO_CMD="sudo"
fi

echo "============================================================"
echo "   IndexTTS-2 智能部署/重启脚本 (V5)"
echo "============================================================"

# 1. 基础环境检查 (快速掠过)
if ! command -v git &> /dev/null; then
    echo "[系统] 检测到缺少 git，正在安装..."
    $SUDO_CMD apt update && $SUDO_CMD apt install -y git curl wget build-essential
fi

# 2. Conda 加载
echo "[Conda] 正在加载 Conda 环境..."
# 尝试定位 Conda
CONDA_BASE=$(conda info --base 2>/dev/null || echo "$HOME/miniconda")
if [ -f "$CONDA_BASE/etc/profile.d/conda.sh" ]; then
    source "$CONDA_BASE/etc/profile.d/conda.sh"
elif [ -f "$HOME/anaconda3/etc/profile.d/conda.sh" ]; then
    source "$HOME/anaconda3/etc/profile.d/conda.sh"
else
    # 如果实在找不到，尝试安装 (仅在真的没有conda命令时)
    if ! command -v conda &> /dev/null; then
        echo "[Conda] 未检测到 Conda，开始安装 Miniconda..."
        wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
        bash miniconda.sh -b -p $HOME/miniconda
        rm miniconda.sh
        source $HOME/miniconda/bin/activate
        conda init
        
        # 修复源 (仅在初次安装时执行)
        echo "[Conda] 配置 conda-forge 源..."
        cat > ~/.condarc <<EOF
channels:
  - conda-forge
show_channel_urls: true
default_channels:
  - https://conda.anaconda.org/conda-forge
channel_priority: strict
EOF
    fi
fi

# 3. 项目代码同步
echo "[代码] 检查项目代码..."
if [ -d "$PROJECT_NAME" ]; then
    cd "$PROJECT_NAME"
    echo "[代码] 项目已存在，执行 git pull 更新..."
    git pull
else
    echo "[代码] 克隆项目..."
    git clone https://github.com/Ksuriuri/index-tts-vllm.git
    cd "$PROJECT_NAME"
fi

# 4. 虚拟环境检查
echo "[环境] 检查虚拟环境 '$ENV_NAME'..."
if conda info --envs | grep -q "$ENV_NAME"; then
    echo "[环境] 环境已存在，跳过创建，直接激活。"
    conda activate "$ENV_NAME"
else
    echo "[环境] 环境不存在，正在创建 (Python 3.12)..."
    # 使用 --override-channels 和 -c conda-forge 确保成功
    conda create -n "$ENV_NAME" python=3.12 --override-channels -c conda-forge -y
    conda activate "$ENV_NAME"
fi

# 5. 依赖安装 (pip 会自动跳过已安装的包，速度很快)
echo "[依赖] 检查/安装依赖..."
pip install -r requirements.txt 2>/dev/null | grep -v 'Requirement already satisfied' || true
pip install modelscope 2>/dev/null | grep -v 'Requirement already satisfied' || true

# 6. 模型检查
echo "[模型] 检查模型权重..."
if [ -d "$MODEL_DIR" ] && [ "$(ls -A $MODEL_DIR)" ]; then
    echo "[模型] 检测到模型目录 '$MODEL_DIR' 且不为空，跳过下载。"
else
    echo "[模型] 模型缺失，开始下载 IndexTTS-2-vLLM..."
    mkdir -p checkpoints
    python -c "from modelscope import snapshot_download; snapshot_download('kusuriuri/IndexTTS-2-vLLM', local_dir='$MODEL_DIR')"
fi

# 7. 服务重启 (核心逻辑)
echo "[服务] 准备重启 API 服务..."

# 查找并杀掉旧进程
PID=$(pgrep -f "api_server_v2.py")
if [ -n "$PID" ]; then
    echo "[服务] 停止旧进程 (PID: $PID)..."
    kill -9 $PID
else
    echo "[服务] 没有运行中的旧进程。"
fi

echo "[服务] 正在启动新进程..."
# 后台启动
nohup python api_server_v2.py \
    --model_dir "$MODEL_DIR" \
    --host 0.0.0.0 \
    --port 6006 \
    --gpu_memory_utilization 0.25 \
    > "$LOG_FILE" 2>&1 &

# 稍微等待一下，检查是否立即报错退出
sleep 3
if pgrep -f "api_server_v2.py" > /dev/null; then
    echo "============================================================"
    echo "✅ 服务启动成功！"
    echo "📍 地址: http://<你的IP>:6006"
    echo "📝 日志: tail -f $PROJECT_NAME/$LOG_FILE"
    echo "============================================================"
else
    echo "============================================================"
    echo "❌ 服务启动失败！请检查日志："
    echo "cat $PROJECT_NAME/$LOG_FILE"
    echo "============================================================"
    exit 1
fi
