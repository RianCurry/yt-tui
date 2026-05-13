#!/usr/bin/env bash
set -euo pipefail

# ============================================
# Konfigurasi
# ============================================
MAX_RESULTS=10
THUMB_SIZE="50x25"         # Lebar x Tinggi (sesuaikan dengan terminal)
THUMB_DIR=$(mktemp -d -t yttui-thumbs-XXXX)
JSON_FILE=$(mktemp -t yttui-json-XXXX)
PREVIEW_SCRIPT=$(mktemp -t yttui-preview-XXXX)
ERROR_LOG=$(mktemp -t yttui-error-XXXX)
trap 'rm -rf "$THUMB_DIR" "$JSON_FILE" "$PREVIEW_SCRIPT" "$ERROR_LOG"' EXIT

# Cek dependensi
for cmd in yt-dlp jq fzf mpv chafa curl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: $cmd tidak ditemukan. Install terlebih dahulu." >&2
        exit 1
    fi
done

# Warna untuk output (ANSI)
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_RED='\033[31m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_BLUE='\033[34m'
C_MAGENTA='\033[35m'
C_CYAN='\033[36m'

# ============================================
# Input Pencarian
# ============================================
if [ $# -eq 0 ]; then
    read -r -p "🔍 Cari video YouTube: " query
else
    query="$*"
fi

if [ -z "$query" ]; then
    echo -e "${C_RED}❌ Query kosong.${C_RESET}" >&2
    exit 1
fi

echo -e "${C_CYAN}⏳ Mencari '$query'...${C_RESET}" >&2

# ============================================
# Ambil Metadata Video (flat playlist, cepat)
# ============================================
yt-dlp \
    --flat-playlist \
    --dump-json \
    --playlist-end "$MAX_RESULTS" \
    "ytsearch${MAX_RESULTS}:${query}" \
    > "$JSON_FILE" 2>"$ERROR_LOG"

exit_code=$?

if [ $exit_code -ne 0 ] || [ ! -s "$JSON_FILE" ]; then
    echo -e "${C_RED}❌ Pencarian gagal.${C_RESET}" >&2
    [ -s "$ERROR_LOG" ] && cat "$ERROR_LOG" >&2
    exit 1
fi

# Bersihkan JSON dari baris non-objek
jq -c 'select(type == "object")' "$JSON_FILE" > "${JSON_FILE}.clean"
mv "${JSON_FILE}.clean" "$JSON_FILE"

if [ ! -s "$JSON_FILE" ]; then
    echo -e "${C_RED}❌ Tidak ada hasil valid.${C_RESET}" >&2
    exit 1
fi

# Hitung jumlah hasil
result_count=$(jq -s 'length' "$JSON_FILE")

# ============================================
# Unduh Thumbnail (ID dari URL i.ytimg.com)
# ============================================
jq -r '.id' "$JSON_FILE" | while read -r id; do
    for quality in maxresdefault hqdefault mqdefault; do
        if curl -sfL "https://i.ytimg.com/vi/${id}/${quality}.jpg" -o "$THUMB_DIR/$id.jpg" 2>/dev/null; then
            break
        fi
    done
done

# ============================================
# Skrip Preview untuk fzf (TAMPILAN KAYA)
# ============================================

cat > "$PREVIEW_SCRIPT" << 'PREVIEW_EOF'
#!/usr/bin/env bash
line="$1"
THUMB_DIR="$2"
JSON_FILE="$3"
id=$(echo "$line" | cut -d'|' -f1 | tr -d ' ')

# --- Detail Video (JSON) - ditampilkan terlebih dahulu ---
jq -r --arg id "$id" '
    select(.id == $id) |
    # Judul (tebal + biru)
    "\u001b[1;34m\(.title // "Tanpa judul")\u001b[0m\n\n" +
    
    # Channel (cyan)
    "\u001b[36m👤 \(.channel // "Tidak diketahui")\u001b[0m\n" +
    
    # Upload date (format ulang)
    "📅 Upload: \(
        if .upload_date then
            (.upload_date[:4] // "????") + "-" + (.upload_date[4:6] // "??") + "-" + (.upload_date[6:8] // "??")
        else
            "????-??-??"
        end
    )\n" +
    
    # Durasi (hijau)
    "\u001b[32m⏱️  Durasi: \(
        if .duration then
            (if .duration >= 3600 then
                ((.duration/3600 | floor | tostring) + ":" +
                 ((.duration%3600)/60 | floor | tostring | if length==1 then "0"+. else . end) + ":" +
                 ((.duration%60 | floor | tostring | if length==1 then "0"+. else . end))
                )
            elif .duration >= 60 then
                ((.duration/60 | floor | tostring) + ":" +
                 ((.duration%60 | floor | tostring | if length==1 then "0"+. else . end))
                )
            else
                ("0:" + (.duration | floor | tostring | if length==1 then "0"+. else . end))
            end)
        else
            "N/A"
        end
    )\u001b[0m\n" +
    
    # View count (jika ada)
    (if .view_count then "\u001b[33m👁️  Penonton: \(.view_count | tostring)\u001b[0m\n" else "" end) +
    
    # Like count (jika ada)
    (if .like_count then "\u001b[33m👍 Like: \(.like_count | tostring)\u001b[0m\n" else "" end) +
    
    # Deskripsi (potong 150 karakter)
    (if .description then
        "\n\u001b[90m📝 Deskripsi:\u001b[0m\n" +
        (.description[0:150] // "") + (if (.description | length) > 150 then "…" else "" end)
    else "" end)
' "$JSON_FILE"

# Garis pemisah setelah deskripsi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# --- Thumbnail via chafa - ditampilkan di paling bawah ---
if [ -f "$THUMB_DIR/$id.jpg" ]; then
    chafa --size="${THUMB_SIZE:-40x20}" --fill=block "$THUMB_DIR/$id.jpg" 2>/dev/null || echo "(Thumbnail error)"
else
    echo "(Thumbnail tidak tersedia)"
fi
PREVIEW_EOF


chmod +x "$PREVIEW_SCRIPT"

# Export variabel yang dibutuhkan preview script
export THUMB_SIZE

# ============================================
# Daftar untuk fzf (tampilan sederhana di kiri)
# ============================================
list=$(jq -r '
    select(type == "object") 
    .id as $id |
    .title // "Tanpa judul" as $title |
    # Format durasi seperti di atas
    (if .duration then
        (if .duration >= 3600 then
            ((.duration/3600 | floor | tostring) + ":" +
             ((.duration%3600)/60 | floor | tostring | if length==1 then "0"+. else . end) + ":" +
             ((.duration%60 | floor | tostring | if length==1 then "0"+. else . end))
            )
        elif .duration >= 60 then
            ((.duration/60 | floor | tostring) + ":" +
             ((.duration%60 | floor | tostring | if length==1 then "0"+. else . end))
            )
        else
            ("0:" + (.duration | floor | tostring | if length==1 then "0"+. else . end))
        end)
    else
        "N/A"
    end) as $dur |
    "\($id) | \($title) [\($dur)]"
' "$JSON_FILE")

if [ -z "$list" ]; then
    echo -e "${C_RED}❌ Tidak ada data yang bisa ditampilkan.${C_RESET}" >&2
    exit 1
fi

# ============================================
# Tampilkan fzf (TUI Utama)
# ============================================
selected=$(echo "$list" | fzf \
    --delimiter='|' \
    --with-nth=2 \
    --preview="'$PREVIEW_SCRIPT' {} '$THUMB_DIR' '$JSON_FILE'" \
    --preview-window=right:55%:wrap:border-rounded \
    --preview-label=" Detail Video " \
    --header="🔎  Pencarian: \"$query\"  |  Hasil: $result_count video  |  Pilih lalu Enter" \
    --header-lines=0 \
    --bind="enter:accept" \
    --color="header:bold:yellow,preview-label:bold:blue" \
    2>/dev/null || true)

if [ -z "$selected" ]; then
    echo -e "${C_RED}❌ Tidak ada yang dipilih.${C_RESET}" >&2
    exit 0
fi

id=$(echo "$selected" | cut -d'|' -f1 | tr -d ' ')
title=$(echo "$selected" | cut -d'|' -f2- | sed 's/^ *//;s/ \[.*//')

# ============================================
# Pilih Mode Putar
# ============================================
echo -e "\n${C_BOLD}Pilih mode putar untuk:${C_RESET} ${C_GREEN}$title${C_RESET}"
echo -e "  ${C_CYAN}[v]${C_RESET} Video (default)"
echo -e "  ${C_YELLOW}[a]${C_RESET} Audio saja"
read -r -p "Pilihan (v/a): " choice
case "$choice" in
    a|A) mode="audio" ;;
    *)   mode="video" ;;
esac

url="https://www.youtube.com/watch?v=$id"
echo -e "${C_MAGENTA}▶️  Memutar: ${C_BOLD}$title${C_RESET} (mode: $mode)${C_RESET}"
if [ "$mode" = "audio" ]; then
    yt-dlp -f bestaudio --no-playlist -o - "$url" | mpv --no-video -
else
    yt-dlp -f bestvideo+bestaudio/best --no-playlist -o - "$url" | mpv -
fi
