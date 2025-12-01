#!/bin/bash

# 遇到错误立即停止
set -e

# --- 配置 ---
# 这一行是用来判断当前目录是不是项目根目录的特征文件
CHECK_FILE="api_server_v2.py"
PROJECT_REPO="https://github.com/Ksuriuri/index-tts-vllm.git"
PROJECT_DIR_NAME="index-tts-vllm"
ENV_NAME="index-tts-vllm"
LOG_FILE="api_server.log"

# --- 权限 ---
if [ "$EUID" -eq 0 ]; then SUDO_CMD=""; else SUDO_CMD="sudo"; fi

echo "============================================================"
echo "   IndexTTS-2 智能感知启动脚本 (V8)"
echo "============================================================"

# 1. 智能判断当前位置 (解决重复Clone的核心逻辑)
if [ -f "$CHECK_FILE" ]; then
    echo "📍 [位置] 检测到脚本已在项目根目录下运行。"
    # 既然在里面了，就不需要改路径
    WORK_DIR="."
else
    echo "📍 [位置] 脚本在项目外部，正在检查项目文件夹..."
    
    # 如果当前目录下没有项目文件夹，才去 Clone
    if [ ! -d "$PROJECT_DIR_NAME" ]; then
        echo "⬇️ [代码] 未找到项目，正在克隆..."
        git clone "$PROJECT_REPO"
    fi
    
    # 进入目录
    cd "$PROJECT_DIR_NAME"
    WORK_DIR="."
    echo "📂 [目录] 已进入 $PROJECT_DIR_NAME"
fi

# 现在的当前目录一定是项目根目录了，执行更新
echo "🔄 [代码] 尝试拉取最新代码 (git pull)..."
git pull || true

# 2. 基础工具检查
if ! command -v git &> /dev/null; then
    echo "[系统] 安装 git..."
    $SUDO_CMD apt update && $SUDO_CMD apt install -y git curl wget build-essential
fi

# 3. Conda 环境加载
CONDA_BASE=$(conda info --base 2>/dev/null || echo "$HOME/miniconda")
if [ -f "$CONDA_BASE/etc/profile.d/conda.sh" ]; then
    source "$CONDA_BASE/etc/profile.d/conda.sh"
elif [ -f "$HOME/anaconda3/etc/profile.d/conda.sh" ]; then
    source "$HOME/anaconda3/etc/profile.d/conda.sh"
else
    export PATH="$HOME/miniconda/bin:$PATH"
    source activate 2>/dev/null || true
fi

# 4. 激活环境
echo "[环境] 激活 Conda 环境..."
# 如果环境不存在，这里可能会报错，建议先手动保证环境建立，或者保持之前脚本的create逻辑
if ! conda info --envs | grep -q "$ENV_NAME"; then
     echo "⚠️ 环境不存在，正在创建..."
     conda create -n "$ENV_NAME" python=3.12 --override-channels -c conda-forge -y
fi
conda activate "$ENV_NAME" || source activate "$ENV_NAME"

# 5. 依赖补全
pip install -r requirements.txt 2>/dev/null | grep -v 'Requirement already satisfied' || true
pip install modelscope 2>/dev/null | grep -v 'Requirement already satisfied' || true

# 6. 模型检测 (V7版逻辑保持)
MODEL_REL_PATH="checkpoints/IndexTTS-2-vLLM"
if [ -d "$MODEL_REL_PATH" ] && [ "$(ls -A $MODEL_REL_PATH)" ]; then
    echo "✅ [模型] 检测到模型已存在，跳过下载。"
else
    echo "⬇️ [模型] 开始下载模型..."
    mkdir -p checkpoints
    python -c "from modelscope import snapshot_download; snapshot_download('kusuriuri/IndexTTS-2-vLLM', local_dir='$MODEL_REL_PATH')"
fi

# 7. 启动服务
echo "[服务] 重置服务..."
pkill -f "api_server_v2.py" || true
sleep 1

echo "[服务] 启动中 (显存 0.9)..."
# 注意：这里使用相对路径 checkpoints/...
nohup python api_server_v2.py \
    --model_dir "./$MODEL_REL_PATH" \
    --host 0.0.0.0 \
    --port 6006 \
    --gpu_memory_utilization 0.9 \
    > "$LOG_FILE" 2>&1 &

sleep 3
if pgrep -f "api_server_v2.py" > /dev/null; then
    echo "============================================================"
    echo "🚀 启动成功！"
    echo "📂 工作目录: $(pwd)"
    echo "📝 日志路径: $(pwd)/$LOG_FILE"
    echo "============================================================"
else
    echo "❌ 启动失败，请查看日志："
    tail -n 10 "$LOG_FILE"
fi
