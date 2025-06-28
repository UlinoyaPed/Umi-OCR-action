# Umi-OCR Docker
# https://github.com/hiroi-sora/Umi-OCR
# https://github.com/hiroi-sora/Umi-OCR_runtime_linux

# 先用一个docker容器本地编译PaddleOCR-json引擎，之后再安装到Umi-OCR容器里

# 编译环境
FROM debian:11 AS build

SHELL ["/bin/bash", "-c"]

# 检查AVX指令集，如果不支持就退出
RUN if [[ -z $(lscpu | grep avx) ]] ; \
    then echo "Current CPU doesn't support AVX." ; \
    exit -1 ; \
    fi

# 安装编译环境
RUN \
    apt update -y && \
    apt install -y wget tar zip unzip git gcc g++ cmake make pkg-config

WORKDIR /src/

# 下载PaddleOCR-json源码
RUN git clone --recursive https://github.com/hiroi-sora/PaddleOCR-json

# 下载依赖库
RUN wget https://paddle-inference-lib.bj.bcebos.com/3.0.0/cxx_c/Linux/CPU/gcc8.2_avx_mkl/paddle_inference.tgz && \
    tar -xf paddle_inference.tgz && \
    wget https://github.com/hiroi-sora/PaddleOCR-json/releases/download/v1.4.0-beta.2/opencv-release_debian_x86-64.zip && \
    unzip -x opencv-release_debian_x86-64.zip && \
    mkdir -p /src/PaddleOCR-json/cpp/.source && \
    mv /src/paddle_inference /src/PaddleOCR-json/cpp/.source && \
    mv /src/opencv-release /src/PaddleOCR-json/cpp/.source && \
    rm paddle_inference.tgz && rm opencv-release_debian_x86-64.zip

ENV PADDLE_LIB="/src/PaddleOCR-json/cpp/.source/paddle_inference/" \
    OPENCV_DIR="/src/PaddleOCR-json/cpp/.source/opencv-release/"

# 构建工程 + 编译
RUN cd /src/PaddleOCR-json/cpp/ && \
    mkdir -p build && \
        cmake -S . -B build \
        -DPADDLE_LIB=$PADDLE_LIB \
        -DOPENCV_DIR=$OPENCV_DIR \
        -DCMAKE_BUILD_TYPE=Release \
        -DENABLE_CLIPBOARD=OFF \
        -DENABLE_REMOTE_EXIT=ON \
        -DENABLE_JSON_IMAGE_PATH=OFF && \
    cmake --build build --config=Release && \
    cmake --install build --prefix build/install --strip



# 部署环境
FROM debian:11-slim

LABEL app="Umi-OCR-Paddle"
LABEL maintainer="hiroi-sora"
LABEL version="2.1.5"
LABEL description="OCR software, free and offline."
LABEL license="MIT"
LABEL org.opencontainers.image.source="https://github.com/hiroi-sora/Umi-OCR_runtime_linux"

# 安装所需工具和QT依赖库
RUN apt-get update && apt-get install -y \
    wget xz-utils ttf-wqy-microhei xvfb libgomp1 \
    libglib2.0-0 libgssapi-krb5-2 libgl1-mesa-glx libfontconfig1 \
    libfreetype6 libxcb-icccm4 libxcb-image0 libxcb-keysyms1 \
    libxcb-render-util0 libxcb-render0 libxcb-shape0 libxcb-xkb1 \
    libxcb-xinerama0 libxkbcommon-x11-0 libxkbcommon0 libdbus-1-3 \
    && rm -rf /var/lib/apt/lists/*

# 工作目录
WORKDIR /app

# 可选1：将主机目录中的发行包，复制到容器内
# COPY Umi-OCR_Linux_Paddle_2.1.5.tar.xz .
# 可选2：在线下载发行包
RUN wget https://github.com/hiroi-sora/Umi-OCR/releases/download/v2.1.5/Umi-OCR_Linux_Paddle_2.1.5.tar.xz

# 解压压缩包，移动文件，删除多余的目录和压缩包
RUN tar -v -xf Umi-OCR_Linux_Paddle_2.1.5.tar.xz && \
    mv Umi-OCR_Linux_Paddle_2.1.5/* . && \
    rmdir Umi-OCR_Linux_Paddle_2.1.5 && \
    rm Umi-OCR_Linux_Paddle_2.1.5.tar.xz

# 下载最新的启动脚本
# RUN wget -O umi-ocr.sh https://raw.githubusercontent.com/hiroi-sora/Umi-OCR_runtime_linux/main/umi-ocr.sh

# 替换PaddleOCR-json引擎
RUN rm -rf UmiOCR-data/plugins/linux_x64_PaddleOCR-json_v141/models/ && \
    rm -rf UmiOCR-data/plugins/linux_x64_PaddleOCR-json_v141/lib/ && \
    rm -rf UmiOCR-data/plugins/linux_x64_PaddleOCR-json_v141/bin/ && \
    wget https://github.com/hiroi-sora/PaddleOCR-json/releases/download/v1.4.1-dev/models_v1.4.1.zip && \
    unzip -x models_v1.4.1.zip && mv ./models/ UmiOCR-data/plugins/linux_x64_PaddleOCR-json_v141/
COPY --from=build /src/PaddleOCR-json/cpp/build/install/ /app/UmiOCR-data/plugins/linux_x64_PaddleOCR-json_v141/

# 写入 Umi-OCR 预配置项：
#    允许外部HTTP请求
#    切换到支持中文的字体
RUN printf "\
[Global]\n\
server.host=0.0.0.0\n\
ui.fontFamily=WenQuanYi Micro Hei\n\
ui.dataFontFamily=WenQuanYi Micro Hei\n\
" > ./UmiOCR-data/.settings


# 运行指令
ENTRYPOINT ["/app/umi-ocr.sh"]
