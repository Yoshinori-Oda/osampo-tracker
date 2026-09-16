#!/bin/sh
# deleted_at (tombstone猶予期限)を過ぎたsessionsを物理削除する
# track_pointsはsessions側のON DELETE CASCADEで一緒に消える
now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
curl -sf -X DELETE "http://postgrest:3000/sessions?deleted_at=lt.${now}"
