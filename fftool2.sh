#!/usr/bin/env bash
#
# fftool.sh — interactive FFmpeg helper
#

set -euo pipefail

# ════════════════════════════════════════════════════════════
# 1. KOLORY
# ════════════════════════════════════════════════════════════
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ════════════════════════════════════════════════════════════
# 2. FUNKCJE POMOCNICZE (muszą być przed wszystkim innym)
# ════════════════════════════════════════════════════════════
banner() {
    clear
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════╗"
    echo "║     🎬  FFtool — FFmpeg Helper       ║"
    echo "╚══════════════════════════════════════╝"
    echo -e "${NC}"
}

info()    { echo -e "${GREEN}[✓]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
error()   { echo -e "${RED}[✗]${NC} $1"; }
ask()     { echo -en "${BLUE}[?]${NC} $1"; }
divider() { echo -e "${CYAN}──────────────────────────────────────${NC}"; }

# ════════════════════════════════════════════════════════════
# 3. DETEKCJA MENEDŻERA PAKIETÓW
# ════════════════════════════════════════════════════════════
detect_pkg_manager() {
    if command -v pacman &>/dev/null; then
        PKG_MANAGER="pacman"
        PKG_INSTALL="sudo pacman -S --noconfirm"
    elif command -v apt &>/dev/null; then
        PKG_MANAGER="apt"
        PKG_INSTALL="sudo apt install -y"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
        PKG_INSTALL="sudo dnf install -y"
    else
        PKG_MANAGER="unknown"
        PKG_INSTALL=""
    fi
}

# ════════════════════════════════════════════════════════════
# 4. SPRAWDZANIE ZALEŻNOŚCI
# ════════════════════════════════════════════════════════════
check_deps() {
    local -A deps=(
        [ffmpeg]="ffmpeg"
        [ffprobe]="ffmpeg"
        [bc]="bc"
        [python3]="python3"
    )

    local missing_cmds=()
    local missing_pkgs=()

    for cmd in "${!deps[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_cmds+=("$cmd")
            local pkg="${deps[$cmd]}"
            if [[ ! " ${missing_pkgs[*]:-} " =~ " ${pkg} " ]]; then
                missing_pkgs+=("$pkg")
            fi
        fi
    done

    if [[ ${#missing_cmds[@]} -eq 0 ]]; then
        return 0
    fi

    echo -e "${RED}╔══════════════════════════════════════╗${NC}"
    echo -e "${RED}║       Missing dependencies!          ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Missing commands: ${YELLOW}${missing_cmds[*]}${NC}"
    echo -e "Packages to install: ${YELLOW}${missing_pkgs[*]}${NC}"
    echo ""

    detect_pkg_manager

    if [[ "$PKG_MANAGER" == "unknown" ]]; then
        error "Can't detect package manager!"
        echo "    Install manually: ${missing_pkgs[*]}"
        exit 1
    fi

    echo -e "Detected system: ${GREEN}${PKG_MANAGER}${NC}"
    echo -e "Command: ${CYAN}${PKG_INSTALL} ${missing_pkgs[*]}${NC}"
    echo ""
    ask "Install? [Y/n]: "
    read -r answer

    if [[ "${answer,,}" == "n" ]]; then
        error "Can't run without these packages."
        exit 1
    fi

    echo ""
    info "Installing..."
    echo ""

    if [[ "$PKG_MANAGER" == "apt" ]]; then
        sudo apt update
    fi

    $PKG_INSTALL "${missing_pkgs[@]}"

    local still_missing=()
    for cmd in "${missing_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            still_missing+=("$cmd")
        fi
    done

    if [[ ${#still_missing[@]} -gt 0 ]]; then
        echo ""
        error "Still missing: ${still_missing[*]}"
        echo "    Try installing manually."
        exit 1
    fi

    echo ""
    info "All dependencies installed!"
    echo ""
    sleep 1
}

# ════════════════════════════════════════════════════════════
# 5. DETEKCJA GPU ENKODERA
# ════════════════════════════════════════════════════════════
detect_gpu_encoder() {
    if ffmpeg -encoders 2>/dev/null | grep -q h264_nvenc; then
        GPU_ENCODER="h264_nvenc"
        GPU_HEVC="hevc_nvenc"
        GPU_NAME="NVIDIA (NVENC)"
    elif ffmpeg -encoders 2>/dev/null | grep -q h264_vaapi; then
        GPU_ENCODER="h264_vaapi"
        GPU_HEVC="hevc_vaapi"
        GPU_NAME="VAAPI (AMD/Intel)"
    elif ffmpeg -encoders 2>/dev/null | grep -q h264_qsv; then
        GPU_ENCODER="h264_qsv"
        GPU_HEVC="hevc_qsv"
        GPU_NAME="Intel QuickSync"
    else
        GPU_ENCODER=""
        GPU_HEVC=""
        GPU_NAME=""
    fi
}

# ════════════════════════════════════════════════════════════
# 6. ODPAL SPRAWDZANIE (kolejność ważna!)
#    - najpierw check_deps (bo potrzebujemy ffmpeg)
#    - potem detect_gpu (bo potrzebuje ffmpeg żeby sprawdzić enkodery)
# ════════════════════════════════════════════════════════════
check_deps
detect_gpu_encoder

# ════════════════════════════════════════════════════════════
# 7. FUNKCJE PLIKOWE
# ════════════════════════════════════════════════════════════
get_input_file() {
    if [[ -n "${INPUT_FILE:-}" ]]; then
        return
    fi

    echo ""
    ask "Input file (path or name): "
    read -r INPUT_FILE

    INPUT_FILE="${INPUT_FILE//\"/}"
    INPUT_FILE="${INPUT_FILE//\'/}"

    if [[ ! -f "$INPUT_FILE" ]]; then
        error "File '$INPUT_FILE' not found!"
        exit 1
    fi

    divider
    echo -e "${BOLD}File:${NC} $INPUT_FILE"

    local ext="${INPUT_FILE##*.}"
    ext="${ext,,}"

    local size_bytes
    size_bytes=$(stat --format="%s" "$INPUT_FILE" 2>/dev/null || stat -f%z "$INPUT_FILE" 2>/dev/null)
    local size_mb
    size_mb=$(echo "scale=2; $size_bytes / 1048576" | bc)
    echo -e "${BOLD}Size:${NC} ${size_mb} MB"

    local has_video has_audio
    has_video=$(ffprobe -v error -select_streams v -show_entries stream=codec_type -of csv=p=0 "$INPUT_FILE" 2>/dev/null | head -1)
    has_audio=$(ffprobe -v error -select_streams a -show_entries stream=codec_type -of csv=p=0 "$INPUT_FILE" 2>/dev/null | head -1)

    if [[ -n "$has_video" && -n "$has_audio" ]]; then
        FILE_TYPE="video"
        local resolution duration vcodec acodec
        resolution=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$INPUT_FILE" 2>/dev/null)
        duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" 2>/dev/null | cut -d. -f1)
        vcodec=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" 2>/dev/null)
        acodec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" 2>/dev/null)
        echo -e "${BOLD}Type:${NC} Video (${vcodec} + ${acodec})"
        echo -e "${BOLD}Resolution:${NC} ${resolution}"
        if [[ -n "$duration" && "$duration" -gt 0 ]]; then
            printf "${BOLD}Duration:${NC} %02d:%02d:%02d\n" $((duration/3600)) $((duration%3600/60)) $((duration%60))
        fi
    elif [[ -n "$has_video" ]]; then
        FILE_TYPE="image"
        echo -e "${BOLD}Type:${NC} Image"
    elif [[ -n "$has_audio" ]]; then
        FILE_TYPE="audio"
        local acodec duration
        acodec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" 2>/dev/null)
        duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" 2>/dev/null | cut -d. -f1)
        echo -e "${BOLD}Type:${NC} Audio (${acodec})"
        if [[ -n "$duration" && "$duration" -gt 0 ]]; then
            printf "${BOLD}Duration:${NC} %02d:%02d:%02d\n" $((duration/3600)) $((duration%3600/60)) $((duration%60))
        fi
    else
        FILE_TYPE="unknown"
        warn "Unknown file type"
    fi

    INPUT_EXT="${ext}"
    divider
}

get_output_file() {
    local suggested_ext="${1:-mp4}"
    local base="${INPUT_FILE%.*}"
    local suggested="${base}_output.${suggested_ext}"

    echo ""
    ask "Output file [${suggested}]: "
    read -r OUTPUT_FILE

    if [[ -z "$OUTPUT_FILE" ]]; then
        OUTPUT_FILE="$suggested"
    fi

    if [[ "$OUTPUT_FILE" == "$INPUT_FILE" ]]; then
        error "Output can't be the same as input!"
        OUTPUT_FILE="${base}_converted.${suggested_ext}"
        warn "Changed to: $OUTPUT_FILE"
    fi

    if [[ -f "$OUTPUT_FILE" ]]; then
        ask "'$OUTPUT_FILE' exists. Overwrite? [y/N]: "
        read -r confirm
        if [[ "${confirm,,}" != "y" && "${confirm,,}" != "t" ]]; then
            error "Cancelled."
            exit 0
        fi
    fi
}

# ════════════════════════════════════════════════════════════
# 8. WYKONANIE KOMENDY
# ════════════════════════════════════════════════════════════
run_cmd() {
    local cmd="$1"
    echo ""
    divider
    echo -e "${BOLD}Command:${NC}"
    echo -e "${YELLOW}${cmd}${NC}"
    divider
    ask "Execute? [Y/n]: "
    read -r confirm

    if [[ "${confirm,,}" == "n" ]]; then
        warn "Cancelled."
        return
    fi

    echo ""
    info "Running..."
    echo ""

    eval "$cmd"

    local exit_code=$?
    echo ""
    if [[ $exit_code -eq 0 ]]; then
        info "Done! → ${OUTPUT_FILE}"
        if [[ -f "$OUTPUT_FILE" ]]; then
            local size_bytes
            size_bytes=$(stat --format="%s" "$OUTPUT_FILE" 2>/dev/null || stat -f%z "$OUTPUT_FILE" 2>/dev/null)
            local size_mb
            size_mb=$(echo "scale=2; $size_bytes / 1048576" | bc)
            info "Output size: ${size_mb} MB"
        fi
    else
        error "Something went wrong (exit code: $exit_code)"
    fi
}

# ════════════════════════════════════════════════════════════
# 9. MENU: KONWERSJA WIDEO
# ════════════════════════════════════════════════════════════
menu_convert_video() {
    echo ""
    echo -e "${BOLD}Convert video to:${NC}"
    echo "  1) MP4  (H.264 + AAC) — most compatible"
    echo "  2) MKV  (copy codecs — instant)"
    echo "  3) WebM (VP9 + Opus — web)"
    echo "  4) MOV  (H.264 + AAC — Apple)"
    echo "  5) AVI  (H.264 + MP3)"
    echo "  6) GIF  (animation)"
    echo "  7) MP4 H.265/HEVC (better compression)"
    echo "  0) ← Back"
    echo ""
    ask "Choice: "
    read -r choice

    case "$choice" in
        1)
            get_output_file "mp4"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -c:v libx264 -crf 23 -preset medium -c:a aac -b:a 192k -y \"$OUTPUT_FILE\""
            ;;
        2)
            get_output_file "mkv"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -c copy -y \"$OUTPUT_FILE\""
            ;;
        3)
            get_output_file "webm"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -c:v libvpx-vp9 -crf 30 -b:v 0 -c:a libopus -b:a 128k -y \"$OUTPUT_FILE\""
            ;;
        4)
            get_output_file "mov"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -c:v libx264 -crf 23 -c:a aac -b:a 192k -y \"$OUTPUT_FILE\""
            ;;
        5)
            get_output_file "avi"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -c:v libx264 -crf 23 -c:a libmp3lame -b:a 192k -y \"$OUTPUT_FILE\""
            ;;
        6)
            get_output_file "gif"
            echo ""
            ask "GIF width in px [480]: "
            read -r gif_width
            gif_width="${gif_width:-480}"
            ask "FPS [15]: "
            read -r gif_fps
            gif_fps="${gif_fps:-15}"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -vf \"fps=${gif_fps},scale=${gif_width}:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse\" -y \"$OUTPUT_FILE\""
            ;;
        7)
            get_output_file "mp4"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -c:v libx265 -crf 28 -preset medium -c:a aac -b:a 128k -tag:v hvc1 -y \"$OUTPUT_FILE\""
            ;;
        0) return ;;
        *) warn "Unknown option" ;;
    esac
}

