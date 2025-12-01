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
    CONDA_BASE=$(conda info --base 2>/dev/null || echo "$HOME/miniconda")
    [ -f "$CONDA_BASE/etc/profile.d/conda.sh" ] && source "$CONDA_BASE/etc/profile.d/conda.sh"
fi

echo "========== [3/7] 强制修复 Conda 源配置 (关键步骤) =========="
# 这一步会覆盖 .condarc 文件，只保留 conda-forge，彻底屏蔽报错的 defaults 源
echo "正在重写 ~/.condarc 配置..."
cat > ~/.condarc <<EOF
channels:
  - conda-forge
show_channel_urls: true
default_channels:
  - https://conda.anaconda.org/conda-forge
channel_priority: strict
EOF

echo "清除索引缓存..."
conda clean --all -y

echo "========== [4/7] 克隆项目代码 =========="
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

echo "========== [5/7] 创建虚拟环境 =========="
# 清理旧环境
conda remove -n index-tts-vllm --all -y || true

echo "创建 Python 3.12 环境 (已屏蔽官方源)..."
# 使用 --override-channels 双重保险
conda create -n index-tts-vllm python=3.12 --override-channels -c conda-forge -y

# 激活环境
conda activate index-tts-vllm

echo "========== [6/7] 安装依赖库 =========="
echo "安装项目依赖..."
pip install --upgrade pip
pip install -r requirements.txt

echo "安装 modelscope..."
pip install modelscope

echo "========== [7/7] 下载模型并启动 =========="
mkdir -p checkpoints
echo "正在下载 IndexTTS-2-vLLM 权重..."
python -c "from modelscope import snapshot_download; snapshot_download('kusuriuri/IndexTTS-2-vLLM', local_dir='./checkpoints/IndexTTS-2-vLLM')"

# 杀掉旧进程
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
echo "部署成功！"
echo "查看日志: tail -f index-tts-vllm/api_server.log"
echo "----------------------------------------------------------------"
