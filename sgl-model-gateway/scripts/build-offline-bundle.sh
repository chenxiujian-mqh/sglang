#!/bin/bash  
set -e  
export DEBIAN_FRONTEND=noninteractive  
apt-get update  
  
# === 1. 安装系统依赖 ===  
apt-get install -y curl wget git build-essential pkg-config libssl-dev \  
  python3 python3-pip ca-certificates tar gzip unzip \  
  gcc-10 g++-10 protobuf-compiler  
  
# === 2. 安装新版 protoc ===  
PROTOC_VERSION=3.20.1  
curl -LO "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-linux-x86_64.zip"  
unzip "protoc-${PROTOC_VERSION}-linux-x86_64.zip" -d /usr/local  
rm "protoc-${PROTOC_VERSION}-linux-x86_64.zip"  
export PATH="/usr/local/bin:$PATH"  
protoc --version  
  
# === 3. 设置 gcc-10 ===  
update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 100  
update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-10 100  
export CC=gcc-10  
export CXX=g++-10  
  
# === 4. 安装 Rust ===  
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal  
source "$HOME/.cargo/env"  
rustup toolchain install 1.90.0 --profile minimal  
rustup toolchain install nightly --profile minimal  
rustup default 1.90.0  
  
# === 5. 进入项目目录 ===  
cd /workspace/sgl-model-gateway  
  
# === 6. 更新 lock 文件 ===  
cargo update  
  
# === 7. 验证构建 ===  
cargo build --locked  
  
# === 8. Vendor 所有依赖（含 git 依赖）===  
mkdir -p .cargo  
cargo vendor > .cargo/config.toml 2>/dev/null || {  
  echo "Vendor output:"  
  cat .cargo/config.toml  
}  
  
# === 9. 创建输出目录 ===  
BUNDLE_DIR="/workspace/sgl-model-gateway-offline-dev-bundle"  
mkdir -p "$BUNDLE_DIR/docs"  
mkdir -p "$BUNDLE_DIR/apt-packages"  
  
# === 10. 打包 Rust 工具链 ===  
tar -czf "$BUNDLE_DIR/rust-toolchain.tar.gz" \  
  -C "$HOME/.rustup/toolchains" \  
  1.90.0-x86_64-unknown-linux-gnu \  
  nightly-x86_64-unknown-linux-gnu  
  
# === 11. 打包 vendor 依赖 ===  
tar -czf "$BUNDLE_DIR/cargo-vendor.tar.gz" \  
  -C "$PWD" vendor  
  
# === 12. 打包完整项目源码（排除 target/ 和 vendor/）===  
# 包含：src/ tests/ benches/ bindings/ e2e_test/ scripts/  
#        build.rs Cargo.toml Cargo.lock .cargo/  
#        Makefile rustfmt.toml pytest.ini README.md  
tar -czf "$BUNDLE_DIR/sgl-model-gateway-src.tar.gz" \  
  --exclude="./target" \  
  --exclude="./vendor" \  
  -C "$PWD" \  
  .  
  
# === 13. 收集 apt 离线包（从容器缓存中复制）===  
find /var/cache/apt/archives/ -name "*.deb" \  
  -exec cp {} "$BUNDLE_DIR/apt-packages/" \; 2>/dev/null || true  
  
# === 14. 打包 protoc zip（供离线安装）===  
curl -LO "https://github.com/protocolbuffers/protobuf/releases/download/v${PROTOC_VERSION}/protoc-${PROTOC_VERSION}-linux-x86_64.zip"  
mv "protoc-${PROTOC_VERSION}-linux-x86_64.zip" "$BUNDLE_DIR/"  
  
# === 15. 创建 README.md ===  
cat > "$BUNDLE_DIR/README.md" << 'EOF'  
# sgl-model-gateway Offline Dev Bundle  
  
This bundle contains everything needed to build, run, and develop  
sgl-model-gateway on an air-gapped Ubuntu 20.04 (x86_64) machine.  
  
