#!/usr/bin/env bash
set -euo pipefail
log(){ printf '[%s] %s\n' "$(date +'%H:%M:%S')" "$*"; }

COMFY_ROOT="${COMFY_ROOT:-/workspace/ComfyUI}"

WAN_I2V_URL="${WAN_I2V_URL:-}"
WAN_T2V_URL="${WAN_T2V_URL:-}"
WAN_VAE_URL="${WAN_VAE_URL:-}"
WAN_CLIPV_URL="${WAN_CLIPV_URL:-}"
WAN_TXTENC_URL="${WAN_TXTENC_URL:-}"

# 任意（必要なら環境変数で渡す）
WAN_HIGH_URL="${WAN_HIGH_URL:-}"
WAN_LOW_URL="${WAN_LOW_URL:-}"

dl_into(){ 
  local url="${1:-}"; local dest="${2:-}"; local fname="${3:-}"
  [ -z "$url" ] && return 0
  [ -z "$dest" ] && return 0
  [ -z "$fname" ] && fname="$(basename "${url%%\?*}")"
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
  if [[ "$fname" == *\?* ]]; then
    local clean="${fname%%\?*}"
    mv -f "${dest}/${fname}" "${dest}/${clean}" || true
  fi
  [ -f "${dest}/${fname%%\?*}" ] && printf '     -> %s (%s)\n' \
     "${fname%%\?*}" "$(du -h "${dest}/${fname%%\?*}" | cut -f1)"
}

# ===== WAN 2.2 AIO =====
dl_into "$WAN_VAE_URL"    "${COMFY_ROOT}/models/vae"            "Wan2.1_VAE.safetensors"
dl_into "$WAN_VAE_URL"    "${COMFY_ROOT}/models/vae"            "Wan2.2_VAE.safetensors"
dl_into "$WAN_CLIPV_URL"  "${COMFY_ROOT}/models/clip_vision"    "clip_vision_vit_h.safetensors"
dl_into "$WAN_TXTENC_URL" "${COMFY_ROOT}/models/text_encoders"  "umt5_xxl_fp8_e4m3fn_scaled.safetensors"

# ===== WAN 2.2 FP8 HIGH/LOW =====
dl_into "$WAN_HIGH_URL"   "${COMFY_ROOT}/models/diffusion_models" "wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors"
dl_into "$WAN_LOW_URL"    "${COMFY_ROOT}/models/diffusion_models" "wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors"
