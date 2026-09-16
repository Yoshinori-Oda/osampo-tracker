-- load extensions and delete all existing tables
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS postgis;

DROP INDEX IF EXISTS idx_sessions_user_id, idx_sessions_updated_at, idx_sessions_deleted_at, idx_track_points_session_id;
DROP TABLE IF EXISTS track_points, sessions, users CASCADE;

-- user table (users)
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- session table (sessions)
CREATE TABLE sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(100) NOT NULL,
    started_at TIMESTAMP WITH TIME ZONE NOT NULL,
    ended_at TIMESTAMP WITH TIME ZONE NOT NULL,
    is_favorite BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,

    move_method VARCHAR(50) NOT NULL,
    total_distance DOUBLE PRECISION NOT NULL DEFAULT 0.0,
    duration_seconds INTEGER NOT NULL DEFAULT 0,
    elevation_gain REAL NOT NULL DEFAULT 0.0,
    max_altitude REAL,
    min_altitude REAL
);

CREATE INDEX idx_sessions_user_id ON sessions(user_id);
CREATE INDEX idx_sessions_updated_at ON sessions(updated_at);
-- パージ処理(deleted_at < now())の対象抽出用。tombstone行は少数のはずなので部分インデックスにする
CREATE INDEX idx_sessions_deleted_at ON sessions(deleted_at) WHERE deleted_at IS NOT NULL;

-- track points table (track_points)
CREATE TABLE track_points (
    id BIGSERIAL PRIMARY KEY,
    session_id UUID NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
    location GEOGRAPHY(POINTZ, 4326) NOT NULL,
    recorded_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE INDEX idx_track_points_session_id ON track_points(session_id);

-- stored function to be called by register function
CREATE OR REPLACE FUNCTION public.register_session_with_points(
    p_session jsonb,
    p_track_points jsonb DEFAULT '[]'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_session_id uuid;
BEGIN
    v_session_id := (p_session->>'id')::uuid;

    -- upsert session
    INSERT INTO public.sessions (
        id, user_id, name, started_at, ended_at, is_favorite, updated_at, move_method,
        total_distance, duration_seconds, elevation_gain, max_altitude, min_altitude
    ) VALUES (
        v_session_id,
        (p_session->>'user_id')::uuid,
        p_session->>'name',
        (p_session->>'started_at')::timestamptz,
        (p_session->>'ended_at')::timestamptz,
        COALESCE((p_session->>'is_favorite')::boolean, false),
        COALESCE((p_session->>'updated_at')::timestamptz, CURRENT_TIMESTAMP),
        p_session->>'move_method',
        COALESCE((p_session->>'total_distance')::double precision, 0.0),
        COALESCE((p_session->>'duration_seconds')::integer, 0),
        COALESCE((p_session->>'elevation_gain')::real, 0.0),
        (p_session->>'max_altitude')::real,
        (p_session->>'min_altitude')::real
    )
    ON CONFLICT (id) DO UPDATE SET
        user_id = EXCLUDED.user_id,
        name = EXCLUDED.name,
        started_at = EXCLUDED.started_at,
        ended_at = EXCLUDED.ended_at,
        is_favorite = EXCLUDED.is_favorite,
        updated_at = EXCLUDED.updated_at,
        move_method = EXCLUDED.move_method,
        total_distance = EXCLUDED.total_distance,
        duration_seconds = EXCLUDED.duration_seconds,
        elevation_gain = EXCLUDED.elevation_gain,
        max_altitude = EXCLUDED.max_altitude,
        min_altitude = EXCLUDED.min_altitude;
    
    -- insert track_points
    DELETE FROM public.track_points WHERE session_id = v_session_id;
    IF jsonb_array_length(p_track_points) > 0 THEN
        INSERT INTO public.track_points (session_id, location, recorded_at)
        SELECT
            v_session_id,
            ST_SetSRID(
                ST_MakePoint(
                    (elem->>'longitude')::double precision,
                    (elem->>'latitude')::double precision,
                    (elem->>'altitude')::double precision
                ),
                4326
            )::geography,
            (elem->>'recorded_at')::timestamptz
        FROM jsonb_array_elements(p_track_points) AS elem;
    END IF;
END;
$$;

-- stored function to be called by fetch function
CREATE OR REPLACE FUNCTION public.fetch_remote_sessions(
    p_user_id uuid,
    p_sync_time timestamptz DEFAULT NULL,
    p_last_synced_at timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_result jsonb;
BEGIN
    SELECT jsonb_agg(session_obj) INTO v_result
    FROM (
        SELECT
            s.id,
            s.user_id,
            s.name,
            s.started_at,
            s.ended_at,
            s.is_favorite,
            s.move_method,
            s.total_distance,
            s.duration_seconds,
            s.elevation_gain,
            s.max_altitude,
            s.min_altitude,
            s.updated_at,
            s.deleted_at,
            COALESCE(
                (
                    SELECT jsonb_agg(
                        jsonb_build_object(
                            'recorded_at', tp.recorded_at,
                            'longitude', ST_X(tp.location::geometry),
                            'latitude', ST_Y(tp.location::geometry),
                            'altitude', ST_Z(tp.location::geometry)
                        ) ORDER BY tp.recorded_at ASC
                    )
                    FROM public.track_points tp
                    WHERE tp.session_id = s.id
                ),
                '[]'::jsonb
            ) AS track_points
        FROM public.sessions s
        WHERE s.user_id = p_user_id
            AND (p_sync_time IS NULL OR s.updated_at != p_sync_time)
            AND (p_last_synced_at IS NULL OR s.updated_at > p_last_synced_at)
        ORDER BY s.started_at DESC
    ) session_obj;

    RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- PostgREST web_anon role config
CREATE ROLE web_anon NOLOGIN;

GRANT web_anon TO authenticator;
GRANT USAGE ON SCHEMA public TO web_anon;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO web_anon;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO web_anon;
GRANT EXECUTE ON FUNCTION public.register_session_with_points(jsonb, jsonb) TO web_anon;
GRANT EXECUTE ON FUNCTION public.fetch_remote_sessions(uuid, timestamptz, timestamptz) TO web_anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO web_anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO web_anon;

-- dummy user for test
INSERT INTO users (id, email)
VALUES ('11111111-1111-1111-1111-111111111111', 'test@example.com');
-- dummy session for test
INSERT INTO sessions (
    id, user_id, name, started_at, ended_at, updated_at, is_favorite, move_method,
    total_distance, duration_seconds, elevation_gain, max_altitude, min_altitude
) VALUES (
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    '11111111-1111-1111-1111-111111111111',
    'テストセッション',
    '2026-09-14T10:00:00Z',
    '2026-09-14T10:00:07Z',
    '2026-09-14T10:30:00Z',
    true,
    'run',
    10.1,
    7,
    0.5,
    11.0,
    10.5
);
-- dummy track_points for test
INSERT INTO track_points (session_id, location, recorded_at) 
VALUES (
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    ST_SetSRID(
        ST_MakePoint(
            139.767125,
            35.681236,
            10.5
        ),
        4326
    ),
    '2026-09-14T10:00:00Z'
),
(
    'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
    ST_SetSRID(
        ST_MakePoint(
            139.767200,
            35.681300,
            11.0
        ),
        4326
    ),
    '2026-09-14T10:00:10Z'
);