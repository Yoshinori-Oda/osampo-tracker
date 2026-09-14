import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/tracking_providers.dart';
import 'session_detail_view.dart';


class SavedSessionsView extends ConsumerWidget {
  const SavedSessionsView({super.key});

  @override
  Widget build(BuildContext cnotext, WidgetRef ref) {
    // provider settings
    final completedSessions = ref.watch(sessionsStreamProvider);
    final service = ref.read(trackingServiceProvider);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('保存済セッション一覧'),
        centerTitle: true
      ),
      body: completedSessions.when(
        loading: () => const SizedBox(
          height: 200,
          child: Center(child: CircularProgressIndicator())
        ),
        error: (err, stack) => Center(child: Text('エラーが発生しました\n$err')),
        data: (data) => SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: data.length,
            itemBuilder: (context, index) {
              final session = data[index];
              return ListTile(
                title: Text(session.name!),
                subtitle: Text(session.startedAt.toString()),
                leading: IconButton(
                  icon: Icon(session.isFavorite ? Icons.star_outlined: Icons.star_border_outlined),
                  onPressed: () => service.toggleFavorite(session)
                ),
                trailing: Icon(Icons.arrow_right),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (context) => SessionDetailView(session: session))
                  );
                }
              );
            }
          )
        )
      )
    );
  }
}