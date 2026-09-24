import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/tracking_providers.dart';
import '../widgets/location_banner_view.dart';
import '../widgets/recording_phase_banner_view.dart';
import 'recording_page.dart';
import 'saved_sessions.dart';
import 'analytics_page.dart';

class BottomNavIndexNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void setIndex(int index) => state = index;
}

final bottomNavIndexProvider = NotifierProvider<BottomNavIndexNotifier, int>(BottomNavIndexNotifier.new);

class MainPage extends ConsumerStatefulWidget {
  const MainPage({super.key});

  @override
  ConsumerState<MainPage> createState() => _MainPageState();
}

class _MainPageState extends ConsumerState<MainPage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // アプリ起動時に一度、他端末での変更を取り込む
    ref.read(repositoryProvider).requestSync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // バックグラウンドから復帰した際にも同期しておく
    if (state == AppLifecycleState.resumed) {
      ref.read(repositoryProvider).requestSync();
    }
  }

  @override
  Widget build(BuildContext context) {
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
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                const RecordingPhaseBannerView(),
                const LocationBannerView()
              ]
            )
          ),
          Expanded(
            child: IndexedStack(
              index: currentIndex,
              children: pages
            )
          )
        ]
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