#!/usr/bin/env bash
# integration_test/app_test.dartをflutter driveで実行し、結果をログファイルへ保存する。
#
# 使い方:
#   scripts/run_e2e_tests.sh <run_id>                     (既定デバイスで実行)
#   scripts/run_e2e_tests.sh <run_id> -d <device_id>      (デバイスを上書き)
#   scripts/run_e2e_tests.sh --id <run_id> --device <device_id>
#
# run_id: 「どの依頼に対応する実行結果か」を一意に特定するための相関トークン。
#         テスト内容の説明ではなく、依頼ごとに変わるユニークな文字列を渡すこと
#         (例: Claudeが依頼時に生成した a3f9c21b のような文字列)。
#         複数セッションでテストが前後しても、run_idで検索すれば取り違えない。
#
# デバイスの決定順: -d/--device指定 > E2E_DEVICE_ID環境変数 > 下記DEFAULT_DEVICE_ID
#
# ログは frontend/e2e_test_logs/<timestamp>_<run_id>_<device_id>_<PASSED|FAILED>.log に保存される。
# (*.log は.gitignore済みなのでコミット対象にはならない)

set -uo pipefail

# 普段使う実機/エミュレータのIDに書き換えておくと、-dを省略して実行できる
# (`flutter devices`で確認できる値)
DEFAULT_DEVICE_ID="A35B6C74-84CE-4CDA-9985-CAE7A066A829"

usage() {
  echo "使い方: $(basename "$0") <run_id> [-d <device_id>]" >&2
  echo "        $(basename "$0") --id <run_id> [--device <device_id>]" >&2
}

RUN_ID=""
DEVICE_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--device)
      if [[ $# -lt 2 ]]; then
        echo "エラー: $1 には値が必要です" >&2
        usage
        exit 1
      fi
      DEVICE_ID="$2"
      shift 2
      ;;
    -i|--id)
      if [[ $# -lt 2 ]]; then
        echo "エラー: $1 には値が必要です" >&2
        usage
        exit 1
      fi
      RUN_ID="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ -z "$RUN_ID" ]]; then
        RUN_ID="$1"
      else
        echo "エラー: 想定外の引数です: $1" >&2
        usage
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$RUN_ID" ]]; then
  usage
  exit 1
fi

DEVICE_ID="${DEVICE_ID:-${E2E_DEVICE_ID:-$DEFAULT_DEVICE_ID}}"
if [[ -z "$DEVICE_ID" ]]; then
  echo "エラー: デバイスIDが未指定です。次のいずれかで指定してください:" >&2
  echo "  1) -d/--device オプション" >&2
  echo "  2) E2E_DEVICE_ID 環境変数" >&2
  echo "  3) このスクリプト冒頭の DEFAULT_DEVICE_ID" >&2
  echo "(flutter devices で確認できます)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
LOG_DIR="$FRONTEND_DIR/e2e_test_logs"
mkdir -p "$LOG_DIR"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
# ファイル名に使えない文字(iOSのUDIDの:、adb over wifiの:等)を潰す
SAFE_RUN_ID="$(printf '%s' "$RUN_ID" | tr -c 'A-Za-z0-9_.-' '_')"
SAFE_DEVICE_ID="$(printf '%s' "$DEVICE_ID" | tr -c 'A-Za-z0-9_.-' '_')"
LOG_FILE="$LOG_DIR/${TIMESTAMP}_${SAFE_RUN_ID}_${SAFE_DEVICE_ID}.log"

echo "run_id: $RUN_ID"
echo "device: $DEVICE_ID"
echo "log: $LOG_FILE"

cd "$FRONTEND_DIR"

flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/app_test.dart \
  -d "$DEVICE_ID" \
  2>&1 | tee "$LOG_FILE"
RESULT=${PIPESTATUS[0]}

if [[ $RESULT -eq 0 ]]; then
  STATUS_LABEL=PASSED
else
  STATUS_LABEL=FAILED
fi
FINAL_LOG_FILE="${LOG_FILE%.log}_${STATUS_LABEL}.log"
mv "$LOG_FILE" "$FINAL_LOG_FILE"

echo "結果: $STATUS_LABEL -> $FINAL_LOG_FILE"
exit "$RESULT"
