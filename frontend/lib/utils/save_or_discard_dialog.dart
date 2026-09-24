import 'package:flutter/material.dart';
import '../models/move_method.dart';
import 'delete_conflict_dialog.dart' show navigatorKey;

// 収録停止後の保存/破棄ダイアログ。通常の停止フロー(recording_page.dart)と、
// 権限エラーによる強制停止フロー(TrackingService)の両方から使う共通部品。
// infoMessageを渡すと、フォームの上に説明文(強制停止の理由など)を表示する。
Future<void> showSaveOrDiscardDialog({
  required DateTime sessionStartedAt,
  required Future<void> Function() onDiscard,
  required Future<void> Function(String sessionName, MoveMethod moveMethod) onSave,
  String? infoMessage,
}) async {
  final context = navigatorKey.currentContext;
  if (context == null) {
    // ダイアログを出せない場合は、データを失わないよう既定の名前で保存する
    await onSave(_defaultSessionName(sessionStartedAt, MoveMethod.walk), MoveMethod.walk);
    return;
  }

  final nameController = TextEditingController();
  MoveMethod selectedMethod = MoveMethod.walk;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('セッション保存'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (infoMessage != null) ...[
                  Text(infoMessage, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'セッション名',
                    border: OutlineInputBorder()
                  )
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<MoveMethod>(
                  initialValue: selectedMethod,
                  decoration: const InputDecoration(
                    labelText: '移動手段',
                    border: OutlineInputBorder()
                  ),
                  items: MoveMethod.values.map((method) {
                    return DropdownMenuItem(
                      value: method,
                      child: Text(method.label)
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => selectedMethod = val);
                  }
                )
              ]
            ),
            actions: [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  await onDiscard();
                },
                child: const Text('破棄')
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();

                  final inputName = nameController.text.trim();
                  final finalSessionName = inputName.isEmpty
                    ? _defaultSessionName(sessionStartedAt, selectedMethod)
                    : inputName;

                  await onSave(finalSessionName, selectedMethod);
                },
                child: const Text('保存')
              )
            ]
          );
        }
      );
    }
  );
}

String _defaultSessionName(DateTime startedAt, MoveMethod moveMethod) {
  final timeStr = '${startedAt.month}/${startedAt.day} '
    '${startedAt.hour}:${startedAt.minute.toString().padLeft(2, '0')}:${startedAt.second.toString().padLeft(2, '0')}';
  return '$timeStrの${moveMethod.label}アクティビティ';
}
