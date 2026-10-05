import os

# pytestは常にテスト用のデータベース(POSTGRES_TEST_DB)に接続する。
# app.configのSettingsはimport時に環境変数を読むので、appをimportする前に書き換える
os.environ["POSTGRES_DB"] = os.environ.get("POSTGRES_TEST_DB", "location_db_test")