## Contents  
- rust-toolchain.tar.gz         Rust 1.90.0 + nightly toolchains  
- cargo-vendor.tar.gz           All Rust crate sources (incl. git deps)  
- sgl-model-gateway-src.tar.gz  Complete project source (src, tests, benches, bindings, build.rs, etc.)  
- apt-packages/                 Offline .deb packages for system dependencies  
- protoc-*.zip                  Protocol Buffers compiler v3.20.1  
- setup-offline.sh              One-click setup script  
  
## Quick Start  
  chmod +x setup-offline.sh  
  ./setup-offline.sh  
  source ~/.bashrc  
  cd sgl-model-gateway  
  cargo run --offline --bin smg -- [args]  
EOF  
  
# === 16. 创建环境要求文档 ===  
cat > "$BUNDLE_DIR/docs/environment-requirements.md" << 'EOF'  
## Environment Requirements  
- OS: Ubuntu 20.04 LTS (Focal Fossa)  
- Architecture: x86_64  
- GLIBC: >= 2.31  
- Disk space: ~3 GB free  
- No internet required after unpacking  
EOF  
  
# === 17. 创建开发指南 ===  
cat > "$BUNDLE_DIR/docs/how-to-develop.md" << 'EOF'  
## Offline Development Guide  
  
### Build  
  cargo build --offline  
  
### Run (equivalent to go run)  
  cargo run --offline --bin smg -- launch --worker-urls http://worker:8000  
  cargo run --offline --bin sgl-model-gateway -- [args]  
  
### Test  
  cargo test --offline  
  
### Format  
  cargo fmt  
  
### Lint  
  cargo clippy --offline  
  
### Adding new dependencies  
  Not supported in fully offline mode.  
  Add deps online, re-run cargo vendor, and rebuild the bundle.  
EOF  
  
# === 18. 创建 setup-offline.sh ===  
# 注意：此处使用 echo 逐行写入，避免嵌套 heredoc 问题  
SETUP="$BUNDLE_DIR/setup-offline.sh"  
  
cat > "$SETUP" << 'SETUP_SCRIPT'  
#!/bin/bash  
set -e  
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  
echo "=== sgl-model-gateway Offline Dev Setup ==="  
  
# Detect OS  
OS_VERSION="$(lsb_release -rs 2>/dev/null || echo unknown)"  
if [ "$OS_VERSION" != "20.04" ]; then  
  echo "Warning: This bundle targets Ubuntu 20.04. Detected: $(lsb_release -d 2>/dev/null || echo 'Unknown OS')"  
  read -p "Continue anyway? (y/N): " -n 1 -r  
  echo  
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then  
    exit 1  
  fi  
fi  
  
# === 1. 安装系统依赖（优先使用离线 .deb 包）===  
echo "[1/6] Installing system dependencies..."  
if ls "$SCRIPT_DIR/apt-packages/"*.deb 1>/dev/null 2>&1; then  
  sudo dpkg -i "$SCRIPT_DIR/apt-packages/"*.deb 2>/dev/null || true  
  sudo apt-get install -f -y 2>/dev/null || true  
else  
  echo "Warning: No .deb packages found, falling back to online install..."  
  sudo apt-get update || true  
  sudo apt-get install -y build-essential pkg-config libssl-dev gcc-10 g++-10 protobuf-compiler || true  
fi  
  
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-10 100 2>/dev/null || true  
sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-10 100 2>/dev/null || true  
  
# === 2. 安装 protoc ===  
echo "[2/6] Installing protoc..."  
PROTOC_ZIP=$(ls "$SCRIPT_DIR"/protoc-*.zip 2>/dev/null | head -1)  
if [ -n "$PROTOC_ZIP" ]; then  
  sudo unzip -o "$PROTOC_ZIP" -d /usr/local bin/protoc 'include/*'  
  echo "protoc: $(protoc --version)"  