# ════════════════════════════════════════════════════════════
# 10. MENU: KONWERSJA AUDIO
# ════════════════════════════════════════════════════════════
menu_convert_audio() {
    echo ""
    echo -e "${BOLD}Convert audio to:${NC}"
    echo "  1) MP3 128k  (small)"
    echo "  2) MP3 192k  (good)"
    echo "  3) MP3 320k  (best MP3)"
    echo "  4) AAC 256k  (.m4a)"
    echo "  5) OGG Vorbis"
    echo "  6) Opus 128k (best modern codec)"
    echo "  7) WAV (lossless, big)"
    echo "  8) FLAC (lossless, compressed)"
    echo "  0) ← Back"
    echo ""
    ask "Choice: "
    read -r choice

    case "$choice" in
        1) get_output_file "mp3";  run_cmd "ffmpeg -i \"$INPUT_FILE\" -vn -c:a libmp3lame -b:a 128k -y \"$OUTPUT_FILE\"" ;;
        2) get_output_file "mp3";  run_cmd "ffmpeg -i \"$INPUT_FILE\" -vn -c:a libmp3lame -b:a 192k -y \"$OUTPUT_FILE\"" ;;
        3) get_output_file "mp3";  run_cmd "ffmpeg -i \"$INPUT_FILE\" -vn -c:a libmp3lame -b:a 320k -y \"$OUTPUT_FILE\"" ;;
        4) get_output_file "m4a";  run_cmd "ffmpeg -i \"$INPUT_FILE\" -vn -c:a aac -b:a 256k -y \"$OUTPUT_FILE\"" ;;
        5) get_output_file "ogg";  run_cmd "ffmpeg -i \"$INPUT_FILE\" -vn -c:a libvorbis -q:a 6 -y \"$OUTPUT_FILE\"" ;;
        6) get_output_file "opus"; run_cmd "ffmpeg -i \"$INPUT_FILE\" -vn -c:a libopus -b:a 128k -y \"$OUTPUT_FILE\"" ;;
        7) get_output_file "wav";  run_cmd "ffmpeg -i \"$INPUT_FILE\" -vn -c:a pcm_s16le -y \"$OUTPUT_FILE\"" ;;
        8) get_output_file "flac"; run_cmd "ffmpeg -i \"$INPUT_FILE\" -vn -c:a flac -y \"$OUTPUT_FILE\"" ;;
        0) return ;;
        *) warn "Unknown option" ;;
    esac
}

