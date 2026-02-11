#!/usr/bin/env bash
#
# fftool.sh — interaktywne "GUI dla biednych" do ffmpeg
# Użycie: ./fftool.sh [opcjonalnie_plik_wejściowy]
#

set -euo pipefail

# ── Kolory ──────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # reset

# ── Pomocnicze funkcje ──────────────────────────────────
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

# Sprawdź czy ffmpeg jest zainstalowany
# ── Wykrywanie menedżera pakietów ───────────────────────
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

# ── Sprawdzanie i instalacja zależności ─────────────────
check_deps() {
    # komenda → nazwa pakietu (taka sama na apt/pacman/dnf)
    local -A deps=(
        [ffmpeg]="ffmpeg"
        [ffprobe]="ffmpeg"    # ffprobe jest w paczce ffmpeg
        [bc]="bc"
        [python3]="python3"
    )

    local missing_cmds=()
    local missing_pkgs=()

    for cmd in "${!deps[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_cmds+=("$cmd")
            # Dodaj pakiet tylko jeśli jeszcze go nie ma w liście
            local pkg="${deps[$cmd]}"
            if [[ ! " ${missing_pkgs[*]:-} " =~ " ${pkg} " ]]; then
                missing_pkgs+=("$pkg")
            fi
        fi
    done

    # Wszystko jest — lecimy
    if [[ ${#missing_cmds[@]} -eq 0 ]]; then
        return 0
    fi

    # Coś brakuje
    echo -e "${RED}╔══════════════════════════════════════╗${NC}"
    echo -e "${RED}║       Brakujące zależności!          ║${NC}"
    echo -e "${RED}╚══════════════════════════════════════╝${NC}"
    echo ""
    echo -e "Brakuje komend: ${YELLOW}${missing_cmds[*]}${NC}"
    echo -e "Pakiety do instalacji: ${YELLOW}${missing_pkgs[*]}${NC}"
    echo ""

    detect_pkg_manager

    if [[ "$PKG_MANAGER" == "unknown" ]]; then
        echo -e "${RED}[✗]${NC} Nie rozpoznałem menedżera pakietów!"
        echo "    Zainstaluj ręcznie: ${missing_pkgs[*]}"
        exit 1
    fi

    echo -e "Wykryty system: ${GREEN}${PKG_MANAGER}${NC}"
    echo -e "Komenda: ${CYAN}${PKG_INSTALL} ${missing_pkgs[*]}${NC}"
    echo ""
    echo -en "${BLUE}[?]${NC} Zainstalować? [T/n]: "
    read -r answer

    if [[ "${answer,,}" == "n" ]]; then
        echo -e "${RED}[✗]${NC} Bez tych pakietów skrypt nie zadziała. Elo."
        exit 1
    fi

    echo ""
    echo -e "${GREEN}[✓]${NC} Instaluję..."
    echo ""

    # apt potrzebuje update przed instalacją
    if [[ "$PKG_MANAGER" == "apt" ]]; then
        sudo apt update
    fi

    $PKG_INSTALL "${missing_pkgs[@]}"

    # Sprawdź czy się udało
    local still_missing=()
    for cmd in "${missing_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            still_missing+=("$cmd")
        fi
    done

    if [[ ${#still_missing[@]} -gt 0 ]]; then
        echo ""
        echo -e "${RED}[✗]${NC} Nadal brakuje: ${still_missing[*]}"
        echo "    Spróbuj zainstalować ręcznie."
        exit 1
    fi

    echo ""
    echo -e "${GREEN}[✓]${NC} Wszystko zainstalowane! Lecim dalej..."
    echo ""
    sleep 1
}

# ── Odpal sprawdzanie ──────────────────────────────────
check_deps

# ── Pobierz plik wejściowy ──────────────────────────────
get_input_file() {
    if [[ -n "${INPUT_FILE:-}" ]]; then
        return
    fi

    echo ""
    ask "Plik wejściowy (ścieżka lub nazwa): "
    read -r INPUT_FILE

    # Obsłuż cudzysłowy i spacje
    INPUT_FILE="${INPUT_FILE//\"/}"
    INPUT_FILE="${INPUT_FILE//\'/}"

    if [[ ! -f "$INPUT_FILE" ]]; then
        error "Plik '$INPUT_FILE' nie istnieje!"
        exit 1
    fi

    # Wyświetl info o pliku
    divider
    echo -e "${BOLD}Plik:${NC} $INPUT_FILE"

    local ext="${INPUT_FILE##*.}"
    ext="${ext,,}" # lowercase

    # Rozmiar
    local size_bytes
    size_bytes=$(stat --format="%s" "$INPUT_FILE" 2>/dev/null || stat -f%z "$INPUT_FILE" 2>/dev/null)
    local size_mb
    size_mb=$(echo "scale=2; $size_bytes / 1048576" | bc)
    echo -e "${BOLD}Rozmiar:${NC} ${size_mb} MB"

    # Typ
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
        echo -e "${BOLD}Typ:${NC} Wideo (${vcodec} + ${acodec})"
        echo -e "${BOLD}Rozdzielczość:${NC} ${resolution}"
        if [[ -n "$duration" ]]; then
            printf "${BOLD}Czas:${NC} %02d:%02d:%02d\n" $((duration/3600)) $((duration%3600/60)) $((duration%60))
        fi
    elif [[ -n "$has_video" ]]; then
        FILE_TYPE="image"
        echo -e "${BOLD}Typ:${NC} Obraz"
    elif [[ -n "$has_audio" ]]; then
        FILE_TYPE="audio"
        local acodec duration
        acodec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" 2>/dev/null)
        duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" 2>/dev/null | cut -d. -f1)
        echo -e "${BOLD}Typ:${NC} Audio (${acodec})"
        if [[ -n "$duration" ]]; then
            printf "${BOLD}Czas:${NC} %02d:%02d:%02d\n" $((duration/3600)) $((duration%3600/60)) $((duration%60))
        fi
    else
        FILE_TYPE="unknown"
        warn "Nie rozpoznano typu pliku"
    fi

    INPUT_EXT="${ext}"
    divider
}

# ── Pobierz nazwę pliku wyjściowego ─────────────────────
get_output_file() {
    local suggested_ext="${1:-mp4}"
    local base="${INPUT_FILE%.*}"
    local suggested="${base}_output.${suggested_ext}"

    echo ""
    ask "Plik wyjściowy [${suggested}]: "
    read -r OUTPUT_FILE

    if [[ -z "$OUTPUT_FILE" ]]; then
        OUTPUT_FILE="$suggested"
    fi

    # Sprawdź czy nie nadpiszemy wejścia
    if [[ "$OUTPUT_FILE" == "$INPUT_FILE" ]]; then
        error "Plik wyjściowy nie może być taki sam jak wejściowy!"
        OUTPUT_FILE="${base}_converted.${suggested_ext}"
        warn "Zmieniono na: $OUTPUT_FILE"
    fi

    if [[ -f "$OUTPUT_FILE" ]]; then
        ask "Plik '$OUTPUT_FILE' istnieje. Nadpisać? [t/N]: "
        read -r confirm
        if [[ "${confirm,,}" != "t" && "${confirm,,}" != "y" ]]; then
            error "Przerwano."
            exit 0
        fi
    fi
}

# ── Wykonaj komendę ─────────────────────────────────────
run_cmd() {
    local cmd="$1"
    echo ""
    divider
    echo -e "${BOLD}Komenda:${NC}"
    echo -e "${YELLOW}${cmd}${NC}"
    divider
    ask "Wykonać? [T/n]: "
    read -r confirm

    if [[ "${confirm,,}" == "n" ]]; then
        warn "Anulowano."
        return
    fi

    echo ""
    info "Uruchamiam..."
    echo ""

    eval "$cmd"

    local exit_code=$?
    echo ""
    if [[ $exit_code -eq 0 ]]; then
        info "Gotowe! → ${OUTPUT_FILE}"
        if [[ -f "$OUTPUT_FILE" ]]; then
            local size_bytes
            size_bytes=$(stat --format="%s" "$OUTPUT_FILE" 2>/dev/null || stat -f%z "$OUTPUT_FILE" 2>/dev/null)
            local size_mb
            size_mb=$(echo "scale=2; $size_bytes / 1048576" | bc)
            info "Rozmiar wyjściowy: ${size_mb} MB"
        fi
    else
        error "Coś poszło nie tak (kod: $exit_code)"
    fi
}

# ══════════════════════════════════════════════════════════
# ── MENU: Konwersja wideo ────────────────────────────────
# ══════════════════════════════════════════════════════════
menu_convert_video() {
    echo ""
    echo -e "${BOLD}Konwertuj wideo na:${NC}"
    echo "  1) MP4  (H.264 + AAC) — najbardziej kompatybilny"
    echo "  2) MKV  (kopiuj kodeki — natychmiastowe)"
    echo "  3) WebM (VP9 + Opus — do internetu)"
    echo "  4) MOV  (H.264 + AAC — Apple)"
    echo "  5) AVI  (H.264 + MP3)"
    echo "  6) GIF  (animacja)"
    echo "  7) MP4 H.265/HEVC (lepsza kompresja)"
    echo "  0) ← Powrót"
    echo ""
    ask "Wybór: "
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
            ask "Szerokość GIF-a w px [480]: "
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
        *) warn "Nieznana opcja" ;;
    esac
}

# ══════════════════════════════════════════════════════════
# ── MENU: Konwersja audio ────────────────────────────────
# ══════════════════════════════════════════════════════════
menu_convert_audio() {
    echo ""
    echo -e "${BOLD}Konwertuj audio na:${NC}"
    echo "  1) MP3 128k  (mały)"
    echo "  2) MP3 192k  (dobry)"
    echo "  3) MP3 320k  (najlepszy MP3)"
    echo "  4) AAC 256k  (.m4a)"
    echo "  5) OGG Vorbis"
    echo "  6) Opus 128k (najlepszy nowoczesny)"
    echo "  7) WAV (bezstratny, duży)"
    echo "  8) FLAC (bezstratny, skompresowany)"
    echo "  0) ← Powrót"
    echo ""
    ask "Wybór: "
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
        *) warn "Nieznana opcja" ;;
    esac
}

# ══════════════════════════════════════════════════════════
# ── MENU: Kompresja ──────────────────────────────────────
# ══════════════════════════════════════════════════════════
menu_compress() {
    echo ""
    echo -e "${BOLD}Kompresja — jak bardzo zmniejszyć?${NC}"
    echo "  1) Lekka      (~75% oryginału)  CRF 25"
    echo "  2) Średnia     (~50% oryginału)  CRF 28"
    echo "  3) Mocna       (~30% oryginału)  CRF 32"
    echo "  4) Brutalna    (~15% oryginału)  CRF 38"
    echo "  5) Zmniejsz rozdzielczość → 720p"
    echo "  6) Zmniejsz rozdzielczość → 480p"
    echo "  7) Do konkretnego rozmiaru (np. 25 MB)"
    echo "  8) Własny CRF (sam wpisujesz)"
    echo "  0) ← Powrót"
    echo ""
    ask "Wybór: "
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
            ask "Docelowy rozmiar w MB: "
            read -r target_mb

            local duration
            duration=$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$INPUT_FILE" | cut -d. -f1)

            if [[ -z "$duration" || "$duration" -eq 0 ]]; then
                error "Nie mogę odczytać długości pliku"
                return
            fi

            local audio_br=128
            local total_br video_br
            total_br=$(( (target_mb * 8192) / duration ))
            video_br=$(( total_br - audio_br ))

            if [[ $video_br -le 0 ]]; then
                error "Żądany rozmiar za mały dla tego pliku!"
                return
            fi

            info "Obliczony bitrate wideo: ${video_br}k (audio: ${audio_br}k)"
            info "Używam dwuprzebiegowego enkodowania..."

            echo ""
            echo -e "${YELLOW}ffmpeg -i \"$INPUT_FILE\" -c:v libx264 -b:v ${video_br}k -pass 1 -an -f null /dev/null${NC}"
            echo -e "${YELLOW}ffmpeg -i \"$INPUT_FILE\" -c:v libx264 -b:v ${video_br}k -pass 2 -c:a aac -b:a ${audio_br}k \"$OUTPUT_FILE\"${NC}"
            divider
            ask "Wykonać? [T/n]: "
            read -r confirm
            if [[ "${confirm,,}" == "n" ]]; then
                warn "Anulowano."
                return
            fi

            ffmpeg -i "$INPUT_FILE" -c:v libx264 -b:v "${video_br}k" -pass 1 -an -f null /dev/null 2>&1
            ffmpeg -i "$INPUT_FILE" -c:v libx264 -b:v "${video_br}k" -pass 2 -c:a aac -b:a "${audio_br}k" -y "$OUTPUT_FILE" 2>&1
            rm -f ffmpeg2pass-0.log ffmpeg2pass-0.log.mbtree

            info "Gotowe! → $OUTPUT_FILE"
            if [[ -f "$OUTPUT_FILE" ]]; then
                local sz
                sz=$(stat --format="%s" "$OUTPUT_FILE" 2>/dev/null || stat -f%z "$OUTPUT_FILE" 2>/dev/null)
                info "Rozmiar: $(echo "scale=2; $sz / 1048576" | bc) MB (cel: ${target_mb} MB)"
            fi
            ;;
        8)
            echo ""
            ask "Wpisz CRF (0=bezstratne, 23=domyślne, 51=najgorsze): "
            read -r custom_crf
            get_output_file "mp4"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -c:v libx264 -crf ${custom_crf} -preset slow -c:a aac -b:a 128k -y \"$OUTPUT_FILE\""
            ;;
        0) return ;;
        *) warn "Nieznana opcja" ;;
    esac
}

# ══════════════════════════════════════════════════════════
# ── MENU: Zmiana prędkości ───────────────────────────────
# ══════════════════════════════════════════════════════════
menu_speed() {
    echo ""
    echo -e "${BOLD}Zmiana prędkości:${NC}"
    echo ""
    echo -e "  ${BOLD}Przyspieszenie:${NC}"
    echo "  1) +15%   (×1.15)"
    echo "  2) +25%   (×1.25)"
    echo "  3) +40%   (×1.40)"
    echo "  4) +50%   (×1.50)"
    echo "  5) +60%   (×1.60)"
    echo "  6) ×2     (dwukrotnie)"
    echo "  7) ×3     (trzykrotnie)"
    echo ""
    echo -e "  ${BOLD}Zwolnienie:${NC}"
    echo "  8) -25%   (×0.75)"
    echo "  9) -50%   (×0.50 — slow motion)"
    echo ""
    echo "  c) Własny mnożnik"
    echo "  0) ← Powrót"
    echo ""
    ask "Wybór: "
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
            ask "Wpisz mnożnik (np. 1.3 = +30%, 0.8 = -20%): "
            read -r speed_factor
            ;;
        0) return ;;
        *) warn "Nieznana opcja"; return ;;
    esac

    # atempo obsługuje zakres 0.5–2.0, trzeba chainować
    # Obliczamy chain w bashu
    local remaining="$speed_factor"
    atempo_filter=""

    # Prosta metoda: dziel na kawałki po max 2.0 lub min 0.5
    local py_result
    py_result=$(python3 -c "
factor = $remaining
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
        # Fallback bez pythona — prosty przypadek
        if (( $(echo "$speed_factor <= 2.0" | bc -l) )) && (( $(echo "$speed_factor >= 0.5" | bc -l) )); then
            py_result="atempo=${speed_factor}"
        else
            error "Potrzebujesz python3 dla prędkości >2x lub <0.5x"
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

# ══════════════════════════════════════════════════════════
# ── MENU: Wycinanie fragmentu ────────────────────────────
# ══════════════════════════════════════════════════════════
menu_cut() {
    echo ""
    echo -e "${BOLD}Wycinanie fragmentu:${NC}"
    echo "  1) Od—Do  (np. 00:01:30 do 00:04:00) — szybko, bez re-enkodowania"
    echo "  2) Od—Do  (dokładne, z re-enkodowaniem)"
    echo "  3) Pierwsze N sekund"
    echo "  4) Ostatnie N sekund"
    echo "  0) ← Powrót"
    echo ""
    ask "Wybór: "
    read -r choice

    case "$choice" in
        1)
            ask "Czas START (np. 00:01:30 lub 90): "
            read -r start_time
            ask "Czas KONIEC (np. 00:04:00 lub 240): "
            read -r end_time
            get_output_file "${INPUT_EXT}"
            run_cmd "ffmpeg -ss ${start_time} -to ${end_time} -i \"$INPUT_FILE\" -c copy -y \"$OUTPUT_FILE\""
            ;;
        2)
            ask "Czas START: "
            read -r start_time
            ask "Czas KONIEC: "
            read -r end_time
            get_output_file "mp4"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -ss ${start_time} -to ${end_time} -c:v libx264 -crf 23 -c:a aac -y \"$OUTPUT_FILE\""
            ;;
        3)
            ask "Ile pierwszych sekund? "
            read -r secs
            get_output_file "${INPUT_EXT}"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -t ${secs} -c copy -y \"$OUTPUT_FILE\""
            ;;
        4)
            ask "Ile ostatnich sekund? "
            read -r secs
            get_output_file "${INPUT_EXT}"
            run_cmd "ffmpeg -sseof -${secs} -i \"$INPUT_FILE\" -c copy -y \"$OUTPUT_FILE\""
            ;;
        0) return ;;
        *) warn "Nieznana opcja" ;;
    esac
}

