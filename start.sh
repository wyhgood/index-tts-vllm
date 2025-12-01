#!/bin/bash

# 设置遇到错误立即停止，除了判断命令是否存在的逻辑
set -e

echo "========== [1/7] 更新系统软件源 =========="
sudo apt update
sudo apt install -y git curl wget build-essential

echo "========== [2/7] 检查并配置 Conda 环境 =========="
# 检查 conda 是否存在，不存在则安装 Miniconda
if ! command -v conda &> /dev/null; then
    echo "Conda 未检测到，正在安装 Miniconda..."
    wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh
    bash miniconda.sh -b -p $HOME/miniconda
    rm miniconda.sh
    source $HOME/miniconda/bin/activate
    conda init
else
    echo "Conda 已安装，正在加载..."
    # 尝试加载 conda profile
    source $(conda info --base)/etc/profile.d/conda.sh
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

echo "========== [4/7] 创建 Conda 虚拟环境 (index-tts-vllm) =========="
# 如果环境已存在则跳过创建，直接激活
if conda info --envs | grep -q "index-tts-vllm"; then
    echo "环境 index-tts-vllm 已存在，正在激活..."
else
    echo "创建 python 3.12 环境..."
    conda create -n index-tts-vllm python=3.12 -y
fi

# 激活环境
conda activate index-tts-vllm

echo "========== [5/7] 安装依赖库 =========="
# 安装 PyTorch (README 提及需要 pytorch 2.8.0 对应 vllm 0.10.2，但截至目前 pytorch 最新稳定版通常为 2.4/2.5)
# 这里我们优先信任 requirements.txt，通常 vllm 会自动拉取兼容的 torch
echo "安装项目依赖..."
pip install --upgrade pip
pip install -r requirements.txt

# 显式安装 modelscope 用于下载模型
echo "安装 modelscope..."
pip install modelscope

echo "========== [6/7] 下载 IndexTTS-2 模型权重 =========="
# 创建权重目录
mkdir -p checkpoints

# 使用 Python 脚本调用 modelscope 下载 IndexTTS-2-vLLM
echo "正在下载 IndexTTS-2-vLLM 权重，这可能需要一些时间..."
python -c "from modelscope import snapshot_download; snapshot_download('kusuriuri/IndexTTS-2-vLLM', local_dir='./checkpoints/IndexTTS-2-vLLM')"

echo "模型下载完成，路径: $(pwd)/checkpoints/IndexTTS-2-vLLM"

echo "========== [7/7] 后台启动 API 服务 =========="
# 杀掉可能存在的旧进程 (防止端口冲突)
pkill -f api_server_v2.py || true

# 定义模型路径
MODEL_PATH="./checkpoints/IndexTTS-2-vLLM"

# 启动参数说明：
# --model_dir: 模型路径
# --host: 0.0.0.0 允许外部访问
# --port: 6006 默认端口
# --gpu_memory_utilization: 0.25 (根据文档推荐)

echo "正在启动 api_server_v2.py ..."
nohup python api_server_v2.py \
    --model_dir "$MODEL_PATH" \
    --host 0.0.0.0 \
    --port 6006 \
    --gpu_memory_utilization 0.25 \
    > api_server.log 2>&1 &

echo "----------------------------------------------------------------"
echo "部署完成！API 服务正在后台运行。"
echo "API 地址: http://<服务器IP>:6006"
echo "查看日志命令: tail -f index-tts-vllm/api_server.log"
echo "----------------------------------------------------------------"
echo "客户端现在可以调用接口了。"
