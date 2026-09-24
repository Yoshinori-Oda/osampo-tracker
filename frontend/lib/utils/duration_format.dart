// 経過時間を"○○前"の形式で表示するための共通フォーマッタ。
// 10秒未満は秒単位で出しても意味が薄いため"10秒以内"にまとめる。
String formatElapsedJa(Duration elapsed) {
  final seconds = elapsed.inSeconds;
  if (seconds < 10) return '10秒以内';
  if (seconds < 60) return '$seconds秒前';

  final minutes = elapsed.inMinutes;
  if (minutes < 60) return '$minutes分前';

  final hours = elapsed.inHours;
  if (hours < 24) return '$hours時間前';

  final days = elapsed.inDays;
  return '$days日前';
}