# ══════════════════════════════════════════════════════════
# ── MENU: Ekstrakcja audio z wideo ───────────────────────
# ══════════════════════════════════════════════════════════
menu_extract_audio() {
    echo ""
    echo -e "${BOLD}Wyciągnij audio z wideo:${NC}"
    echo "  1) MP3 320k"
    echo "  2) MP3 192k"
    echo "  3) AAC (kopia bez re-enkodowania — instant)"
    echo "  4) WAV (bezstratny)"
    echo "  5) FLAC (bezstratny skompresowany)"
    echo "  0) ← Powrót"
    echo ""
    ask "Wybór: "
    read -r choice

    case "$choice" in
        1) get_output_file "mp3";  run_cmd "ffmpeg -i \"$INPUT_FILE\" -vn -c:a libmp3lame -b:a 320k -y \"$OUTPUT_FILE\"" ;;
        2) get_output_file "mp3";  run_cmd "ffmpeg -i \"$INPUT_FILE\" -vn -c:a libmp3lame -b:a 192k -y \"$OUTPUT_FILE\"" ;;
        3) get_output_file "aac";  run_cmd "ffmpeg -i \"$INPUT_FILE\" -vn -c:a copy -y \"$OUTPUT_FILE\"" ;;
        4) get_output_file "wav";  run_cmd "ffmpeg -i \"$INPUT_FILE\" -vn -c:a pcm_s16le -y \"$OUTPUT_FILE\"" ;;
        5) get_output_file "flac"; run_cmd "ffmpeg -i \"$INPUT_FILE\" -vn -c:a flac -y \"$OUTPUT_FILE\"" ;;
        0) return ;;
        *) warn "Nieznana opcja" ;;
    esac
}

