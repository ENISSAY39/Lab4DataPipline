#!/bin/bash

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

# LOCAL FILE LIST
ls "$SOURCE_DIR" > $TMP_DIR/local_list.txt
sort $TMP_DIR/local_list.txt > $TMP_DIR/local_sorted.txt

# REMOTE FILE LIST
curl \
--url "https://photoserver2.mde.epf.fr/api/v2/Album::photos?album_id=$ALBUM_ID" \
--header "Authorization: $API_TOKEN" \
--header "Accept: application/json" \
> $TMP_DIR/remote.json

# Extract titles
jq -r '.photos[] | .title' $TMP_DIR/remote.json | sort > $TMP_DIR/remote_sorted.txt

# FILES TO DELETE (remote - local)
comm -23 $TMP_DIR/remote_sorted.txt $TMP_DIR/local_sorted.txt > $TMP_DIR/to_delete.txt

# DELETE LOOP
while read filename; do

  PHOTO_ID=$(jq -r ".photos[] | select(.title==\"$filename\").id" $TMP_DIR/remote.json)

  if [ ! -z "$PHOTO_ID" ]; then
    curl -s --request DELETE \
    --url https://photoserver2.mde.epf.fr/api/v2/Photo \
    --header "Authorization: $API_TOKEN" \
    --header "Content-Type: application/json" \
    --header "Accept: application/json" \
    --data "{\"from_id\":\"$ALBUM_ID\",\"photo_ids\":[\"$PHOTO_ID\"]}"

    echo "Deleted $filename (ID: $PHOTO_ID)"
  fi

done < $TMP_DIR/to_delete.txt

# 🔥 REFRESH AFTER DELETE
echo "Refreshing remote after delete..."

curl \
--url "https://photoserver2.mde.epf.fr/api/v2/Album::photos?album_id=$ALBUM_ID" \
--header "Authorization: $API_TOKEN" \
--header "Accept: application/json" \
> $TMP_DIR/remote.json

jq -r '.photos[] | .title' $TMP_DIR/remote.json | sort > $TMP_DIR/remote_sorted.txt

# FILES TO UPLOAD (local - remote)
comm -13 $TMP_DIR/remote_sorted.txt $TMP_DIR/local_sorted.txt > $TMP_DIR/to_upload.txt

# UPLOAD LOOP
while read filename; do

  FILEPATH="$SOURCE_DIR/$filename"

  if [ ! -f "$FILEPATH" ]; then
    echo "File not found, skipping $filename"
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

# REFRESH REMOTE DATA
curl \
--url "https://photoserver2.mde.epf.fr/api/v2/Album::photos?album_id=$ALBUM_ID" \
--header "Authorization: $API_TOKEN" \
--header "Accept: application/json" \
> $TMP_DIR/remote.json

# TAGGING (PHOTOS WITHOUT TAGS)
jq -r '.photos[] | select(.tags == []) | "\(.id) \(.title)"' $TMP_DIR/remote.json > $TMP_DIR/no_tags.txt

while read photo_id filename; do

  FILEPATH="$SOURCE_DIR/$filename"

  # Skip si fichier absent
  if [ ! -f "$FILEPATH" ]; then
    echo "File not found locally, skipping $filename"
    continue
  fi

  COLORS=$(python3 "$PYTHON_SCRIPT" "$FILEPATH")

  COLOR1=$(echo $COLORS | cut -d',' -f1)
  COLOR2=$(echo $COLORS | cut -d',' -f2)

  echo "Colors for $filename: $COLOR1 $COLOR2"

  # Sécurité JSON
  if [ -z "$COLOR1" ] || [ -z "$COLOR2" ]; then
    echo "Invalid colors, skipping $filename"
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

echo "SYNC COMPLETE"