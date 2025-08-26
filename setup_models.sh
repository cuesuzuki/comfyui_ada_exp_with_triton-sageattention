#!/usr/bin/env bash
set -euo pipefail

log(){ printf '[%s] %s\n' "$(date +'%H:%M:%S')" "$*"; }
warn(){ printf '[%s] [WARN] %s\n' "$(date +'%H:%M:%S')" "$*" >&2; }

COMFY_ROOT="${COMFY_ROOT:-/workspace/ComfyUI}"

# === Raw Editor で与えるURL群 ===
WAN_VAE22_URL="${WAN_VAE22_URL:-}"   # Wan2.2_VAE.pth
WAN_VAE21_URL="${WAN_VAE21_URL:-}"   # wan_2.1_vae.safetensors
WAN_CLIPV_URL="${WAN_CLIPV_URL:-}"
WAN_TXTENC_URL="${WAN_TXTENC_URL:-}"
WAN_HIGH_URL="${WAN_HIGH_URL:-}"
WAN_LOW_URL="${WAN_LOW_URL:-}"
WAN_LORA_LOW_URL="${WAN_LORA_LOW_URL:-https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors}"
WAN_LORA_HIGH_URL="${WAN_LORA_HIGH_URL:-https://huggingface.co/Comfy-Org/Wan_2.2_ComfyUI_Repackaged/resolve/main/split_files/loras/wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors}"
HF_TOKEN="${HF_TOKEN:-}"

# === DLユーティリティ（失敗しても止めない） ===
dl_into(){
  local url="${1:-}"; local dest="${2:-}"; local fname="${3:-}"
  [ -z "$url" ]  && { warn "skip (empty url)"; return 0; }
  [ -z "$dest" ] && { warn "skip (empty dest)"; return 0; }
  [ -z "$fname" ] && fname="$(basename "${url%%\?*}")"

  mkdir -p "$dest"
  log "DL -> ${dest}/${fname} (${url})"

  local ok=0
  # 1) aria2c
  aria2c -x16 -s16 --min-split-size=1M --continue=true \
         --auto-file-renaming=false --allow-overwrite=true \
         ${HF_TOKEN:+--header="Authorization: Bearer ${HF_TOKEN}"} \
         -o "$fname" -d "$dest" "$url" && ok=1

  # 2) curl fallback
  if [ $ok -eq 0 ]; then
    curl -fL --retry 5 --retry-delay 2 \
         ${HF_TOKEN:+-H "Authorization: Bearer ${HF_TOKEN}"} \
         -o "${dest}/${fname}" "$url" && ok=1 || true
  fi

  # 失敗しても続行
  if [ $ok -eq 0 ]; then
    warn "DL FAILED: $url"
    return 0
  fi

  # ?download= 正規化
  if [[ "$fname" == *\?* ]]; then
    local clean="${fname%%\?*}"
    mv -f "${dest}/${fname}" "${dest}/${clean}" 2>/dev/null || true
    fname="$clean"
  fi

  if [ -f "${dest}/${fname}" ]; then
    printf '     -> %s (%s)\n' "$fname" "$(du -h "${dest}/${fname}" | cut -f1)"
  else
    warn "file not found after DL: ${dest}/${fname}"
  fi
}

# === 保存先用意 ===
mkdir -p \
  "${COMFY_ROOT}/models/vae" \
  "${COMFY_ROOT}/models/clip_vision" \
  "${COMFY_ROOT}/models/text_encoders" \
  "${COMFY_ROOT}/models/diffusion_models" \
  "${COMFY_ROOT}/models/loras"

# === 初期DL ===
# VAE
dl_into "$WAN_VAE22_URL" "${COMFY_ROOT}/models/vae" "Wan2.2_VAE.pth"
dl_into "$WAN_VAE21_URL" "${COMFY_ROOT}/models/vae" "Wan_2.1_VAE.safetensors"

# Encoders
dl_into "$WAN_CLIPV_URL"  "${COMFY_ROOT}/models/clip_vision"   "clip_vision_vit_h.safetensors"
dl_into "$WAN_TXTENC_URL" "${COMFY_ROOT}/models/text_encoders" "umt5_xxl_fp8_e4m3fn_scaled.safetensors"

# Diffusion (HIGH/LOW)
dl_into "$WAN_HIGH_URL" "${COMFY_ROOT}/models/diffusion_models" "wan2.2_i2v_high_noise_14B_fp8_scaled.safetensors"
dl_into "$WAN_LOW_URL"  "${COMFY_ROOT}/models/diffusion_models" "wan2.2_i2v_low_noise_14B_fp8_scaled.safetensors"

# LoRA
dl_into "$WAN_LORA_LOW_URL"  "${COMFY_ROOT}/models/loras" "wan2.2_i2v_lightx2v_4steps_lora_v1_low_noise.safetensors"
dl_into "$WAN_LORA_HIGH_URL" "${COMFY_ROOT}/models/loras" "wan2.2_i2v_lightx2v_4steps_lora_v1_high_noise.safetensors"