# ══════════════════════════════════════════════════════════
# ── MENU: Konwersja obrazów ──────────────────────────────
# ══════════════════════════════════════════════════════════
menu_convert_image() {
    echo ""
    echo -e "${BOLD}Konwersja obrazu:${NC}"
    echo "  1) → JPG"
    echo "  2) → PNG"
    echo "  3) → WebP"
    echo "  4) → BMP"
    echo "  5) Zmień rozdzielczość (podajesz szerokość)"
    echo "  0) ← Powrót"
    echo ""
    ask "Wybór: "
    read -r choice

    case "$choice" in
        1)
            get_output_file "jpg"
            ask "Jakość JPG (2=najlepsza, 31=najgorsza) [5]: "
            read -r q; q="${q:-5}"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -q:v ${q} -y \"$OUTPUT_FILE\""
            ;;
        2) get_output_file "png";  run_cmd "ffmpeg -i \"$INPUT_FILE\" -y \"$OUTPUT_FILE\"" ;;
        3)
            get_output_file "webp"
            ask "Jakość WebP (0-100) [85]: "
            read -r q; q="${q:-85}"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -quality ${q} -y \"$OUTPUT_FILE\""
            ;;
        4) get_output_file "bmp";  run_cmd "ffmpeg -i \"$INPUT_FILE\" -y \"$OUTPUT_FILE\"" ;;
        5)
            ask "Nowa szerokość w px (wysokość auto): "
            read -r new_w
            get_output_file "${INPUT_EXT}"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -vf \"scale=${new_w}:-1\" -y \"$OUTPUT_FILE\""
            ;;
        0) return ;;
        *) warn "Nieznana opcja" ;;
    esac
}

