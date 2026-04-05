# syntax=docker/dockerfile:1
# Base Camoufox build image — full Firefox compilation from source.
#
# This image is built rarely (new Firefox/Camoufox releases) and pushed
# to a registry. It contains the compiled objects, source tree, and build
# tools needed for fast incremental rebuilds in Dockerfile.camoufox.
#
# Built by: .github/workflows/build-camoufox-base.yml
# Used by:  Dockerfile.camoufox (FROM this image)
#
# Usage:
#   docker build -f Dockerfile.camoufox-base \
#     --build-arg CAMOUFOX_REF=v135.0.1-beta.24 \
#     -t ghcr.io/eh-ops/camoufox-base:135.0.1-beta.24 .

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# ─── System dependencies ─────────────────────────────────────────────────

RUN apt-get update && apt-get install -y --no-install-recommends \
    aria2 build-essential ca-certificates ccache curl git gnupg \
    libasound2-dev libcurl4-openssl-dev libdbus-1-dev libdbus-glib-1-dev \
    libdrm-dev libffi-dev libgbm-dev libgtk-3-dev libpango1.0-dev \
    libpulse-dev libx11-xcb-dev libxcomposite-dev libxdamage-dev \
    libxrandr-dev libxss-dev libxt-dev libxtst-dev lsb-release m4 \
    msitools nasm p7zip-full pkg-config python3 python3-pip python3-venv \
    software-properties-common unzip wget xvfb yasm \
    && rm -rf /var/lib/apt/lists/*

ENV CCACHE_DIR=/root/.ccache
ENV CCACHE_MAXSIZE=20G

# LLVM 18
RUN wget -q https://apt.llvm.org/llvm.sh && chmod +x llvm.sh && \
    ./llvm.sh 18 && \
    apt-get install -y lld-18 clang-18 libclang-18-dev && \
    update-alternatives --install /usr/bin/ld.lld ld.lld /usr/bin/ld.lld-18 100 && \
    rm llvm.sh

# Go (arch-aware download)
RUN GOARCH=$(dpkg --print-architecture | sed 's/aarch64/arm64/') && \
    curl -fsSL "https://go.dev/dl/go1.23.4.linux-${GOARCH}.tar.gz" | tar -C /usr/local -xzf -
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && apt-get install -y nodejs

ENV PATH="/usr/local/go/bin:/root/.cargo/bin:/root/.mozbuild/cbindgen:${PATH}"

# ─── Camoufox source + build ─────────────────────────────────────────────

ARG CAMOUFOX_REF=v135.0.1-beta.24
WORKDIR /build

RUN git clone --depth 1 --branch ${CAMOUFOX_REF} \
    https://github.com/daijro/camoufox.git /build/camoufox

WORKDIR /build/camoufox

RUN make fetch
RUN make setup-minimal

# Bootstrap (Rust, cbindgen, etc.)
RUN cd camoufox-*/ && \
    export MOZBUILD_STATE_PATH=$HOME/.mozbuild && \
    ./mach --no-interactive bootstrap --application-choice=browser || \
    echo "Bootstrap completed with warnings"
RUN which cbindgen 2>/dev/null || cargo install cbindgen

ENV PATH="/root/.mozbuild/nasm:/root/.mozbuild/node/bin:/root/.mozbuild/cbindgen:${PATH}"

# Patch mozconfig: system LLVM, disable bootstrap/wasm, enable ccache
RUN sed -i 's/--enable-bootstrap/--disable-bootstrap/' /build/camoufox/assets/base.mozconfig && \
    echo '' >> /build/camoufox/assets/base.mozconfig && \
    echo '# System LLVM 18 (mobile-harness base build)' >> /build/camoufox/assets/base.mozconfig && \
    echo 'export CC=clang-18' >> /build/camoufox/assets/base.mozconfig && \
    echo 'export CXX=clang++-18' >> /build/camoufox/assets/base.mozconfig && \
    echo 'export AR=llvm-ar-18' >> /build/camoufox/assets/base.mozconfig && \
    echo 'export NM=llvm-nm-18' >> /build/camoufox/assets/base.mozconfig && \
    echo 'export RANLIB=llvm-ranlib-18' >> /build/camoufox/assets/base.mozconfig && \
    echo "ac_add_options --with-libclang-path=$(llvm-config-18 --libdir)" >> /build/camoufox/assets/base.mozconfig && \
    echo 'ac_add_options --without-wasm-sandboxed-libraries' >> /build/camoufox/assets/base.mozconfig && \
    echo '' >> /build/camoufox/assets/base.mozconfig && \
    echo '# Enable ccache for faster rebuilds' >> /build/camoufox/assets/base.mozconfig && \
    echo 'ac_add_options --with-ccache' >> /build/camoufox/assets/base.mozconfig

# Full stock build (~68 min on x86_64, longer on arm64)
# Cache mounts for ccache and mozbuild to speed up rebuilds
RUN --mount=type=cache,target=/root/.ccache \
    --mount=type=cache,target=/root/.mozbuild \
    ARCH=$(uname -m | sed 's/aarch64/arm64/') && \
    mkdir -p dist && \
    python3 ./multibuild.py --target linux --arch ${ARCH}

# Store version info for downstream
RUN echo "${CAMOUFOX_REF}" > /build/CAMOUFOX_VERSION
