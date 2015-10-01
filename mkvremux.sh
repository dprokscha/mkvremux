#!/bin/bash

hash mkvinfo 2>/dev/null || { echo "Package not found: mkvtoolnix"; exit 1; }
hash mkvmerge 2>/dev/null || { echo "Package not found: mkvtoolnix"; exit 1; }
hash avconv 2>/dev/null || { echo "Package not found: libav-tools"; exit 1; }

SCRIPT_PATH=`pwd`
VERBOSE=0
TESTRUN=0
ERR=()

while getopts ":tv" opt; do
    case $opt in
        t)
            TESTRUN=1
            ;;
        v)
            VERBOSE=1
            ;;
        \?)
            echo "mkvremux [tv] DIR"
            exit 1
    esac
done

shift $(($OPTIND - 1))

DIR=$(echo "$1" | tr -s /); DIR=${DIR%/}

if [[ "$DIR" != /* ]]; then
    DIR="$SCRIPT_PATH/$DIR"
fi

if [ ! -d "$DIR" ]; then
    echo "Not a directory: $DIR"
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
    TYPE="und"
    LANGUAGE="und"
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
                [ $TESTRUN -eq 0 ] && mkvextract tracks "$f" "$ID:$BASE/video.h264.tmp"
                [ $TESTRUN -eq 1 ] && touch "$BASE/video.h264.tmp"
                [ $VERBOSE -eq 1 ] && echo "extract video (track $ID, to $BASE/video.h264.tmp)"
            fi

            if [ "$TYPE" = "aud" ] &&
               [ "$LANGUAGE" = "eng" ] &&
               [ ! -f "$BASE/audio.eng.org.tmp" ]; then
                [ $TESTRUN -eq 0 ] && mkvextract tracks "$f" "$ID:$BASE/audio.eng.org.tmp"
                [ $TESTRUN -eq 1 ] && touch "$BASE/audio.eng.org.tmp"
                [ $VERBOSE -eq 1 ] && echo "extract audio (eng, track $ID, to $BASE/audio.eng.org.tmp)"
            fi

            if [ "$TYPE" = "aud" ] &&
               [ "$LANGUAGE" = "ger" ] &&
               [ ! -f "$BASE/audio.ger.org.tmp" ]; then
                [ $TESTRUN -eq 0 ] && mkvextract tracks "$f" "$ID:$BASE/audio.ger.org.tmp"
                [ $TESTRUN -eq 1 ] && touch "$BASE/audio.ger.org.tmp"
                [ $VERBOSE -eq 1 ] && echo "extract audio (ger, track $ID, to $BASE/audio.ger.org.tmp)"
            fi

            if [ "$TYPE" = "vid" ] &&
               [ "$TMPDUR" != "und" ]; then
                DEFDUR=$TMPDUR
                [ $VERBOSE -eq 1 ] && echo "set default video duration: $DEFDUR"
            fi

            if [ "$TYPE" = "aud" ] &&
               (( "$DEFID" >= 0 )); then
                DEFAUD=$DEFID
                [ $VERBOSE -eq 1 ] && echo "set default audio track: $DEFAUD"
            fi

            DEFID=-1
            TYPE="und"
            LANGUAGE="und"
            TMPDUR="und"
        fi

        [ $VERBOSE -eq 1 ] && echo "$line"

        if [[ "$line" = $(echo "| + A track") ]]; then
            ID=$[$ID+1]
            [ $VERBOSE -eq 1 ] && echo "found track $ID"
        fi

        if [[ "$line" = $(echo "*Default flag: 0*") ]]; then
            DEFID=$ID
            [ $VERBOSE -eq 1 ] && echo "found default track $DEFID"
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

        if [[ "$line" = $(echo "*Default duration:*") ]]; then
            TMPDUR=$(echo "$line" | grep -oP "[0-9.]+ms")
            [ $VERBOSE -eq 1 ] && echo "found duration $TMPDUR"
        fi

    done < "$INFO"

    if [ ! -f "$BASE/audio.eng.org.tmp" ] &&
       [ -f "$BASE/audio.ger.org.tmp" ] &&
       (( "$DEFAUD" >= 0 )); then
        [ $TESTRUN -eq 0 ] && mkvextract tracks "$f" "$DEFAUD:$BASE/audio.eng.org.tmp"
        [ $TESTRUN -eq 1 ] && touch "$BASE/audio.eng.org.tmp"
        [ $VERBOSE -eq 1 ] && echo "extract audio (assumed ger, default track $DEFAUD, to $BASE/audio.ger.org.tmp)"
    fi

    if [ ! -f "$BASE/audio.ger.org.tmp" ] &&
       [ -f "$BASE/audio.eng.org.tmp" ] &&
       (( "$DEFAUD" >= 0 )); then
        [ $TESTRUN -eq 0 ] && mkvextract tracks "$f" "$DEFAUD:$BASE/audio.ger.org.tmp"
        [ $TESTRUN -eq 1 ] && touch "$BASE/audio.ger.org.tmp"
        [ $VERBOSE -eq 1 ] && echo "extract audio (assumed eng, default track $DEFAUD, to $BASE/audio.ger.org.tmp)"
    fi

    if [ ! -f "$BASE/video.h264.tmp" ] ||
       [ ! -f "$BASE/audio.eng.org.tmp" ] ||
       [ ! -f "$BASE/audio.ger.org.tmp" ]; then
        ERR+=("$f (extracting needed tracks failed)")
        rm "$BASE"/*.tmp
        continue
    fi

    [ $TESTRUN -eq 0 ] && avconv -i "$BASE/audio.eng.org.tmp" -aq 448k -f ac3 "$BASE/audio.eng.ac3.tmp"
    [ $TESTRUN -eq 1 ] && touch "$BASE/audio.eng.ac3.tmp"
    [ $TESTRUN -eq 0 ] && avconv -i "$BASE/audio.ger.org.tmp" -aq 448k -f ac3 "$BASE/audio.ger.ac3.tmp"
    [ $TESTRUN -eq 1 ] && touch "$BASE/audio.ger.ac3.tmp"

    if [ ! -f "$BASE/audio.eng.ac3.tmp" ] ||
       [ ! -f "$BASE/audio.ger.ac3.tmp" ]; then
        ERR+=("$f (audio conversion failed)")
        rm "$BASE"/*.tmp
        continue
    fi

    [ $TESTRUN -eq 0 ] && mv "$f" "$f.bkp"
    [ $TESTRUN -eq 0 ] && mkvmerge -o "$f" --default-duration "0:$DEFDUR" --default-language "ger" "$BASE/video.h264.tmp" --language 0:ger "$BASE/audio.ger.ac3.tmp" --language 0:eng "$BASE/audio.eng.ac3.tmp"
    [ $TESTRUN -eq 1 ] && echo "mkvmerge -o $f --default-duration 0:$DEFDUR --default-language ger $BASE/video.h264.tmp --language 0:ger $BASE/audio.ger.ac3.tmp --language 0:eng $BASE/audio.eng.ac3.tmp"
    [ $TESTRUN -eq 0 ] && rm "$BASE"/*.tmp

done < <(find "$DIR" -type f -name "*.mkv" -print0)

if (( "${#ERR[@]}" > 0 )); then
    echo "Errors:"
    printf '%s\n' "${ERR[@]}"
fi

echo "Done"
exit 0