# ══════════════════════════════════════════════════════════
# ── MENU: Szybkie info ───────────────────────────────────
# ══════════════════════════════════════════════════════════
menu_info() {
    echo ""
    echo -e "${BOLD}Szczegółowe info o pliku:${NC}"
    divider
    ffprobe -hide_banner "$INPUT_FILE" 2>&1
    divider
    echo ""
    ask "Naciśnij Enter..."
    read -r
}

# ══════════════════════════════════════════════════════════
# ── MENU: Inne / ekstra ─────────────────────────────────
# ══════════════════════════════════════════════════════════
menu_extras() {
    echo ""
    echo -e "${BOLD}Ekstra:${NC}"
    echo "  1) Screenshot z konkretnej sekundy"
    echo "  2) Screenshoty co N sekund"
    echo "  3) Usuń audio z wideo (zostaw ciche wideo)"
    echo "  4) Zmień FPS"
    echo "  5) Obróć wideo (90° w prawo)"
    echo "  6) Odbicie lustrzane"
    echo "  7) Czarno-biały"
    echo "  8) Normalizuj głośność"
    echo "  9) Odwróć wideo (tyłem)"
    echo "  0) ← Powrót"
    echo ""
    ask "Wybór: "
    read -r choice

    case "$choice" in
        1)
            ask "W której sekundzie? (np. 00:00:30 lub 30): "
            read -r ss_time
            get_output_file "png"
            run_cmd "ffmpeg -ss ${ss_time} -i \"$INPUT_FILE\" -frames:v 1 -y \"$OUTPUT_FILE\""
            ;;
        2)
            ask "Co ile sekund? [5]: "
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
            ask "Nowy FPS [30]: "
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
            warn "To wymaga załadowania całego pliku do RAM — duże pliki mogą się nie zmieścić!"
            run_cmd "ffmpeg -i \"$INPUT_FILE\" -vf \"reverse\" -af \"areverse\" -y \"$OUTPUT_FILE\""
            ;;
        0) return ;;
        *) warn "Nieznana opcja" ;;
    esac
}