# ════════════════════════════════════════════════════════════
# 11. MENU: KOMPRESJA
# ════════════════════════════════════════════════════════════
menu_compress() {
    echo ""
    echo -e "${BOLD}Compression — how much?${NC}"
    echo ""
    echo -e "  ${BOLD}CPU encoding:${NC}"
    echo "  1) Light      (~75% of original)  CRF 25"
    echo "  2) Medium     (~50% of original)  CRF 28"
    echo "  3) Heavy      (~30% of original)  CRF 32"
    echo "  4) Brutal     (~15% of original)  CRF 38"
    echo ""
    echo -e "  ${BOLD}Resolution:${NC}"
    echo "  5) Downscale → 720p"
    echo "  6) Downscale → 480p"
    echo ""
    echo -e "  ${BOLD}Advanced:${NC}"
    echo "  7) Target file size (e.g. 25 MB)"
    echo "  8) Custom CRF (you choose)"
    echo ""
    echo -e "  ${BOLD}GPU encoding (fast!):${NC}"
    if [[ -n "$GPU_ENCODER" ]]; then
        echo -e "  g) 🚀 GPU compress (${GREEN}${GPU_NAME} detected${NC})"
    else
        echo -e "  g) 🚀 GPU compress (${RED}not available${NC})"
    fi
    echo ""
    echo "  0) ← Back"
    echo ""
    ask "Choice: "
    read -r choice

    case "$choice" in
        1)
            get_output_file "mp4"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -c:v libx264 -crf 25 -preset slow -c:a aac -b:a 192k -y \"$OUTPUT_FILE\""
            ;;
        2)
            get_output_file "mp4"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -c:v libx264 -crf 28 -preset slow -c:a aac -b:a 128k -y \"$OUTPUT_FILE\""
            ;;
        3)
            get_output_file "mp4"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -c:v libx264 -crf 32 -preset slow -c:a aac -b:a 96k -y \"$OUTPUT_FILE\""
            ;;
        4)
            get_output_file "mp4"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -c:v libx264 -crf 38 -preset slow -c:a aac -b:a 64k -y \"$OUTPUT_FILE\""
            ;;
        5)
            get_output_file "mp4"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -vf \"scale=-2:720\" -c:v libx264 -crf 23 -preset medium -c:a aac -b:a 128k -y \"$OUTPUT_FILE\""
            ;;
        6)
            get_output_file "mp4"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -vf \"scale=-2:480\" -c:v libx264 -crf 23 -preset medium -c:a aac -b:a 96k -y \"$OUTPUT_FILE\""
            ;;
        7)
            get_output_file "mp4"
            echo ""
            ask "Target size in MB: "
            read -r target_mb

            local duration
            duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" | cut -d. -f1)

            if [[ -z "$duration" || "$duration" -eq 0 ]]; then
                error "Can't read file duration"
                return
            fi

            local audio_br=128
            local total_br video_br
            total_br=$(( (target_mb * 8192) / duration ))
            video_br=$(( total_br - audio_br ))

            if [[ $video_br -le 0 ]]; then
                error "Target size too small for this file!"
                return
            fi

            info "Calculated video bitrate: ${video_br}k (audio: ${audio_br}k)"
            info "Using 2-pass encoding..."

            echo ""
            echo -e "${YELLOW}Pass 1: ffmpeg -i \"$INPUT_FILE\" -c:v libx264 -b:v ${video_br}k -pass 1 -an -f null /dev/null${NC}"
            echo -e "${YELLOW}Pass 2: ffmpeg -i \"$INPUT_FILE\" -c:v libx264 -b:v ${video_br}k -pass 2 -c:a aac -b:a ${audio_br}k \"$OUTPUT_FILE\"${NC}"
            divider
            ask "Execute? [Y/n]: "
            read -r confirm
            if [[ "${confirm,,}" == "n" ]]; then
                warn "Cancelled."
                return
            fi

            ffmpeg -i "$INPUT_FILE" -c:v libx264 -b:v "${video_br}k" -pass 1 -an -f null /dev/null 2>&1
            ffmpeg -i "$INPUT_FILE" -c:v libx264 -b:v "${video_br}k" -pass 2 -c:a aac -b:a "${audio_br}k" -y "$OUTPUT_FILE" 2>&1
            rm -f ffmpeg2pass-0.log ffmpeg2pass-0.log.mbtree

            info "Done! → $OUTPUT_FILE"
            if [[ -f "$OUTPUT_FILE" ]]; then
                local sz
                sz=$(stat --format="%s" "$OUTPUT_FILE" 2>/dev/null || stat -f%z "$OUTPUT_FILE" 2>/dev/null)
                info "Size: $(echo "scale=2; $sz / 1048576" | bc) MB (target: ${target_mb} MB)"
            fi
            ;;
        8)
            echo ""
            ask "CRF value (0=lossless, 23=default, 51=worst): "
            read -r custom_crf
            get_output_file "mp4"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -c:v libx264 -crf ${custom_crf} -preset slow -c:a aac -b:a 128k -y \"$OUTPUT_FILE\""
            ;;
        g|G)
            if [[ -z "$GPU_ENCODER" ]]; then
                error "No GPU encoder detected!"
                warn "You need: NVIDIA + drivers, or AMD/Intel with VAAPI"
                return
            fi

            get_output_file "mp4"
            echo ""
            echo -e "Encoder: ${GREEN}${GPU_NAME}${NC}"
            ask "Quality CQ (18=great, 28=ok, 35=small) [23]: "
            read -r gpu_cq
            gpu_cq="${gpu_cq:-23}"

            if [[ "$GPU_ENCODER" == "h264_vaapi" ]]; then
                run_cmd "ffmpeg -vaapi_device /dev/dri/renderD128 -i \"$INPUT_FILE\" -vf 'format=nv12,hwupload' -c:v ${GPU_ENCODER} -qp ${gpu_cq} -c:a aac -b:a 128k -y \"$OUTPUT_FILE\""
            else
                run_cmd "ffmpeg -i \"$INPUT_FILE\" -c:v ${GPU_ENCODER} -cq ${gpu_cq} -preset p4 -c:a aac -b:a 128k -y \"$OUTPUT_FILE\""
            fi
            ;;
        0) return ;;
        *) warn "Unknown option" ;;
    esac
}

