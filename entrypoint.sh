#!/usr/bin/env bash
set -Eeuo pipefail
export PIP_ROOT_USER_ACTION=ignore

log(){ printf '[%s] %s\n' "$(date +'%H:%M:%S')" "$*"; }
warn(){ printf '[%s] [WARN] %s\n' "$(date +'%H:%M:%S')" "$*" >&2; }
trap 'code=$?; echo "[ERROR] exit $code at line $LINENO"; exit $code' ERR
sanitize(){ local s="${1:-}"; s="${s//\"/}"; echo -n "$s"; }

# --- WORKSPACE autodetect ---
if [ -z "${WORKSPACE:-}" ]; then
  if [ -d "/runpod-volume" ]; then
    WORKSPACE="/runpod-volume"
  else
    WORKSPACE="/workspace"
  fi
fi
log "WORKSPACE set to: ${WORKSPACE}"
export COMFY_ROOT="${WORKSPACE}/ComfyUI"

# === ComfyUI 初回セットアップ ===
if [ ! -d "${COMFY_ROOT}" ]; then
  log "Cloning ComfyUI..."
  git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git "${COMFY_ROOT}"
fi

# === 依存関係（本体） ===
log "Installing ComfyUI requirements..."
python3 -m pip install --no-cache-dir -r "${COMFY_ROOT}/requirements.txt"
python3 -m pip install --no-cache-dir --upgrade torch torchvision torchaudio || true

# === 追加の軽量依存（稀に必要） ===
python3 -m pip install --no-cache-dir kornia_rs pydantic_core mako typing_inspection annotated-types || true

# === オプション: Triton / FlashAttention / SageAttention ===
INSTALL_TRITON="${INSTALL_TRITON:-0}"
INSTALL_SAGE="${INSTALL_SAGE:-0}"

if [ "${INSTALL_TRITON}" = "1" ]; then
  log "Installing Triton (and FlashAttention) for faster attention kernels..."
  # Triton: PyTorch 2.3 系に整合するバージョンを pip に解決させる
  python3 -m pip install --no-cache-dir triton || warn "Triton install failed"
  # FlashAttention（任意。ComfyUIの一部ノードで高速化の恩恵。失敗は無害化）
  python3 -m pip install --no-cache-dir "flash-attn>=2" || warn "flash-attn install failed"
fi

if [ "${INSTALL_SAGE}" = "1" ]; then
  log "Installing SageAttention (build with CUDA arch: ${TORCH_CUDA_ARCH_LIST:-unknown})..."
  # develイメージ＋nvcc前提。失敗してもUIは起動継続（warn化）
  TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-8.9}" \
    python3 -m pip install --no-cache-dir git+https://github.com/thu-ml/SageAttention.git \
    || warn "SageAttention install failed"
fi

COMFY_PORT="${COMFY_PORT:-8188}"
JUPYTER_PORT="${JUPYTER_PORT:-8888}"

ALWAYS_DL="${ALWAYS_DL:-1}"
CLEAR_MODELS_BEFORE_DL="${CLEAR_MODELS_BEFORE_DL:-0}"
INSTALL_MANAGER="${INSTALL_MANAGER:-1}"
INSTALL_VHS="${INSTALL_VHS:-1}"
JUPYTER_TOKEN="$(sanitize "${JUPYTER_TOKEN:-}")"

mkdir -p "${WORKSPACE}/logs"

# === ComfyUI-Manager ===
if [ "${INSTALL_MANAGER}" = "1" ]; then
  MANAGER_DIR="${COMFY_ROOT}/custom_nodes/ComfyUI-Manager"
  if [ ! -d "${MANAGER_DIR}" ]; then
    log "Installing ComfyUI-Manager"
    git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Manager.git "${MANAGER_DIR}" || warn "Manager clone failed"
  fi
  python3 -m pip install --no-cache-dir -r "${MANAGER_DIR}/requirements.txt" || warn "Manager deps failed"
fi

# === VHS ===
if [ "${INSTALL_VHS}" = "1" ]; then
  VHS_DIR="${COMFY_ROOT}/custom_nodes/ComfyUI-VideoHelperSuite"
  if [ ! -d "${VHS_DIR}" ]; then
    log "Installing ComfyUI-VideoHelperSuite"
    git clone --depth=1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git "${VHS_DIR}" || warn "VHS clone failed"
  fi
  python3 -m pip install --no-cache-dir -r "${VHS_DIR}/requirements.txt" || warn "VHS deps failed"
fi

# === モデルDL ===
if [ "${ALWAYS_DL}" = "1" ]; then
  if [ "${CLEAR_MODELS_BEFORE_DL}" = "1" ]; then
    log "wipe models/"
    rm -rf "${COMFY_ROOT}/models"/* || true
  fi
  mkdir -p "${COMFY_ROOT}"/models/{checkpoints,diffusion_models,text_encoders,vae,clip_vision,loras}
  log "setup_models.sh (start)"
  bash -x /opt/bootstrap/setup_models.sh | tee "${WORKSPACE}/logs/setup_models.log" || true
  echo "[DONE] $(date)" >> "${WORKSPACE}/logs/setup_models.last.log" || true
  log "setup_models.sh (done)"
fi

# === Jupyter ===
declare -a JUPY_ARGS
if [ -n "${JUPYTER_TOKEN}" ]; then JUPY_ARGS+=(--ServerApp.token="${JUPYTER_TOKEN}"); else JUPY_ARGS+=(--ServerApp.token=); fi
log "Starting Jupyter :${JUPYTER_PORT}"
nohup jupyter lab \
  --ip=0.0.0.0 --port="${JUPYTER_PORT}" --no-browser --allow-root \
  --ServerApp.root_dir="${WORKSPACE}" --ServerApp.allow_origin="*" \
  "${JUPY_ARGS[@]}" > "${WORKSPACE}/logs/jupyter.log" 2>&1 &

# === ComfyUI ===
log "Starting ComfyUI :${COMFY_PORT} from ${COMFY_ROOT}"
cd "${COMFY_ROOT}"
nohup python3 main.py --listen 0.0.0.0 --port "${COMFY_PORT}" \
  > "${WORKSPACE}/logs/comfyui.log" 2>&1 &

# 軽いヘルス待ち
for i in {1..60}; do
  sleep 2
  if curl -fsS "http://127.0.0.1:${COMFY_PORT}" >/dev/null 2>&1; then
    break
  fi
done

log "Jupyter:  http://<pod>:${JUPYTER_PORT}/$( [ -n "${JUPYTER_TOKEN}" ] && echo '?token='${JUPYTER_TOKEN} )"
log "ComfyUI:  http://<pod>:${COMFY_PORT}/"

exec tail -F "${WORKSPACE}/logs/comfyui.log" "${WORKSPACE}/logs/jupyter.log"
