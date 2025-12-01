#!/bin/bash

# 遇到错误立即停止
set -e

# --- 权限检测 ---
if [ "$EUID" -eq 0 ]; then
  SUDO_CMD=""
else
  SUDO_CMD="sudo"
fi

echo "========== [1/7] 更新系统软件源 =========="
$SUDO_CMD apt update
$SUDO_CMD apt install -y git curl wget build-essential

echo "========== [2/7] 检查 Conda 环境 =========="
if ! command -v conda &> /dev/null; then
    echo "Conda 未检测到，正在安装 Miniconda..."
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
    bash miniconda.sh -b -p $HOME/miniconda
    rm miniconda.sh
    source $HOME/miniconda/bin/activate
    conda init
else
    echo "Conda 已安装，正在加载..."
    if [ -f "$HOME/miniconda/etc/profile.d/conda.sh" ]; then
        source "$HOME/miniconda/etc/profile.d/conda.sh"
    elif [ -f "$HOME/anaconda3/etc/profile.d/conda.sh" ]; then
        source "$HOME/anaconda3/etc/profile.d/conda.sh"
    else
        CONDA_BASE=$(conda info --base 2>/dev/null || echo "")
        if [ -n "$CONDA_BASE" ]; then
            source "$CONDA_BASE/etc/profile.d/conda.sh"
        fi
    fi
fi

echo "========== [3/7] 克隆项目代码 =========="
PROJECT_DIR="index-tts-vllm"
if [ -d "$PROJECT_DIR" ]; then
    echo "项目目录已存在，进入目录..."
    cd "$PROJECT_DIR"
    git pull
else
    echo "正在克隆仓库..."
    git clone https://github.com/Ksuriuri/index-tts-vllm.git
    cd "$PROJECT_DIR"
fi

echo "========== [4/7] 创建虚拟环境 (使用 conda-forge) =========="
# 清理可能因上次失败残留的半成品环境
if conda info --envs | grep -q "index-tts-vllm"; then
    echo "检测到环境已存在，尝试删除以确保纯净重装..."
    conda remove -n index-tts-vllm --all -y || true
fi

echo "正在通过 conda-forge 创建 Python 3.12 环境..."
# 关键修改：添加 -c conda-forge 参数，绕过 Anaconda ToS
conda create -n index-tts-vllm python=3.12 -c conda-forge -y

# 激活环境
conda activate index-tts-vllm

echo "========== [5/7] 安装依赖库 =========="
echo "安装项目依赖..."
pip install --upgrade pip
pip install -r requirements.txt

echo "安装 modelscope..."
pip install modelscope

echo "========== [6/7] 下载 IndexTTS-2 模型权重 =========="
mkdir -p checkpoints
echo "正在下载 IndexTTS-2-vLLM 权重..."
python -c "from modelscope import snapshot_download; snapshot_download('kusuriuri/IndexTTS-2-vLLM', local_dir='./checkpoints/IndexTTS-2-vLLM')"

echo "========== [7/7] 后台启动 API 服务 =========="
pkill -f api_server_v2.py || true

MODEL_PATH="./checkpoints/IndexTTS-2-vLLM"

echo "正在启动 api_server_v2.py ..."
nohup python api_server_v2.py \
    --model_dir "$MODEL_PATH" \
    --host 0.0.0.0 \
    --port 6006 \
    --gpu_memory_utilization 0.25 \
    > api_server.log 2>&1 &

echo "----------------------------------------------------------------"
echo "部署成功！(已修复 ToS 问题)"
echo "查看日志: tail -f index-tts-vllm/api_server.log"
echo "----------------------------------------------------------------"