# ════════════════════════════════════════════════════════════
# 12. MENU: ZMIANA PRĘDKOŚCI
# ════════════════════════════════════════════════════════════
menu_speed() {
    echo ""
    echo -e "${BOLD}Change speed:${NC}"
    echo ""
    echo -e "  ${BOLD}Speed up:${NC}"
    echo "  1) +15%   (×1.15)"
    echo "  2) +25%   (×1.25)"
    echo "  3) +40%   (×1.40)"
    echo "  4) +50%   (×1.50)"
    echo "  5) +60%   (×1.60)"
    echo "  6) ×2     (double)"
    echo "  7) ×3     (triple)"
    echo ""
    echo -e "  ${BOLD}Slow down:${NC}"
    echo "  8) -25%   (×0.75)"
    echo "  9) -50%   (×0.50 — slow motion)"
    echo ""
    echo "  c) Custom multiplier"
    echo "  0) ← Back"
    echo ""
    ask "Choice: "
    read -r choice

    local speed_factor atempo_filter

    case "$choice" in
        1) speed_factor="1.15" ;;
        2) speed_factor="1.25" ;;
        3) speed_factor="1.40" ;;
        4) speed_factor="1.50" ;;
        5) speed_factor="1.60" ;;
        6) speed_factor="2.0"  ;;
        7) speed_factor="3.0"  ;;
        8) speed_factor="0.75" ;;
        9) speed_factor="0.50" ;;
        c|C)
            ask "Multiplier (e.g. 1.3 = +30%, 0.8 = -20%): "
            read -r speed_factor
            ;;
        0) return ;;
        *) warn "Unknown option"; return ;;
    esac

    local py_result
    py_result=$(python3 -c "
factor = $speed_factor
parts = []
if factor >= 1.0:
    while factor > 2.0:
        parts.append('2.0')
        factor /= 2.0
    parts.append(f'{factor:.4f}')
else:
    while factor < 0.5:
        parts.append('0.5')
        factor /= 0.5
    parts.append(f'{factor:.4f}')
print(','.join(['atempo=' + p for p in parts]))
" 2>/dev/null)

    if [[ -z "$py_result" ]]; then
        if (( $(echo "$speed_factor <= 2.0" | bc -l) )) && (( $(echo "$speed_factor >= 0.5" | bc -l) )); then
            py_result="atempo=${speed_factor}"
        else
            error "Need python3 for speeds >2x or <0.5x"
            return
        fi
    fi

    atempo_filter="$py_result"

    get_output_file "mp4"

    if [[ "$FILE_TYPE" == "audio" ]]; then
        run_cmd "ffmpeg -i \"$INPUT_FILE\" -af \"${atempo_filter}\" -y \"$OUTPUT_FILE\""
    else
        run_cmd "ffmpeg -i \"$INPUT_FILE\" -filter_complex \"[0:v]setpts=PTS/${speed_factor}[v];[0:a]${atempo_filter}[a]\" -map \"[v]\" -map \"[a]\" -c:v libx264 -crf 23 -preset medium -c:a aac -b:a 128k -y \"$OUTPUT_FILE\""
    fi
}