else  
  echo "Warning: protoc zip not found in bundle, skipping."  
fi  
  
# === 3. 解压 Rust 工具链 ===  
echo "[3/6] Extracting Rust toolchain..."  
mkdir -p "$HOME/.rustup/toolchains"  
tar -xzf "$SCRIPT_DIR/rust-toolchain.tar.gz" -C "$HOME/.rustup/toolchains"  
  
TOOLCHAIN_DIR="$HOME/.rustup/toolchains/1.90.0-x86_64-unknown-linux-gnu"  
  
# === 4. 配置 cargo/rustc（不依赖 rustup）===  
echo "[4/6] Configuring Rust environment..."  
mkdir -p "$HOME/.cargo/bin"  
ln -sf "$TOOLCHAIN_DIR/bin/cargo"         "$HOME/.cargo/bin/cargo"  
ln -sf "$TOOLCHAIN_DIR/bin/rustc"         "$HOME/.cargo/bin/rustc"  
ln -sf "$TOOLCHAIN_DIR/bin/rustfmt"       "$HOME/.cargo/bin/rustfmt"       2>/dev/null || true  
ln -sf "$TOOLCHAIN_DIR/bin/cargo-clippy"  "$HOME/.cargo/bin/cargo-clippy"  2>/dev/null || true  
ln -sf "$TOOLCHAIN_DIR/bin/clippy-driver" "$HOME/.cargo/bin/clippy-driver" 2>/dev/null || true  
  
# 写入 ~/.bashrc（幂等，使用 echo 避免嵌套 heredoc）  
if ! grep -q "RUSTUP_TOOLCHAIN" ~/.bashrc 2>/dev/null; then  
  echo '# sgl-model-gateway offline dev environment'                                                >> ~/.bashrc  
  echo 'export RUSTUP_TOOLCHAIN="1.90.0-x86_64-unknown-linux-gnu"'                                 >> ~/.bashrc  
  echo 'export PATH="$HOME/.rustup/toolchains/1.90.0-x86_64-unknown-linux-gnu/bin:$HOME/.cargo/bin:$PATH"' >> ~/.bashrc  
  echo 'export CC=gcc-10'                                                                           >> ~/.bashrc  
  echo 'export CXX=g++-10'                                                                         >> ~/.bashrc  
fi  
  
export RUSTUP_TOOLCHAIN="1.90.0-x86_64-unknown-linux-gnu"  
export PATH="$TOOLCHAIN_DIR/bin:$HOME/.cargo/bin:$PATH"  
export CC=gcc-10  
export CXX=g++-10  
  
# === 5. 解压项目源码和 vendor 依赖 ===  
echo "[5/6] Extracting project source and vendor dependencies..."  
mkdir -p sgl-model-gateway  
tar -xzf "$SCRIPT_DIR/sgl-model-gateway-src.tar.gz" -C sgl-model-gateway  
tar -xzf "$SCRIPT_DIR/cargo-vendor.tar.gz"          -C sgl-model-gateway  
  
# === 6. 验证环境 ===  
echo "[6/6] Verifying environment..."  
echo ""  
echo "  rustc  : $(rustc  --version 2>/dev/null || echo 'NOT FOUND')"  
echo "  cargo  : $(cargo  --version 2>/dev/null || echo 'NOT FOUND')"  
echo "  protoc : $(protoc --version 2>/dev/null || echo 'NOT FOUND')"  
echo "  gcc    : $(gcc    --version 2>/dev/null | head -1 || echo 'NOT FOUND')"  
echo ""  
echo "Setup complete!"  
echo ""  
echo "Next steps:"  
echo "  source ~/.bashrc"  
echo "  cd sgl-model-gateway"  
echo "  cargo build --offline"  
echo "  cargo run --offline --bin smg -- [args]"  
echo "  cargo test --offline"  
SETUP_SCRIPT  
  
chmod +x "$SETUP"  
echo "Offline dev bundle created at: $BUNDLE_DIR"
