#!/usr/bin/env bash
set -euo pipefail

log(){ printf '[%s] %s\n' "$(date +'%Y-%m-%d %H:%M:%S')" "$*"; }

# ==== 基本パス（entrypoint から継承される想定）====
COMFY_ROOT="${COMFY_ROOT:-/workspace/ComfyUI}"

# ==== RunPod Raw Editor で設定する環境変数 ====
# VAE & encoders / vision
WAN_VAE22_URL="${WAN_VAE22_URL:-}"   # 例）https://.../Wan_2.2_VAE.safetensors
WAN_VAE21_URL="${WAN_VAE21_URL:-}"   # 例）https://.../Wan_2.1_VAE.safetensors
WAN_CLIPV_URL="${WAN_CLIPV_URL:-}"   # 例）https://.../clip_vision_vit_h.safetensors
WAN_TXTENC_URL="${WAN_TXTENC_URL:-}" # 例）https://.../umt5_xxl_fp8_e4m3fn_scaled.safetensors

# Diffusion (HIGH / LOW)
WAN_HIGH_URL="${WAN_HIGH_URL:-}"     # 例）https://.../wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors
WAN_LOW_URL="${WAN_LOW_URL:-}"       # 例）https://.../wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors

# LoRA（デフォルトはComfy-Orgの公式リパッケージURL。Raw Editorで上書き可）
WAN_LORA_LOW_URL="${WAN_LORA_LOW_URL:-https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors}"
WAN_LORA_HIGH_URL="${WAN_LORA_HIGH_URL:-https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors}"

# HF gated用（必要に応じて）
HF_TOKEN="${HF_TOKEN:-}"

# ==== DLユーティリティ（aria2c -> curl フォールバック、?download= の正規化対応）====
dl_into(){
  local url="${1:-}"; local dest="${2:-}"; local fname="${3:-}"
  [ -z "$url" ]  && return 0
  [ -z "$dest" ] && return 0
  if [ -z "$fname" ]; then
    fname="$(basename "${url%%\?*}")"
  fi
  mkdir -p "$dest"
  log "DL -> ${dest}/${fname}  (${url})"

  if ! aria2c -x16 -s16 --min-split-size=1M --continue=true \
        --auto-file-renaming=false --allow-overwrite=true \
        ${HF_TOKEN:+--header="Authorization: Bearer ${HF_TOKEN}"} \
        -o "$fname" -d "$dest" "$url"; then
    curl -fL --retry 5 --retry-delay 2 \
      ${HF_TOKEN:+-H "Authorization: Bearer ${HF_TOKEN}"} \
      -o "${dest}/${fname}" "$url"
  fi

  # ?download=true 等の末尾クエリを除去した正規名に整える
  if [[ "$fname" == *\?* ]]; then
    local clean="${fname%%\?*}"
    mv -f "${dest}/${fname}" "${dest}/${clean}" || true
    fname="$clean"
  fi

  if [ -f "${dest}/${fname}" ]; then
    printf '     -> %s (%s)\n' "$fname" "$(du -h "${dest}/${fname}" | cut -f1)"
  else
    echo "     !! not found: ${dest}/${fname}"
  fi
}

# ==== 保存先ディレクトリの用意 ====
mkdir -p \
  "${COMFY_ROOT}/models/vae" \
  "${COMFY_ROOT}/models/clip_vision" \
  "${COMFY_ROOT}/models/text_encoders" \
  "${COMFY_ROOT}/models/diffusion_models" \
  "${COMFY_ROOT}/models/loras"

# ==== 初期DLモデル（ご指定どおりに変更）====
# VAE 2種（2.2 / 2.1）
dl_into "$WAN_VAE22_URL" "${COMFY_ROOT}/models/vae" "Wan_2.2_VAE.safetensors"
dl_into "$WAN_VAE21_URL" "${COMFY_ROOT}/models/vae" "Wan_2.1_VAE.safetensors"

# CLIP vision / text encoder
dl_into "$WAN_CLIPV_URL"  "${COMFY_ROOT}/models/clip_vision"   "clip_vision_vit_h.safetensors"
dl_into "$WAN_TXTENC_URL" "${COMFY_ROOT}/models/text_encoders" "umt5_xxl_fp8_e4m3fn_scaled.safetensors"

# Diffusion（HIGH / LOW）
dl_into "$WAN_HIGH_URL" "${COMFY_ROOT}/models/diffusion_models" "wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors"
dl_into "$WAN_LOW_URL"  "${COMFY_ROOT}/models/diffusion_models" "wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors"

# ==== LoRA（Lightx2v 4steps：low/high）====
dl_into "$WAN_LORA_LOW_URL"  "${COMFY_ROOT}/models/loras" "wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors"
dl_into "$WAN_LORA_HIGH_URL" "${COMFY_ROOT}/models/loras" "wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors"