# ════════════════════════════════════════════════════════════
# 13. MENU: WYCINANIE
# ════════════════════════════════════════════════════════════
menu_cut() {
    echo ""
    echo -e "${BOLD}Cut/Trim:${NC}"
    echo "  1) From—To (fast, no re-encoding)"
    echo "  2) From—To (precise, re-encoded)"
    echo "  3) First N seconds"
    echo "  4) Last N seconds"
    echo "  0) ← Back"
    echo ""
    ask "Choice: "
    read -r choice

    case "$choice" in
        1)
            ask "Start time (e.g. 00:01:30 or 90): "
            read -r start_time
            ask "End time (e.g. 00:04:00 or 240): "
            read -r end_time
            get_output_file "${INPUT_EXT}"
            run_cmd "ffmpeg -ss ${start_time} -to ${end_time} -i \"$INPUT_FILE\" -c copy -y \"$OUTPUT_FILE\""
            ;;
        2)
            ask "Start time: "
            read -r start_time
            ask "End time: "
            read -r end_time
            get_output_file "mp4"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -ss ${start_time} -to ${end_time} -c:v libx264 -crf 23 -c:a aac -y \"$OUTPUT_FILE\""
            ;;
        3)
            ask "How many seconds from the start? "
            read -r secs
            get_output_file "${INPUT_EXT}"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -t ${secs} -c copy -y \"$OUTPUT_FILE\""
            ;;
        4)
            ask "How many seconds from the end? "
            read -r secs
            get_output_file "${INPUT_EXT}"
            run_cmd "ffmpeg -sseof -${secs} -i \"$INPUT_FILE\" -c copy -y \"$OUTPUT_FILE\""
            ;;
        0) return ;;
        *) warn "Unknown option" ;;
    esac
}

