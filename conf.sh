# ============================================
# Perbaikan thumbnail ytfzf
# ============================================

# 1. Gunakan chafa sebagai default thumbnail viewer
thumbnail_viewer="chafa"

# 2. Gunakan resolusi thumbnail tertinggi (opsional)
thumbnail_quality="maxres"

# 3. Override download_thumbnails: tambahkan header User-Agent & Referer
download_thumbnails() {
    [ "$skip_thumb_download" -eq 1 ] && {
        print_info "Skipping thumbnail download"
        return 0
    }
    [ "$async_thumbnails" -eq 0 ] && print_info "Fetching thumbnails...${new_line}"
    curl_config_file="${session_temp_dir}/curl_config"
    [ -z "$*" ] && return 0
    : >"$curl_config_file"
    for line in "$@"; do
        printf "url=\"%s\"\noutput=\"$thumb_dir/%s.jpg\"\n" "${line%%';'*}" "${line##*';'}"
    done >>"$curl_config_file"
    curl -fLZ -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
         -H "Referer: https://www.youtube.com/" \
         -K "$curl_config_file"
    [ $? -eq 2 ] && curl -fL -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
         -H "Referer: https://www.youtube.com/" \
         -K "$curl_config_file"
}
