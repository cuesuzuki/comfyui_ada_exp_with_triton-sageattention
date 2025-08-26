# CUDA 12.1 / cuDNN8 / nvcc を含む devel イメージ（SageAttention等のビルド用）
FROM pytorch/pytorch:2.3.1-cuda12.1-cudnn8-devel

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_ROOT_USER_ACTION=ignore \
    PYTHONUNBUFFERED=1 \
    WORKSPACE=/workspace \
    COMFY_PORT=8188 \
    JUPYTER_PORT=8888 \
    TORCH_CUDA_ARCH_LIST="8.9" \
    # pipキャッシュと将来のvenvをVolume配下に置くため
    PIP_CACHE_DIR=/workspace/.cache/pip \
    # 起動時に entrypoint.sh が参照（既定ON）
    INSTALL_TRITON=1 \
    INSTALL_SAGE=1 \
    # モデルDL関連（entrypoint/setup_models.sh で参照）
    ALWAYS_DL=1 \
    CLEAR_MODELS_BEFORE_DL=0 \
    INSTALL_MANAGER=1 \
    INSTALL_VHS=1

# 必須ツール＋ビルド系（Sage/FlashAttn等のビルドに必要）
RUN apt-get update && apt-get install -y --no-install-recommends \
      tini curl ca-certificates git ffmpeg aria2 \
      build-essential python3-dev python3-venv \
      ninja-build pkg-config cmake \
    && rm -rf /var/lib/apt/lists/*

# JupyterLab
RUN python -m pip install --upgrade pip && \
    python -m pip install --no-cache-dir jupyterlab

# 作業ディレクトリとログ領域
RUN mkdir -p /opt/bootstrap /usr/local/bin ${WORKSPACE} /runpod-volume ${WORKSPACE}/logs ${PIP_CACHE_DIR}

# エントリポイント用スクリプト（リポジトリ側の最新版を同階層に置く想定）
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY setup_models.sh /opt/bootstrap/setup_models.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /opt/bootstrap/setup_models.sh

# ポート公開（ComfyUI / Jupyter）
EXPOSE 8188 8888

# Tini を subreaper で起動（ゾンビ回収の警告抑制）
ENTRYPOINT ["/usr/bin/tini","-s","--"]
CMD ["/usr/local/bin/entrypoint.sh"]
