#!/bin/bash
# DBコンテナの初回起動時(ボリュームが空のとき)だけ実行される。postgis/postgisイメージに含まれる
# 10_postgis.sh(開発用データベースへのPostGISの導入)の後に実行されるよう、ファイル名を20_で始めている。
# ロール・テスト用データベース・拡張機能・権限を用意する。テーブルはAlembicのマイグレーションで作る
set -euo pipefail

# PostgreSQLのサーバー全体で1回だけ作るもの(ロールとテスト用データベース)
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    -v migrator_user="$MIGRATOR_DB_USER" \
    -v migrator_password="$MIGRATOR_DB_PASSWORD" \
    -v app_user="$APP_DB_USER" \
    -v app_password="$APP_DB_PASSWORD" \
    -v authenticator_password="$AUTHENTICATOR_DB_PASSWORD" \
    -v test_db="$POSTGRES_TEST_DB" <<'EOSQL'
-- マイグレーション用: テーブルを作成・変更し、その所有者になる
CREATE ROLE :"migrator_user" LOGIN PASSWORD :'migrator_password';
-- api・worker用: データの読み書きのみ(テーブルの作成・変更はできない)
CREATE ROLE :"app_user" LOGIN PASSWORD :'app_password';
-- PostgREST用(PostgRESTを削除するまでの暫定)
CREATE ROLE web_anon NOLOGIN;
CREATE ROLE authenticator LOGIN NOINHERIT PASSWORD :'authenticator_password';
GRANT web_anon TO authenticator;

-- pytest専用のデータベース
CREATE DATABASE :"test_db";
EOSQL

# 開発用・テスト用の両方のデータベースに、同じ拡張機能と権限を設定する
for db in "$POSTGRES_DB" "$POSTGRES_TEST_DB"; do
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$db" \
        -v migrator_user="$MIGRATOR_DB_USER" \
        -v app_user="$APP_DB_USER" <<'EOSQL'
-- 拡張機能の作成にはスーパーユーザーの権限が必要なので、Alembicではなくここで作る
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- publicスキーマにテーブルを作れるのはマイグレーション用のロールだけにする
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA public TO :"migrator_user";
GRANT USAGE ON SCHEMA public TO :"app_user", web_anon;

-- マイグレーション用のロールが今後作るテーブル・シーケンスに、自動で読み書きの権限を付ける
ALTER DEFAULT PRIVILEGES FOR ROLE :"migrator_user" IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :"app_user", web_anon;
ALTER DEFAULT PRIVILEGES FOR ROLE :"migrator_user" IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO :"app_user", web_anon;
EOSQL
done
