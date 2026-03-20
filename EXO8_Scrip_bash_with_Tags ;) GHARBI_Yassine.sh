#!/bin/bash

NB_THREAD=$(pgrep -c -f "$0")
if [ $NB_THREAD -gt 1 ]; then
  echo "Already running"
  exit
fi

# CONFIG
API_TOKEN="w10pmh5zlmpcVM2b7uglyQ=="

ALBUM_ID="IKJMxZugjcsfgORWnGhqhtzX"

SOURCE_DIR="/home/yassine/datasource"
PYTHON_SCRIPT="$SOURCE_DIR/getColor.py"
TMP_DIR="/tmp/yassine_sync"

mkdir -p $TMP_DIR

echo "START SYNC"

# CHECK SOURCE DIRECTORY
if [ ! -d "$SOURCE_DIR" ]; then
  echo "Source directory not found"
  exit 1
fi

# CHECK PYTHON SCRIPT
if [ ! -f "$PYTHON_SCRIPT" ]; then
  echo "Python script not found"
  exit 1
fi

# LOCAL FILE LIST (IMAGES ONLY)
ls "$SOURCE_DIR" | grep -E '\.(jpg|jpeg|png)$' > $TMP_DIR/local_list.txt
sort $TMP_DIR/local_list.txt > $TMP_DIR/local_sorted.txt

# REMOTE FILE LIST
curl \
--url "https://photoserver2.mde.epf.fr/api/v2/Album::photos?album_id=$ALBUM_ID" \
--header "Authorization: $API_TOKEN" \
--header "Accept: application/json" \
> $TMP_DIR/remote.json

# Extract titles
jq -r '.photos[] | .title' $TMP_DIR/remote.json | sort > $TMP_DIR/remote_sorted.txt

# FILES TO DELETE
comm -23 $TMP_DIR/remote_sorted.txt $TMP_DIR/local_sorted.txt > $TMP_DIR/to_delete.txt

while read filename; do
  PHOTO_ID=$(jq -r ".photos[] | select(.title==\"$filename\").id" $TMP_DIR/remote.json)

  if [ ! -z "$PHOTO_ID" ]; then
    curl -s --request DELETE \
    --url https://photoserver2.mde.epf.fr/api/v2/Photo \
    --header "Authorization: $API_TOKEN" \
    --header "Content-Type: application/json" \
    --header "Accept: application/json" \
    --data "{\"from_id\":\"$ALBUM_ID\",\"photo_ids\":[\"$PHOTO_ID\"]}"

    echo "Deleted $filename"
  fi
done < $TMP_DIR/to_delete.txt

# REFRESH AFTER DELETE
curl \
--url "https://photoserver2.mde.epf.fr/api/v2/Album::photos?album_id=$ALBUM_ID" \
--header "Authorization: $API_TOKEN" \
--header "Accept: application/json" \
> $TMP_DIR/remote.json

jq -r '.photos[] | .title' $TMP_DIR/remote.json | sort > $TMP_DIR/remote_sorted.txt

# FILES TO UPLOAD
comm -13 $TMP_DIR/remote_sorted.txt $TMP_DIR/local_sorted.txt > $TMP_DIR/to_upload.txt

while read filename; do
  FILEPATH="$SOURCE_DIR/$filename"

  if [ ! -f "$FILEPATH" ]; then
    continue
  fi

  curl --request POST \
  --url https://photoserver2.mde.epf.fr/api/v2/Photo \
  --header "Authorization: $API_TOKEN" \
  --header "Accept: application/json" \
  --header "Content-Type: multipart/form-data" \
  --form "album_id=$ALBUM_ID" \
  --form "file=@$FILEPATH" \
  --form "file_name=$filename" \
  --form "chunk_number=1" \
  --form "total_chunks=1" \
  --form "uuid_name=" \
  --form "extension="

  echo "Uploaded $filename"

done < $TMP_DIR/to_upload.txt

# REFRESH REMOTE
curl \
--url "https://photoserver2.mde.epf.fr/api/v2/Album::photos?album_id=$ALBUM_ID" \
--header "Authorization: $API_TOKEN" \
--header "Accept: application/json" \
> $TMP_DIR/remote.json

# TAGGING
jq -r '.photos[] | select(.tags == [w]) | "\(.id) \(.title)"' $TMP_DIR/remote.json > $TMP_DIR/no_tags.txt

while read photo_id filename; do

  FILEPATH="$SOURCE_DIR/$filename"

  if [ ! -f "$FILEPATH" ]; then
    continue
  fi

  COLORS=$(python3 "$PYTHON_SCRIPT" "$FILEPATH")

  COLOR1=$(echo $COLORS | cut -d',' -f1)
  COLOR2=$(echo $COLORS | cut -d',' -f2)

  if [ -z "$COLOR1" ] || [ -z "$COLOR2" ]; then
    continue
  fi

  curl -s --request PATCH \
  --url https://photoserver2.mde.epf.fr/api/v2/Photo::tags \
  --header "Authorization: $API_TOKEN" \
  --header "Content-Type: application/json" \
  --header "Accept: application/json" \
  --data "{
    \"shall_override\": true,
    \"photo_ids\": [\"$photo_id\"],
    \"tags\": [$COLOR1, $COLOR2]
  }"

  echo "Tagged $filename"

done < $TMP_DIR/no_tags.txt

done < $TMP_DIR/all_photos.txt

echo "SYNC COMPLETE"