# Umi-OCR Docker
# 编译环境
FROM debian:11 AS build

SHELL ["/bin/bash", "-c"]

# 检查AVX指令集
RUN if [[ -z $(lscpu | grep avx) ]]; then \
    echo "错误：当前CPU不支持AVX指令集"; \
    exit 1; \
    fi

# 安装编译环境及依赖库
RUN apt update -y && \
    apt install -y \
    wget tar zip unzip git gcc g++ cmake make pkg-config \
    libopenblas-dev openssl libssl-dev libcurl4-openssl-dev

WORKDIR /src/

# 下载PaddleOCR-json源码
RUN git clone --recursive https://github.com/hiroi-sora/PaddleOCR-json

# 下载依赖库 - 添加下载重试
RUN apt-get update && apt-get install -y ca-certificates && update-ca-certificates && \
    for i in {1..3}; do \
        wget --tries=3 --waitretry=10 --retry-connrefused https://paddle-inference-lib.bj.bcebos.com/3.0.0/cxx_c/Linux/CPU/gcc8.2_avx_mkl/paddle_inference.tgz && \
        break; \
    done && \
    tar -xf paddle_inference.tgz && \
    for i in {1..3}; do \
        wget --tries=3 --waitretry=10 --retry-connrefused https://github.com/hiroi-sora/PaddleOCR-json/releases/download/v1.4.0-beta.2/opencv-release_debian_x86-64.zip && \
        break; \
    done && \
    unzip -x opencv-release_debian_x86-64.zip && \
    mkdir -p /src/PaddleOCR-json/cpp/.source && \
    mv /src/paddle_inference /src/PaddleOCR-json/cpp/.source/ && \
    mv /src/opencv-release /src/PaddleOCR-json/cpp/.source/ && \
    rm paddle_inference.tgz opencv-release_debian_x86-64.zip

ENV PADDLE_LIB="/src/PaddleOCR-json/cpp/.source/paddle_inference/" \
    OPENCV_DIR="/src/PaddleOCR-json/cpp/.source/opencv-release/"

# 构建工程 + 编译（添加并行编译和详细日志）
RUN cd /src/PaddleOCR-json/cpp/ && \
    mkdir -p build && \
    cmake -S . -B build \
        -DPADDLE_LIB=$PADDLE_LIB \
        -DOPENCV_DIR=$OPENCV_DIR \
        -DCMAKE_BUILD_TYPE=Release \
        -DENABLE_CLIPBOARD=OFF \
        -DENABLE_REMOTE_EXIT=ON \
        -DENABLE_JSON_IMAGE_PATH=OFF && \
    cmake --build build --config=Release --parallel $(nproc) --verbose && \
    cmake --install build --prefix build/install --strip

# 清理不需要的编译文件减小镜像大小
RUN rm -rf /src/PaddleOCR-json/cpp/build/CMakeFiles

# 部署环境
FROM debian:11-slim

LABEL app="Umi-OCR-Paddle" maintainer="hiroi-sora" version="2.1.5" \
    description="OCR software, free and offline." license="MIT" \
    org.opencontainers.image.source="https://github.com/hiroi-sora/Umi-OCR_runtime_linux"

# 安装所需工具和QT依赖库 - 使用多阶段安装减少层数
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget xz-utils ttf-wqy-microhei xvfb libgomp1 \
    libglib2.0-0 libgssapi-krb5-2 libgl1-mesa-glx libfontconfig1 \
    libfreetype6 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 \
    libxcb-render-util0 libxcb-render0 libxcb-shape0 libxcb-xkb1 \
    libxcb-xinerama0 libxkbcommon-x11-0 libxkbcommon0 libdbus-1-3 \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 工作目录
WORKDIR /app

# 下载发行包 - 添加证书更新
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && update-ca-certificates && \
    for i in {1..3}; do \
        wget --tries=3 --waitretry=10 --retry-connrefused https://github.com/hiroi-sora/Umi-OCR/releases/download/v2.1.5/Umi-OCR_Linux_Paddle_2.1.5.tar.xz && \
        break; \
    done && \
    tar -v -xf Umi-OCR_Linux_Paddle_2.1.5.tar.xz && \
    mv Umi-OCR_Linux_Paddle_2.1.5/* . && \
    rmdir Umi-OCR_Linux_Paddle_2.1.5 && \
    rm Umi-OCR_Linux_Paddle_2.1.5.tar.xz

# 替换PaddleOCR-json引擎 - 修复目录移动问题
RUN apt-get update && apt-get install -y --no-install-recommends wget unzip rsync ca-certificates && \
    update-ca-certificates && \
    for i in {1..3}; do \
        wget --tries=3 --waitretry=10 --retry-connrefused https://github.com/hiroi-sora/PaddleOCR-json/releases/download/v1.4.1-dev/models_v1.4.1.zip && \
        break; \
    done && \
    unzip -x models_v1.4.1.zip -d ./temp_models && \
    # 改为使用rsync确保目标目录被正确覆盖
    rsync -a --delete ./temp_models/models/ UmiOCR-data/plugins/linux_x64_PaddleOCR-json_v141/models/ && \
    rm -rf ./temp_models models_v1.4.1.zip && \
    apt-get purge -y wget unzip rsync && apt-get autoremove -y

# 从构建阶段复制编译好的二进制
COPY --from=build /src/PaddleOCR-json/cpp/build/install/ /app/UmiOCR-data/plugins/linux_x64_PaddleOCR-json_v141/

# 写入Umi-OCR预配置项
RUN printf "[Global]\nserver.host=0.0.0.0\nui.fontFamily=WenQuanYi Micro Hei\nui.dataFontFamily=WenQuanYi Micro Hei\n" \
    > ./UmiOCR-data/.settings

# 运行指令
ENTRYPOINT ["/app/umi-ocr.sh"]
