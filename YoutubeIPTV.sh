#!/bin/bash

# Script para criar playlists IPTV a partir de vídeos ou playlists do YouTube.
# Ignora vídeos deletados ou protegidos, implementa cancelamento imediato e limpa arquivos temporários.

# Pergunta ao usuário se deseja processar um Link Único ou uma Playlist
opcao=$(zenity --list --title="Escolha o Tipo de Link" \
    --text="Selecione se deseja processar um link único ou uma playlist:" \
    --radiolist --column="Selecionado" --column="Opção" \
    TRUE "Link Único" FALSE "Playlist")

if [ -z "$opcao" ]; then
    zenity --error --title="Erro" --text="Nenhuma opção selecionada. O script será encerrado."
    exit 1
fi

# Solicita o link do YouTube
link=$(zenity --entry --title="Insira o Link do YouTube" --text="Digite o URL do vídeo ou playlist do YouTube:")

if [ -z "$link" ]; then
    zenity --error --title="Erro" --text="Nenhum link foi fornecido. O script será encerrado."
    exit 1
fi

# Função para verificar se o link da playlist é válido
verificar_playlist() {
    local url="$1"
    if [[ "$url" != *"list="* ]]; then
        zenity --error --title="Erro" --text="O link da playlist fornecido é inválido.\nFormato correto:\nhttps://www.youtube.com/playlist?list=ID_DA_PLAYLIST"
        exit 1
    fi
}

# Se for uma playlist, verifica a validade do link
if [ "$opcao" == "Playlist" ]; then
    verificar_playlist "$link"
fi

# Solicita a categoria
categoria=$(zenity --entry --title="Categoria" --text="Digite o nome da categoria (exemplo: RANGEL):" --entry-text="WEB TV VINTAGE")
[ -z "$categoria" ] && categoria="WEB TV VINTAGE"

# Local para salvar o arquivo
output_file=$(zenity --file-selection --save --confirm-overwrite --title="Escolha o Local para Salvar o Arquivo .m3u" --filename="playlist_iptv.m3u")
if [ -z "$output_file" ]; then
    zenity --error --title="Erro" --text="Nenhum local foi selecionado. O script será encerrado."
    exit 1
fi

# Cria o cabeçalho do arquivo .m3u
echo "#EXTM3U" > "$output_file"

# Variável de controle de cancelamento
cancelado=false

# Função para processar vídeo único
processar_video_unico() {
    local video_url="$1"
    local titulo
    local stream_url

    if $cancelado; then return; fi

    # Verifica se o vídeo está disponível
    titulo=$(yt-dlp --get-title "$video_url" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$titulo" ]; then
        echo "DEBUG: Vídeo indisponível ou protegido: $video_url"
        return
    fi

    # Obtém o stream combinado (vídeo + áudio)
    stream_url=$(yt-dlp -f "best[ext=mp4]/bestvideo[ext=mp4]+bestaudio[ext=m4a]/best" -g "$video_url" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$stream_url" ]; then
        echo "DEBUG: Falha ao obter stream: $video_url"
        return
    fi

    # Adiciona ao arquivo M3U
    echo "#EXTINF:-1 tvg-id=\"ext\" tvg-name=\"$titulo\" group-title=\"$categoria\",$titulo" >> "$output_file"
    echo "$stream_url" >> "$output_file"
}

# Função para processar playlist
processar_playlist() {
    echo "DEBUG: Processando playlist: $link"

    # Obtém todos os links dos vídeos da playlist
    yt-dlp --flat-playlist --print-to-file "url" urls_temp.txt "$link" 2>/dev/null
    if [ $? -ne 0 ]; then
        echo "DEBUG: Falha ao processar a playlist."
        rm -f urls_temp.txt
        exit 1
    fi

    total_videos=$(wc -l < urls_temp.txt)
    current_video=0

    # Barra de progresso com cancelamento imediato
    (
        while read -r video_url; do
            if $cancelado; then break; fi
            ((current_video++))
            echo "$((current_video * 100 / total_videos))"  # Atualiza a porcentagem
            echo "# Processando vídeo $current_video de $total_videos..."
            processar_video_unico "$video_url"
        done < urls_temp.txt
    ) | zenity --progress --title="Processando Playlist" --text="Preparando vídeos..." --percentage=0 --auto-close --auto-kill || cancelado=true

    # Remove o arquivo temporário mesmo se cancelado
    rm -f urls_temp.txt
    if $cancelado; then
        echo "DEBUG: Processamento cancelado pelo usuário."
        exit 1
    fi
}

# Executa a opção escolhida
if [ "$opcao" == "Link Único" ]; then
    ( echo "50" ; echo "# Processando vídeo único..." ; processar_video_unico "$link" ) | \
    zenity --progress --title="Processando Vídeo" --text="Preparando..." --percentage=0 --auto-close --auto-kill || cancelado=true
else
    processar_playlist
fi

# Verificação final
if $cancelado; then
    zenity --warning --title="Cancelado" --text="O processamento foi interrompido."
    exit 1
fi

if [ -s "$output_file" ]; then
    zenity --info --title="Sucesso" --text="Arquivo .m3u gerado com sucesso:\n$output_file"
else
    zenity --error --title="Erro" --text="O arquivo .m3u está vazio. Algo deu errado."
    exit 1
fi
