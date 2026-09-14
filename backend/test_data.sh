curl -i -X POST "http://localhost:3000/rpc/register_session_with_points" \
  -H "Content-Type: application/json" \
  -d '{
    "p_session": {
      "id": "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11",
      "user_id": "11111111-1111-1111-1111-111111111111",
      "name": "curlテストセッション",
      "started_at": "2026-09-14T10:00:00Z",
      "ended_at": "2026-09-14T10:00:07Z",
      "is_favorite": true,
      "move_method": "run",
      "total_distance": 10.0,
      "duration_seconds": 7,
      "elevation_gain": 0.5,
      "max_altitude": 11.0,
      "min_altitude": 10.5,
      "updated_at": "2026-09-14T10:30:00Z"
    },
    "p_track_points": [
      {
        "latitude": 35.681236,
        "longitude": 139.767125,
        "altitude": 10.5,
        "recorded_at": "2026-09-14T10:00:05Z"
      },
      {
        "latitude": 35.681300,
        "longitude": 139.767200,
        "altitude": 11.0,
        "recorded_at": "2026-09-14T10:00:10Z"
      }
    ]
  }'