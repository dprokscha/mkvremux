#!/bin/bash

hash mkvinfo 2>/dev/null || { echo "Package not found: mkvtoolnix"; exit 1; }
hash mkvmerge 2>/dev/null || { echo "Package not found: mkvtoolnix"; exit 1; }
hash avconv 2>/dev/null || { echo "Package not found: libav-tools"; exit 1; }

DIR=$(echo "$1" | tr -s /); DIR=${DIR%/}
SCRIPT_PATH=`pwd`

if [[ "$DIR" != /* ]]; then
    DIR="$SCRIPT_PATH/$DIR"
fi

if [ ! -d "$DIR" ]; then
    echo "Not found: $DIR"
    exit 1
fi

for f in $(find "$DIR" -name "*.mkv"); do
    BASE=$(dirname "$f")
    INFO="$BASE/mkvinfo.tmp"

    echo "Processing: $f"
    mkvinfo -r "$INFO" "$f"

    if (( "$(grep -c "Track type: audio" "$INFO")" < 2 )) ||
       (( "$(grep -c "Channels: [1,2,3,4]" "$INFO")" > 0 )); then
        echo "Omitted: $f (not enough audio tracks found or bad audio quality)"
        continue
    fi

    if (( "$(grep -c "Track type: video" "$INFO")" > 1 )) ||
       (( "$(grep -c "h.264" "$INFO")" == 0 )) ||
       (( "$(grep -c "Pixel width: 1920" "$INFO")" == 0 )); then
        echo "Omitted: $f (too many video tracks or bad video quality)"
        continue
    fi

    ID=-1
    LANGUAGE="und"
    TYPE="und"

    while IFS= read -r line || [[ -n "$line" ]]; do

        if [ -f "$BASE/video.h264.tmp" ] && [ -f "$BASE/audio.eng.org.tmp" ] && [ -f "$BASE/audio.ger.org.tmp" ]; then
            break
        fi

        if [[ "$line" = $(echo "*A track*") ]]; then
            ID=$[$ID+1]
            LANGUAGE="und"
            TYPE="und"
        fi

        if [[ "$line" = $(echo "*Track type: video*") ]]; then
            echo "Found track: Video (ID: $ID)"
            mkvextract tracks "$f" "$ID:video.h264.tmp"
        fi

        if [[ "$line" = $(echo "*Track type: audio*") ]]; then
            TYPE="aud"
        fi

        if [ "$TYPE" = "aud" ] && [ "$LANGUAGE" = "und" ] && [[ "$line" = $(echo "*Language: eng*") ]]; then
            LANGUAGE="eng"
        fi

        if [ "$TYPE" = "aud" ] && [ "$LANGUAGE" = "und" ] && [[ "$line" = $(echo "*Language: ger*") ]]; then
            LANGUAGE="ger"
        fi

        if [ "$TYPE" = "aud" ] && [ "$LANGUAGE" = "eng" ]; then
            echo "Found track: Audio, eng (ID: $ID)"
            mkvextract tracks "$f" "$ID:audio.eng.org.tmp"
        fi

        if [ "$TYPE" = "aud" ] && [ "$LANGUAGE" = "ger" ]; then
            echo "Found track: Audio, ger (ID: $ID)"
            mkvextract tracks "$f" "$ID:audio.ger.org.tmp"
        fi

    done < "$INFO"

    if [ ! -f "$BASE/video.h264.tmp" ] || [ ! -f "$BASE/audio.eng.org.tmp" ] || [ ! -f "$BASE/audio.ger.org.tmp" ]; then
        echo "Omitted: $f (extracting needed tracks failed)"
        continue
    fi

    avconv -i "$BASE/audio.eng.org.tmp" -aq 448k -f ac3 "$BASE/audio.eng.ac3.tmp"
    avconv -i "$BASE/audio.ger.org.tmp" -aq 448k -f ac3 "$BASE/audio.ger.ac3.tmp"

    if [ ! -f "$BASE/audio.eng.ac3.tmp" ] || [ ! -f "$BASE/audio.ger.ac3.tmp" ]; then
        echo "Omitted: $f (audio conversion failed)"
        continue
    fi

    mv "$f" "$f.bkp"
    mkvmerge -o "$f" --default-language "ger" "$BASE/video.h264.tmp" --language 0:ger "$BASE/audio.ger.ac3.tmp" --language 0:eng "$BASE/audio.eng.ac3.tmp"

    rm "$BASE"/*.tmp

done

echo "Done"
exit 0