# ════════════════════════════════════════════════════════════
# 14. MENU: EKSTRAKCJA AUDIO
# ════════════════════════════════════════════════════════════
menu_extract_audio() {
    echo ""
    echo -e "${BOLD}Extract audio from video:${NC}"
    echo "  1) MP3 320k"
    echo "  2) MP3 192k"
    echo "  3) AAC (copy, no re-encoding — instant)"
    echo "  4) WAV (lossless)"
    echo "  5) FLAC (lossless compressed)"
    echo "  0) ← Back"
    echo ""
    ask "Choice: "
    read -r choice

    case "$choice" in
        1) get_output_file "mp3";  run_cmd "ffmpeg -i \"$INPUT_FILE\" -vn -c:a libmp3lame -b:a 320k -y \"$OUTPUT_FILE\"" ;;
        2) get_output_file "mp3";  run_cmd "ffmpeg -i \"$INPUT_FILE\" -vn -c:a libmp3lame -b:a 192k -y \"$OUTPUT_FILE\"" ;;
        3) get_output_file "aac";  run_cmd "ffmpeg -i \"$INPUT_FILE\" -vn -c:a copy -y \"$OUTPUT_FILE\"" ;;
        4) get_output_file "wav";  run_cmd "ffmpeg -i \"$INPUT_FILE\" -vn -c:a pcm_s16le -y \"$OUTPUT_FILE\"" ;;
        5) get_output_file "flac"; run_cmd "ffmpeg -i \"$INPUT_FILE\" -vn -c:a flac -y \"$OUTPUT_FILE\"" ;;
        0) return ;;
        *) warn "Unknown option" ;;
    esac
}

