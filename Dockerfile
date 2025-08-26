# 変更点：-runtime → -devel（nvcc を使うため）
FROM pytorch/pytorch:2.3.1-cuda12.1-cudnn8-devel

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_ROOT_USER_ACTION=ignore \
    PYTHONUNBUFFERED=1 \
    WORKSPACE=/workspace \
    COMFY_PORT=8188 \
    JUPYTER_PORT=8888 \
    TORCH_CUDA_ARCH_LIST="8.9" \
    # オプション導入スイッチ（既定OFF）
    INSTALL_TRITON=0 \
    INSTALL_SAGE=0

# 必須ツール＋ビルド系（Sage/FlashAttn等のビルドに必要）
RUN apt-get update && apt-get install -y --no-install-recommends \
      tini curl ca-certificates git ffmpeg aria2 \
      build-essential python3-dev ninja-build pkg-config cmake \
    && rm -rf /var/lib/apt/lists/*

# JupyterLab
RUN python -m pip install --upgrade pip && \
    python -m pip install --no-cache-dir jupyterlab

# ここで Triton/FlashAttention を“任意導入”できるようにする（既定OFF）
# ピン止めはせず pip の解決に任せる（Torch 2.3.1/CUDA12.1で互換パッケージを取得）
# ※ 実導入は entrypoint.sh 側のスイッチでも可能だが、ビルド時間短縮のため Dockerfile 側でも可
# （今回は entrypoint 側で条件導入する設計に寄せるため、ここでは入れない）

# ディレクトリとログ領域
RUN mkdir -p /opt/bootstrap /usr/local/bin /workspace /runpod-volume /workspace/logs

# エントリポイント関連スクリプト配置
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY setup_models.sh /opt/bootstrap/setup_models.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /opt/bootstrap/setup_models.sh

# ポート公開（ComfyUI / Jupyter）
EXPOSE 8188 8888

ENTRYPOINT ["/usr/bin/tini","-s","--"]
CMD ["/usr/local/bin/entrypoint.sh"]
