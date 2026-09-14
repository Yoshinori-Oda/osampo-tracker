import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'recording_page.dart';
import 'saved_sessions.dart';
import 'analytics_page.dart';

class BottomNavIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setIndex(int index) => state = index;
}

final bottomNavIndexProvider = NotifierProvider<BottomNavIndexNotifier, int>(BottomNavIndexNotifier.new);

class MainPage extends ConsumerWidget {
  const MainPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(bottomNavIndexProvider);

    final pages = [
      const RecordingPage(),
      Navigator(
        key: GlobalKey<NavigatorState>(),
        onGenerateRoute: (routeSettings) {
          return MaterialPageRoute(builder: (context) => SavedSessionsView());
        }
      ),
      const AnalyticsPage(),
      const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.history, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                'オプション\n(未実装)',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16)
              )
            ]
          )
        )
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: pages
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (index) {
          ref.read(bottomNavIndexProvider.notifier).setIndex(index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.play_circle_fill),
            label: '収録'
          ),
          NavigationDestination(
            icon: Icon(Icons.directions_run_outlined),
            selectedIcon: Icon(Icons.directions_run),
            label: '履歴'
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: '統計'
          ),
          NavigationDestination(
            icon: Icon(Icons.settings),
            label: '設定'
          )
        ]
      )
    );
  }
}