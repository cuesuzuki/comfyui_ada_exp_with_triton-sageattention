#!/usr/bin/env bash
set -Eeuo pipefail
export PIP_ROOT_USER_ACTION=ignore

log(){ printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"; }
warn(){ printf '[%s] [WARN] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*" >&2; }
trap 'code=$?; echo "[ERROR] exit $code at line $LINENO"; exit $code' ERR
sanitize(){ local s="${1:-}"; s="${s//\"/}"; echo -n "$s"; }

# ===== Workspace / Pip cache / venv =====
# WORKSPACE は Dockerfile の ENV または RunPod の Raw Editor で与えられる想定
if [ -z "${WORKSPACE:-}" ]; then
  if [ -d "/runpod-volume" ]; then
    WORKSPACE="/runpod-volume"
  else
    WORKSPACE="/workspace"
  fi
fi
export WORKSPACE
log "WORKSPACE=${WORKSPACE}"

# pip キャッシュを Volume に固定（初期化）
export PIP_CACHE_DIR="${PIP_CACHE_DIR:-${WORKSPACE}/.cache/pip}"
mkdir -p "${PIP_CACHE_DIR}"

# Volume 上の venv を永続利用（なければ作成）
VENV_DIR="${WORKSPACE}/venv"
if [ ! -d "${VENV_DIR}" ]; then
  log "Creating Python venv at ${VENV_DIR}"
  python3 -m venv "${VENV_DIR}"
fi
# 有効化
# shellcheck disable=SC1090
. "${VENV_DIR}/bin/activate"
python -m pip install --upgrade pip wheel setuptools

# ===== 基本設定 =====
export COMFY_ROOT="${WORKSPACE}/ComfyUI"
COMFY_PORT="${COMFY_PORT:-8188}"
JUPYTER_PORT="${JUPYTER_PORT:-8888}"
JUPYTER_TOKEN="$(sanitize "${JUPYTER_TOKEN:-}")"

ALWAYS_DL="${ALWAYS_DL:-1}"
CLEAR_MODELS_BEFORE_DL="${CLEAR_MODELS_BEFORE_DL:-0}"
INSTALL_MANAGER="${INSTALL_MANAGER:-1}"
INSTALL_VHS="${INSTALL_VHS:-1}"
INSTALL_TRITON="${INSTALL_TRITON:-1}"   # 既定ON（Dockerfileで設定済み）
INSTALL_SAGE="${INSTALL_SAGE:-1}"       # 既定ON（Dockerfileで設定済み）

mkdir -p "${WORKSPACE}/logs"

# ===== ComfyUI 取得 =====
if [ ! -d "${COMFY_ROOT}" ]; then
  log "Cloning ComfyUI into ${COMFY_ROOT}"
  git clone --depth 1 https://github.com/comfyanonymous/ComfyUI.git "${COMFY_ROOT}"
else
  log "ComfyUI already present at ${COMFY_ROOT}"
fi

# ===== 依存導入（本体） =====
log "Installing ComfyUI requirements..."
python -m pip install --no-cache-dir -r "${COMFY_ROOT}/requirements.txt"
# torch 系は環境に合わせて上書き（失敗は致命にしない）
python -m pip install --no-cache-dir --upgrade torch torchvision torchaudio || warn "torch family upgrade failed"

# 稀に必要になる軽量依存
python -m pip install --no-cache-dir kornia_rs pydantic_core mako typing_inspection annotated-types || true

# ===== オプション導入：Triton / FlashAttention / SageAttention =====
if [ "${INSTALL_TRITON}" = "1" ]; then
  log "Installing Triton / FlashAttention (optional accelerators)"
  python -m pip install --no-cache-dir triton || warn "triton install failed"
  python -m pip install --no-cache-dir "flash-attn>=2" || warn "flash-attn install failed"
fi

if [ "${INSTALL_SAGE}" = "1" ]; then
  log "Installing SageAttention (CUDA arch: ${TORCH_CUDA_ARCH_LIST:-unknown})"
  TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-8.9}" \
    python -m pip install --no-cache-dir git+https://github.com/thu-ml/SageAttention.git \
    || warn "SageAttention install failed"
fi

# ===== ComfyUI-Manager / VHS =====
if [ "${INSTALL_MANAGER}" = "1" ]; then
  MANAGER_DIR="${COMFY_ROOT}/custom_nodes/ComfyUI-Manager"
  if [ ! -d "${MANAGER_DIR}" ]; then
    log "Installing ComfyUI-Manager"
    git clone --depth=1 https://github.com/ltdrdata/ComfyUI-Manager.git "${MANAGER_DIR}" || warn "Manager clone failed"
  fi
  python -m pip install --no-cache-dir -r "${MANAGER_DIR}/requirements.txt" || warn "Manager requirements failed"
fi

if [ "${INSTALL_VHS}" = "1" ]; then
  VHS_DIR="${COMFY_ROOT}/custom_nodes/ComfyUI-VideoHelperSuite"
  if [ ! -d "${VHS_DIR}" ]; then
    log "Installing ComfyUI-VideoHelperSuite"
    git clone --depth=1 https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite.git "${VHS_DIR}" || warn "VHS clone failed"
  fi
  python -m pip install --no-cache-dir -r "${VHS_DIR}/requirements.txt" || warn "VHS requirements failed"
fi

# ===== モデルダウンロード =====
if [ "${ALWAYS_DL}" = "1" ]; then
  if [ "${CLEAR_MODELS_BEFORE_DL}" = "1" ]; then
    log "Clearing ${COMFY_ROOT}/models/*"
    rm -rf "${COMFY_ROOT}/models"/* || true
  fi
  mkdir -p "${COMFY_ROOT}"/models/{checkpoints,diffusion_models,text_encoders,vae,clip_vision,loras}
  log "Running setup_models.sh (download models)"
  bash -x /opt/bootstrap/setup_models.sh | tee "${WORKSPACE}/logs/setup_models.log" || warn "setup_models.sh returned non-zero"
  echo "[DONE] $(date)" >> "${WORKSPACE}/logs/setup_models.last.log" || true
fi

# ===== ユーザーデータの作成（保存エラー502対策） =====
mkdir -p "${COMFY_ROOT}/user/workflows"

# ===== Jupyter 起動 =====
declare -a JUPY_ARGS
if [ -n "${JUPYTER_TOKEN}" ]; then
  JUPY_ARGS+=(--ServerApp.token="${JUPYTER_TOKEN}")
else
  JUPY_ARGS+=(--ServerApp.token=)
fi

log "Starting Jupyter :${JUPYTER_PORT}"
nohup jupyter lab \
  --ip=0.0.0.0 --port="${JUPYTER_PORT}" --no-browser --allow-root \
  --ServerApp.root_dir="${WORKSPACE}" --ServerApp.allow_origin="*" \
  "${JUPY_ARGS[@]}" \
  > "${WORKSPACE}/logs/jupyter.log" 2>&1 &

# ===== ComfyUI 起動（SageAttention を全体適用） =====
log "Starting ComfyUI :${COMFY_PORT} (SageAttention enabled globally)"
cd "${COMFY_ROOT}"
nohup python3 main.py \
  --listen 0.0.0.0 --port "${COMFY_PORT}" \
  --dont-print-server \
  --use-sage-attention \
  --user-directory "${COMFY_ROOT}/user" \
  > "${WORKSPACE}/logs/comfyui.log" 2>&1 &

# ===== ヘルス待機 =====
for i in {1..90}; do
  sleep 2
  if curl -fsS "http://127.0.0.1:${COMFY_PORT}" >/dev/null 2>&1; then
    log "ComfyUI is up."
    break
  fi
  if (( i % 10 == 0 )); then
    log "Waiting ComfyUI... (${i}/90)"
  fi
done

log "Jupyter URL:  http://<pod>:${JUPYTER_PORT}/$( [ -n "${JUPYTER_TOKEN}" ] && echo '?token='${JUPYTER_TOKEN} )"
log "ComfyUI URL:  http://<pod>:${COMFY_PORT}/"

# ===== フォアグラウンドでログ監視 =====
exec tail -F "${WORKSPACE}/logs/comfyui.log" "${WORKSPACE}/logs/jupyter.log"