# ════════════════════════════════════════════════════════════
# 15. MENU: KONWERSJA OBRAZÓW
# ════════════════════════════════════════════════════════════
menu_convert_image() {
    echo ""
    echo -e "${BOLD}Convert image:${NC}"
    echo "  1) → JPG"
    echo "  2) → PNG"
    echo "  3) → WebP"
    echo "  4) → BMP"
    echo "  5) Resize (set width)"
    echo "  0) ← Back"
    echo ""
    ask "Choice: "
    read -r choice

    case "$choice" in
        1)
            get_output_file "jpg"
            ask "JPG quality (2=best, 31=worst) [5]: "
            read -r q; q="${q:-5}"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -q:v ${q} -y \"$OUTPUT_FILE\""
            ;;
        2) get_output_file "png";  run_cmd "ffmpeg -i \"$INPUT_FILE\" -y \"$OUTPUT_FILE\"" ;;
        3)
            get_output_file "webp"
            ask "WebP quality (0-100) [85]: "
            read -r q; q="${q:-85}"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -quality ${q} -y \"$OUTPUT_FILE\""
            ;;
        4) get_output_file "bmp";  run_cmd "ffmpeg -i \"$INPUT_FILE\" -y \"$OUTPUT_FILE\"" ;;
        5)
            ask "New width in px (height auto): "
            read -r new_w
            get_output_file "${INPUT_EXT}"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -vf \"scale=${new_w}:-1\" -y \"$OUTPUT_FILE\""
            ;;
        0) return ;;
        *) warn "Unknown option" ;;
    esac
}

# ════════════════════════════════════════════════════════════
# 16. MENU: INFO O PLIKU
# ════════════════════════════════════════════════════════════
menu_info() {
    echo ""
    echo -e "${BOLD}Detailed file info:${NC}"
    divider
    ffprobe -hide_banner "$INPUT_FILE" 2>&1
    divider
    echo ""
    ask "Press Enter to continue..."
    read -r
}

