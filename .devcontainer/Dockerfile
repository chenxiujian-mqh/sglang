# 使用 Ubuntu 20.04 作为基础镜像（匹配内网环境）
FROM ubuntu:20.04

# 避免 apt 交互式提示
ENV DEBIAN_FRONTEND=noninteractive

# 安装基础系统依赖（必须！）
RUN apt-get update && \
   apt-get install -y \
       curl \
       wget \
       git \
       build-essential \
       pkg-config \
       libssl-dev \
       ca-certificates \
       python3 \
       python3-pip \
       python3-venv \
       zsh \
       vim \
       tmux \
       sudo \
       && \
   rm -rf /var/lib/apt/lists/*

# 创建非 root 用户（解决 GitHub Codespaces 文件权限问题）
ARG HOST_UID=1003
ARG HOST_GID=1003
RUN groupadd -g $HOST_GID devuser && \
   useradd -m -u $HOST_UID -g $HOST_GID -s /bin/zsh devuser

# 配置 sudo 权限
RUN echo "devuser ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/devuser && \
   chmod 0440 /etc/sudoers.d/devuser

# 安装 oh-my-zsh（可选，提升体验）
RUN git clone https://github.com/ohmyzsh/ohmyzsh.git /home/devuser/.oh-my-zsh && \
   cp /home/devuser/.oh-my-zsh/templates/zshrc.zsh-template /home/devuser/.zshrc && \
   chown -R devuser:devuser /home/devuser

# 设置工作目录
WORKDIR /sgl-workspace/sglang
RUN mkdir -p /sgl-workspace/sglang && \
   chown -R devuser:devuser /sgl-workspace

# 切换到普通用户
USER devuser

# 安装 uv（Rust/Python 包管理加速器）
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# 安装 Rust（使用 rustup）
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal

# 将 Cargo/bin 加入 PATH（关键！）
ENV PATH="/home/devuser/.cargo/bin:/home/devuser/.local/bin:$PATH"
