#!/bin/bash

# 遇到错误立即停止
set -e

# --- 配置 ---
CHECK_FILE="api_server_v2.py"
PROJECT_REPO="https://github.com/Ksuriuri/index-tts-vllm.git"
PROJECT_DIR_NAME="index-tts-vllm"
ENV_NAME="index-tts-vllm"
LOG_FILE="api_server.log"
# 模型路径
MODEL_REL_PATH="checkpoints/IndexTTS-2-vLLM"

# --- 权限 ---
if [ "$EUID" -eq 0 ]; then SUDO_CMD=""; else SUDO_CMD="sudo"; fi

echo "============================================================"
echo "   IndexTTS-2 暴力清理显存启动版 (V9)"
echo "============================================================"

# 1. 智能位置判断
if [ -f "$CHECK_FILE" ]; then
    echo "📍 [位置] 当前已在项目目录。"
    WORK_DIR="."
else
    echo "📍 [位置] 脚本在外部，检查项目..."
    if [ ! -d "$PROJECT_DIR_NAME" ]; then
        echo "⬇️ [代码] 克隆项目..."
        git clone "$PROJECT_REPO"
    fi
    cd "$PROJECT_DIR_NAME"
    WORK_DIR="."
fi

# 2. 代码更新
echo "🔄 [代码] 检查更新..."
git pull || true

# 3. 基础环境
if ! command -v git &> /dev/null; then
    $SUDO_CMD apt update && $SUDO_CMD apt install -y git curl wget build-essential
fi

# 4. Conda 环境
CONDA_BASE=$(conda info --base 2>/dev/null || echo "$HOME/miniconda")
if [ -f "$CONDA_BASE/etc/profile.d/conda.sh" ]; then
    source "$CONDA_BASE/etc/profile.d/conda.sh"
elif [ -f "$HOME/anaconda3/etc/profile.d/conda.sh" ]; then
    source "$HOME/anaconda3/etc/profile.d/conda.sh"
else
    export PATH="$HOME/miniconda/bin:$PATH"
    source activate 2>/dev/null || true
fi

# 激活环境
if ! conda info --envs | grep -q "$ENV_NAME"; then
     conda create -n "$ENV_NAME" python=3.12 --override-channels -c conda-forge -y
fi
conda activate "$ENV_NAME" || source activate "$ENV_NAME"

# 5. 依赖与模型
pip install -r requirements.txt 2>/dev/null | grep -v 'Requirement already satisfied' || true
pip install modelscope 2>/dev/null | grep -v 'Requirement already satisfied' || true

if [ -d "$MODEL_REL_PATH" ] && [ "$(ls -A $MODEL_REL_PATH)" ]; then
    echo "✅ [模型] 已存在，跳过下载。"
else
    echo "⬇️ [模型] 下载中..."
    mkdir -p checkpoints
    python -c "from modelscope import snapshot_download; snapshot_download('kusuriuri/IndexTTS-2-vLLM', local_dir='$MODEL_REL_PATH')"
fi

# ========================================================
# 7. 暴力清理显存与重启逻辑 (核心修改)
# ========================================================
echo "🧹 [服务] 正在清理旧进程与显存..."

# 1. 发送强制终止信号 (kill -9)
# 同时查找 api_server_v2.py 和可能残留的 vllm 进程
PIDS=$(pgrep -f "api_server_v2.py" || true)

if [ -n "$PIDS" ]; then
    echo "   检测到进程 ID: $PIDS，正在强制击杀..."
    echo "$PIDS" | xargs kill -9 2>/dev/null || true
else
    echo "   没有发现运行中的进程。"
fi

# 2. 死循环等待，直到进程彻底消失
echo "   正在确认进程完全退出..."
while pgrep -f "api_server_v2.py" > /dev/null; do
    echo "   ...等待进程释放资源..."
    sleep 1
done

# 3. 显存冷却时间 (关键)
# 进程虽然没了，但 NVIDIA 驱动回收显存需要几秒钟
echo "❄️  [显存] 等待 NVIDIA 驱动回收显存 (3秒)..."
sleep 3

echo "🚀 [服务] 正在启动 (显存利用率 0.9)..."
nohup python api_server_v2.py \
    --model_dir "./$MODEL_REL_PATH" \
    --host 0.0.0.0 \
    --port 6006 \
    --gpu_memory_utilization 0.9 \
    > "$LOG_FILE" 2>&1 &

sleep 5
if pgrep -f "api_server_v2.py" > /dev/null; then
    echo "✅ 启动成功！"
    echo "📝 日志: $(pwd)/$LOG_FILE"
else
    echo "❌ 启动失败，最后10行日志："
    tail -n 10 "$LOG_FILE"
fi