# ════════════════════════════════════════════════════════════
# 17. MENU: EKSTRA
# ════════════════════════════════════════════════════════════
menu_extras() {
    echo ""
    echo -e "${BOLD}Extras:${NC}"
    echo "  1) Screenshot at specific time"
    echo "  2) Screenshots every N seconds"
    echo "  3) Remove audio (silent video)"
    echo "  4) Change FPS"
    echo "  5) Rotate 90° right"
    echo "  6) Mirror (horizontal flip)"
    echo "  7) Black & white"
    echo "  8) Normalize volume"
    echo "  9) Reverse video"
    echo "  0) ← Back"
    echo ""
    ask "Choice: "
    read -r choice

    case "$choice" in
        1)
            ask "At what time? (e.g. 00:00:30 or 30): "
            read -r ss_time
            get_output_file "png"
            run_cmd "ffmpeg -ss ${ss_time} -i \"$INPUT_FILE\" -frames:v 1 -y \"$OUTPUT_FILE\""
            ;;
        2)
            ask "Every how many seconds? [5]: "
            read -r interval; interval="${interval:-5}"
            local outdir="${INPUT_FILE%.*}_screenshots"
            mkdir -p "$outdir"
            OUTPUT_FILE="${outdir}/thumb_%04d.png"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -vf \"fps=1/${interval}\" -y \"${outdir}/thumb_%04d.png\""
            ;;
        3)
            get_output_file "${INPUT_EXT}"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -an -c:v copy -y \"$OUTPUT_FILE\""
            ;;
        4)
            ask "New FPS [30]: "
            read -r new_fps; new_fps="${new_fps:-30}"
            get_output_file "mp4"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -vf \"fps=${new_fps}\" -c:v libx264 -crf 23 -c:a copy -y \"$OUTPUT_FILE\""
            ;;
        5)
            get_output_file "mp4"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -vf \"transpose=1\" -c:v libx264 -crf 23 -c:a copy -y \"$OUTPUT_FILE\""
            ;;
        6)
            get_output_file "mp4"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -vf \"hflip\" -c:v libx264 -crf 23 -c:a copy -y \"$OUTPUT_FILE\""
            ;;
        7)
            get_output_file "mp4"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -vf \"hue=s=0\" -c:v libx264 -crf 23 -c:a copy -y \"$OUTPUT_FILE\""
            ;;
        8)
            get_output_file "${INPUT_EXT}"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -af \"loudnorm\" -c:v copy -y \"$OUTPUT_FILE\""
            ;;
        9)
            get_output_file "mp4"
            warn "This loads the entire file into RAM — large files may not fit!"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -vf \"reverse\" -af \"areverse\" -y \"$OUTPUT_FILE\""
            ;;
        0) return ;;
        *) warn "Unknown option" ;;
    esac
}

# ════════════════════════════════════════════════════════════
# 18. GŁÓWNE MENU
# ════════════════════════════════════════════════════════════
main() {
    if [[ -n "${1:-}" ]]; then
        INPUT_FILE="$1"
        if [[ ! -f "$INPUT_FILE" ]]; then
            error "File '$INPUT_FILE' not found!"
            exit 1
        fi
    fi

    INPUT_FILE="${INPUT_FILE:-}"
    FILE_TYPE=""
    INPUT_EXT=""

    while true; do
        banner

        if [[ -n "$INPUT_FILE" ]]; then
            echo -e "  File: ${GREEN}${INPUT_FILE}${NC}"
            if [[ -n "$GPU_NAME" ]]; then
                echo -e "  GPU:  ${GREEN}${GPU_NAME}${NC}"
            fi
            echo ""
        fi

        echo -e "${BOLD}  What do you want to do?${NC}"
        echo ""
        echo "  1) 🔄  Convert video"
        echo "  2) 🎵  Convert audio"
        echo "  3) 🖼️   Convert image"
        echo "  4) 📦  Compress (reduce file size)"
        echo "  5) ⏩  Change speed"
        echo "  6) ✂️   Cut/trim"
        echo "  7) 🔊  Extract audio from video"
        echo "  8) 📊  File info"
        echo "  9) 🧰  Extras (screenshots, rotate, FPS...)"
        echo ""
        echo "  f)     Change input file"
        echo "  q)     Quit"
        echo ""
        ask "Choice: "
        read -r main_choice

        case "$main_choice" in
            1) get_input_file; menu_convert_video ;;
            2) get_input_file; menu_convert_audio ;;
            3) get_input_file; menu_convert_image ;;
            4) get_input_file; menu_compress ;;
            5) get_input_file; menu_speed ;;
            6) get_input_file; menu_cut ;;
            7) get_input_file; menu_extract_audio ;;
            8) get_input_file; menu_info ;;
            9) get_input_file; menu_extras ;;
            f|F)
                INPUT_FILE=""
                FILE_TYPE=""
                INPUT_EXT=""
                get_input_file
                ;;
            q|Q)
                echo ""
                info "See you! 👋"
                exit 0
                ;;
            *)
                warn "Unknown option"
                sleep 1
                ;;
        esac

        echo ""
        ask "Press Enter to go back to menu..."
        read -r
    done
}

main "$@"
