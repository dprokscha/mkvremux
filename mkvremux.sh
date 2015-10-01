#!/bin/bash

hash mkvinfo 2>/dev/null || { echo "Package not found: mkvtoolnix"; exit 1; }
hash mkvmerge 2>/dev/null || { echo "Package not found: mkvtoolnix"; exit 1; }
hash avconv 2>/dev/null || { echo "Package not found: libav-tools"; exit 1; }

DIR=$(echo "$1" | tr -s /); DIR=${DIR%/}
SCRIPT_PATH=`pwd`
ERR=()

if [[ "$DIR" != /* ]]; then
    DIR="$SCRIPT_PATH/$DIR"
fi

if [ ! -d "$DIR" ]; then
    echo "Not found: $DIR"
    exit 1
fi

while IFS= read -r -d '' f; do
    BASE=$(dirname "$f")
    INFO="$BASE/mkvinfo.tmp"

    echo "Processing: $f"
    mkvinfo -r "$INFO" "$f"

    if (( "$(grep -c "Track type: video" "$INFO")" > 1 )) ||
       (( "$(grep -c "h.264" "$INFO")" == 0 )) ||
       (( "$(grep -c "Pixel width: 19" "$INFO")" == 0 )); then
        ERR+=("$f (too many video tracks or bad video quality)")
        rm "$BASE"/*.tmp
        continue
    fi

    if (( "$(grep -c "Track type: audio" "$INFO")" < 2 )) ||
       (( "$(grep -c "Channels: [1,2,3,4]" "$INFO")" > 0 )); then
        ERR+=("$f (not enough audio tracks found or bad audio quality)")
        rm "$BASE"/*.tmp
        continue
    fi

    ID=-1
    LANGUAGE="und"
    TYPE="und"
    DEFID=-1
    DEFAUD=-1
    DEFDUR="und"
    TMPDUR="und"

    while IFS= read -r line || [[ -n "$line" ]]; do

        if [ -f "$BASE/video.h264.tmp" ] &&
           [ -f "$BASE/audio.eng.org.tmp" ] &&
           [ -f "$BASE/audio.ger.org.tmp" ]; then
            break
        fi

        if [[ "$line" = $(echo "| + A track") ]] ||
           [[ "$line" = $(echo "|+ *") ]]; then

            if [ "$TYPE" = "vid" ] &&
               [ ! -f "$BASE/video.h264.tmp" ]; then
                mkvextract tracks "$f" "$ID:$BASE/video.h264.tmp"
            fi

            if [ "$TYPE" = "aud" ] &&
               [ "$LANGUAGE" = "eng" ] &&
               [ ! -f "$BASE/audio.eng.org.tmp" ]; then
                mkvextract tracks "$f" "$ID:$BASE/audio.eng.org.tmp"
            fi

            if [ "$TYPE" = "aud" ] &&
               [ "$LANGUAGE" = "ger" ] &&
               [ ! -f "$BASE/audio.ger.org.tmp" ]; then
                mkvextract tracks "$f" "$ID:$BASE/audio.ger.org.tmp"
            fi

            if [ "$TYPE" = "vid" ] &&
               [ "$TMPDUR" != "und" ]; then
                DEFDUR=$TMPDUR
            fi

            if [ "$TYPE" = "aud" ] &&
               (( "$DEFID" >= 0 )); then
                DEFAUD=$DEFID
            fi

            DEFID=-1
            LANGUAGE="und"
            TYPE="und"
            TMPDUR="und"
        fi

        if [[ "$line" = $(echo "| + A track") ]]; then
            ID=$[$ID+1]
        fi

        if [[ "$line" = $(echo "*Default flag: 0*") ]]; then
            DEFID=$ID
        fi

        if [[ "$line" = $(echo "*Track type: video*") ]]; then
            TYPE="vid"
        fi

        if [[ "$line" = $(echo "*Track type: audio*") ]]; then
            TYPE="aud"
        fi

        if [[ "$line" = $(echo "*Language: eng*") ]] ||
           [[ "$line" = $(echo "*Name:*Eng*") ]]; then
            LANGUAGE="eng"
        fi

        if [[ "$line" = $(echo "*Language: ger*") ]] ||
           [[ "$line" = $(echo "*Name:*Ger*") ]]; then
            LANGUAGE="ger"
        fi

        if [[ "$line" = $(echo "*Default duration:*") ]]; then
            TMPDUR=$(echo "$line" | grep -oP "[0-9.]+ms")
        fi

    done < "$INFO"

    if [ ! -f "$BASE/audio.eng.org.tmp" ] &&
       [ -f "$BASE/audio.ger.org.tmp" ] &&
       (( "$DEFAUD" >= 0 )); then
        mkvextract tracks "$f" "$DEFAUD:$BASE/audio.eng.org.tmp"
    fi

    if [ ! -f "$BASE/audio.ger.org.tmp" ] &&
       [ -f "$BASE/audio.eng.org.tmp" ] &&
       (( "$DEFAUD" >= 0 )); then
        mkvextract tracks "$f" "$DEFAUD:$BASE/audio.ger.org.tmp"
    fi

    if [ ! -f "$BASE/video.h264.tmp" ] ||
       [ ! -f "$BASE/audio.eng.org.tmp" ] ||
       [ ! -f "$BASE/audio.ger.org.tmp" ]; then
        ERR+=("$f (extracting needed tracks failed)")
        rm "$BASE"/*.tmp
        continue
    fi

    avconv -i "$BASE/audio.eng.org.tmp" -aq 448k -f ac3 "$BASE/audio.eng.ac3.tmp"
    avconv -i "$BASE/audio.ger.org.tmp" -aq 448k -f ac3 "$BASE/audio.ger.ac3.tmp"

    if [ ! -f "$BASE/audio.eng.ac3.tmp" ] ||
       [ ! -f "$BASE/audio.ger.ac3.tmp" ]; then
        ERR+=("$f (audio conversion failed)")
        rm "$BASE"/*.tmp
        continue
    fi

    mv "$f" "$f.bkp"
    mkvmerge -o "$f" --default-duration "0:$DEFDUR" --default-language "ger" "$BASE/video.h264.tmp" --language 0:ger "$BASE/audio.ger.ac3.tmp" --language 0:eng "$BASE/audio.eng.ac3.tmp"
    rm "$BASE"/*.tmp

done < <(find "$DIR" -type f -name "*.mkv" -print0)

if (( "${#ERR[@]}" > 0 )); then
    echo "Errors:"
    printf '%s\n' "${ERR[@]}"
fi

echo "Done"
exit 0