# ══════════════════════════════════════════════════════════
# ── GŁÓWNE MENU ──────────────────────────────────────────
# ══════════════════════════════════════════════════════════
main() {
    # Argument z linii komend?
    if [[ -n "${1:-}" ]]; then
        INPUT_FILE="$1"
        if [[ ! -f "$INPUT_FILE" ]]; then
            error "Plik '$INPUT_FILE' nie istnieje!"
            exit 1
        fi
    fi

    INPUT_FILE="${INPUT_FILE:-}"
    FILE_TYPE=""
    INPUT_EXT=""

    while true; do
        banner

        if [[ -n "$INPUT_FILE" ]]; then
            echo -e "  Plik: ${GREEN}${INPUT_FILE}${NC}"
            echo ""
        fi

        echo -e "${BOLD}  Co chcesz zrobić?${NC}"
        echo ""
        echo "  1) 🔄  Konwersja wideo"
        echo "  2) 🎵  Konwersja audio"
        echo "  3) 🖼️   Konwersja obrazu"
        echo "  4) 📦  Kompresja (zmniejsz rozmiar)"
        echo "  5) ⏩  Zmiana prędkości"
        echo "  6) ✂️   Wytnij fragment"
        echo "  7) 🔊  Wyciągnij audio z wideo"
        echo "  8) 📊  Info o pliku"
        echo "  9) 🧰  Ekstra (screenshoty, obrót, FPS...)"
        echo ""
        echo "  f)     Zmień plik wejściowy"
        echo "  q)     Wyjście"
        echo ""
        ask "Wybór: "
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
                info "Do zobaczenia! 👋"
                exit 0
                ;;
            *)
                warn "Nieznana opcja"
                sleep 1
                ;;
        esac

        echo ""
        ask "Naciśnij Enter aby wrócić do menu..."
        read -r
    done
}

main "$@"
