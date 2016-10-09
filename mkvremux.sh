#!/bin/bash

#
# Requirements.
#
hash mkvinfo 2>/dev/null || { echo "Package not found: mkvtoolnix"; exit 1; }
hash mkvmerge 2>/dev/null || { echo "Package not found: mkvtoolnix"; exit 1; }
hash avconv 2>/dev/null || { echo "Package not found: libav-tools"; exit 1; }

#
# Variables.
#
PROCESSED=0
QUALITY=1
SCRIPT_PATH=`pwd`
TESTRUN=0
VERBOSE=0

#
# Options
#
while getopts ":qtv" opt; do
    case $opt in
        q)
            QUALITY=0
            ;;
        t)
            TESTRUN=1
            ;;
        v)
            VERBOSE=1
            ;;
        \?)
            echo "mkvremux [qtv] DIR"
            exit 1
    esac
done

shift "$((OPTIND-1))"

#
# Arguments.
#
DIR=$(echo "$1" | tr -s /); DIR=${DIR%/}

if [[ "$DIR" != /* ]]; then
    DIR="$SCRIPT_PATH/$DIR"
fi

if [ ! -d "$DIR" ]; then
    echo "Not a directory: $DIR"
    exit 1
fi

#
# Functions.
#
function bad_quality(){

    local INFO="$1"
    local BAD=0

    if (( "$(grep -c "Track type: video" "$INFO")" > 1 )) ||
       (( "$(grep -c "h.264" "$INFO")" == 0 )) ||
       (( "$(grep -c "Pixel width: 19" "$INFO")" == 0 )); then
        return 0
    fi

    if (( "$(grep -c "Track type: audio" "$INFO")" < 2 )) ||
       (( "$(grep -c "Channels: [1,2,3,4]" "$INFO")" > 0 )); then
        return 0
    fi

    return 1
}

function cleanup(){

    local BASE="$1"

    [ $TESTRUN -eq 0 ] && rm "$BASE/"*.tmp
}

function convert_audio_tracks(){

    local BASE="$1"

    if [ ! -f "$BASE/audio.ger.ac3.tmp" ] &&
       [ -f "$BASE/audio.ger.org.tmp" ]; then
        [ $TESTRUN -eq 0 ] && avconv -i "$BASE/audio.ger.org.tmp" -aq 448k -f ac3 "$BASE/audio.ger.ac3.tmp" < /dev/null
        [ $TESTRUN -eq 1 ] && touch "$BASE/audio.ger.ac3.tmp"
        [ $VERBOSE -eq 1 ] && echo "convert audio (ger, $BASE/audio.ger.org.tmp to $BASE/audio.ger.ac3.tmp"
    fi

    if [ ! -f "$BASE/audio.eng.ac3.tmp" ] &&
       [ -f "$BASE/audio.eng.org.tmp" ]; then
        [ $TESTRUN -eq 0 ] && avconv -i "$BASE/audio.eng.org.tmp" -aq 448k -f ac3 "$BASE/audio.eng.ac3.tmp" < /dev/null
        [ $TESTRUN -eq 1 ] && touch "$BASE/audio.eng.ac3.tmp"
        [ $VERBOSE -eq 1 ] && echo "convert audio (eng, $BASE/audio.eng.org.tmp to $BASE/audio.eng.ac3.tmp"
    fi
}

function crawl_tracks(){

    local BASE="$1"
    local INFO="$2"
    local TRACKS="$3"

    local ID=-1
    local TYPE="und"
    local LANGUAGE="und"
    local TMPDUR="und"

    if [ -f "$TRACKS" ]; then
        [ $VERBOSE -eq 1 ] && echo "$TRACKS already exists - do not crawl again"
        return 0
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do

        if grep -s -q "video=" "$TRACKS" &&
           grep -s -q "audio_eng=" "$TRACKS" &&
           grep -s -q "audio_ger=" "$TRACKS"; then
            break
        fi

        if [[ "$line" = $(echo "| + A track") ]] ||
           [[ "$line" = $(echo "|+ *") ]]; then

            if [ "$TYPE" = "vid" ] &&
               ! grep -s -q "video=" "$TRACKS"; then
                echo "video=$ID" >> "$TRACKS"
                [ $VERBOSE -eq 1 ] && echo "write 'video=$ID' to $TRACKS"
            fi

            if [ "$TYPE" = "aud" ] &&
               ( [ "$LANGUAGE" = "eng" ] || [ "$LANGUAGE" = "und" ] ) &&
               ! grep -s -q "audio_eng=" "$TRACKS"; then
                echo "audio_eng=$ID" >> "$TRACKS"
                [ $VERBOSE -eq 1 ] && echo "write 'audio_eng=$ID' to $TRACKS"
            fi

            if [ "$TYPE" = "aud" ] &&
               [ "$LANGUAGE" = "ger" ] &&
               ! grep -s -q "audio_ger=" "$TRACKS"; then
                echo "audio_ger=$ID" >> "$TRACKS"
                [ $VERBOSE -eq 1 ] && echo "write 'audio_ger=$ID' to $TRACKS"
            fi

            if [ "$TYPE" = "vid" ] &&
               [ "$TMPDUR" != "und" ] &&
               ! grep -s -q "def_dur=" "$TRACKS"; then
                echo "def_dur=$TMPDUR" >> "$TRACKS"
                [ $VERBOSE -eq 1 ] && echo "write 'video_dur=$TMPDUR' to $TRACKS"
            fi

            TYPE="und"
            LANGUAGE="und"
            TMPDUR="und"
        fi

        [ $VERBOSE -eq 1 ] && echo "$line"

        if [[ "$line" = $(echo "| + A track") ]]; then
            ID=$[$ID+1]
            [ $VERBOSE -eq 1 ] && echo "found track $ID"
        fi

        if [[ "$line" = $(echo "*Track type: video*") ]]; then
            TYPE="vid"
            [ $VERBOSE -eq 1 ] && echo "found type video"
        fi

        if [[ "$line" = $(echo "*Track type: audio*") ]]; then
            TYPE="aud"
            [ $VERBOSE -eq 1 ] && echo "found type audio"
        fi

        if [[ "$line" = $(echo "*Language: eng*") ]] ||
           [[ "$line" = $(echo "*Name:*Eng*") ]]; then
            LANGUAGE="eng"
            [ $VERBOSE -eq 1 ] && echo "found lang eng"
        fi

        if [[ "$line" = $(echo "*Language: ger*") ]] ||
           [[ "$line" = $(echo "*Name:*Ger*") ]]; then
            LANGUAGE="ger"
            [ $VERBOSE -eq 1 ] && echo "found lang ger"
        fi

        if [[ "$line" = $(echo "*Language:*") ]] &&
           [ $LANGUAGE = "und" ]; then
            LANGUAGE="ignore"
            [ $VERBOSE -eq 1 ] && echo "found unknown lang"
        fi

        if [[ "$line" = $(echo "*Default duration:*") ]]; then
            TMPDUR=$(echo "$line" | grep -oP "[0-9.]+ms")
            [ $VERBOSE -eq 1 ] && echo "found duration $TMPDUR"
        fi

    done < "$INFO"
}

function extract_tracks(){

    local BASE="$1"
    local MKV="$2"
    local VIDEO="$3"
    local AUDIO_ENG="$4"
    local AUDIO_GER="$5"

    if [ $VIDEO != "und" ] &&
       [ ! -f "$BASE/video.h264.tmp" ]; then
        [ $TESTRUN -eq 0 ] && mkvextract tracks "$MKV" "$VIDEO:$BASE/video.h264.tmp"
        [ $TESTRUN -eq 1 ] && touch "$BASE/video.h264.tmp"
        [ $VERBOSE -eq 1 ] && echo "extract video (track $VIDEO, to $BASE/video.h264.tmp)"
    fi

    if [ $AUDIO_ENG != "und" ] &&
       [ ! -f "$BASE/audio.eng.org.tmp" ]; then
        [ $TESTRUN -eq 0 ] && mkvextract tracks "$f" "$AUDIO_ENG:$BASE/audio.eng.org.tmp"
        [ $TESTRUN -eq 1 ] && touch "$BASE/audio.eng.org.tmp"
        [ $VERBOSE -eq 1 ] && echo "extract audio (eng, track $AUDIO_ENG, to $BASE/audio.eng.org.tmp)"
    fi

    if [ $AUDIO_GER != "und" ] &&
       [ ! -f "$BASE/audio.ger.org.tmp" ]; then
        [ $TESTRUN -eq 0 ] && mkvextract tracks "$f" "$AUDIO_GER:$BASE/audio.ger.org.tmp"
        [ $TESTRUN -eq 1 ] && touch "$BASE/audio.ger.org.tmp"
        [ $VERBOSE -eq 1 ] && echo "extract audio (ger, track $AUDIO_GER, to $BASE/audio.ger.org.tmp)"
    fi
}

function remux(){

    local BASE="$1"
    local MKV="$2"
    local DEFDUR="$3"
    local CMD="mkvmerge -o \"$MKV\" --default-language eng"

    [ $TESTRUN -eq 0 ] && mv "$f" "$f.bkp"

    if [ $DEFDUR != "und" ]; then
        CMD+=" --default-duration \"0:$DEFDUR\""
    fi

    if [ -f "$BASE/video.h264.tmp" ];then
        CMD+=" \"$BASE/video.h264.tmp\""
    fi

    if [ -f "$BASE/audio.eng.ac3.tmp" ];then
        CMD+=" --default-track 0:0 --language 0:eng \"$BASE/audio.eng.ac3.tmp\""
    fi

    if [ -f "$BASE/audio.ger.ac3.tmp" ];then
        CMD+=" --default-track 0:1 --language 0:ger \"$BASE/audio.ger.ac3.tmp\""
    fi

    [ $TESTRUN -eq 0 ] && eval "$CMD"
    [ $TESTRUN -eq 1 ] && echo "$CMD"
}

function tracks_missing(){

    local VIDEO="$1"
    local AUDIO_ENG="$2"
    local AUDIO_GER="$3"

    if [ $VIDEO = "und" ]; then
        return 0
    fi

    if [ $QUALITY -eq 1 ] &&
       ( [ $AUDIO_ENG = "und" ] ||
         [ $AUDIO_GER = "und" ]
       ); then
        return 0
    fi

    if [ $AUDIO_ENG = "und" ] &&
       [ $AUDIO_GER = "und" ]; then
        return 0
    fi

    return 1
}

#
# Main.
#
while IFS= read -r -d '' f; do

    BASE=$(dirname "$f")
    INFO="$BASE/mkvinfo.tmp"
    TRACKS="$BASE/tracks.tmp"

    echo "Processing $f"
    PROCESSED=$[PROCESSED + 1]

    if [ ! -f "$INFO" ]; then
        mkvinfo -r "$INFO" "$f"
    fi

    if [ $QUALITY -eq 1 ] &&
       bad_quality "$INFO"; then
        [ $VERBOSE -eq 1 ] && echo "Skipped $f - bad quality"
        continue
    fi

    crawl_tracks "$BASE" "$INFO" "$TRACKS"

    typeset -A CONFIG
    CONFIG=(
        [video]="und"
        [def_dur]="und"
        [audio_eng]="und"
        [audio_ger]="und"
    )

    while read line
    do
        if echo $line | grep -F = &>/dev/null
        then
            KEY=$(echo "$line" | cut -d '=' -f 1)
            if [ -n "${CONFIG[$KEY] + 1}" ]; then
                CONFIG[$KEY]=$(echo "$line" | cut -d '=' -f 2-)
            fi
        fi
    done < "$TRACKS"

    if tracks_missing "${CONFIG[video]}" "${CONFIG[audio_eng]}" "${CONFIG[audio_ger]}"; then
        [ $VERBOSE -eq 1 ] && echo "Skipped $f - needed tracks not found"
        continue
    fi

    extract_tracks "$BASE" "$f" "${CONFIG[video]}" "${CONFIG[audio_eng]}" "${CONFIG[audio_ger]}"
    convert_audio_tracks "$BASE"
    remux "$BASE" "$f" "${CONFIG[def_dur]}"
    cleanup "$BASE"

done < <(find "$DIR" -type f -name "*.mkv" -print0)

if [ $PROCESSED = 0 ]; then
    echo "Nothing to do"
    exit 0
fi

echo "Processed $PROCESSED file(s) - done"
exit 0