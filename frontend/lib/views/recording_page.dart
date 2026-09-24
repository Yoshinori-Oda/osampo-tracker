import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../providers/tracking_providers.dart';
import '../utils/save_or_discard_dialog.dart';
import '../widgets/compass.dart';
import 'map_view.dart';

class RecordingPage extends ConsumerStatefulWidget {
  const RecordingPage({super.key});

  @override
  ConsumerState<RecordingPage> createState() => _RecordingPageState();
}

class _RecordingPageState extends ConsumerState<RecordingPage> {
  final MapController _mapController = MapController();

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mapState = ref.watch(mapModeProvider);
    final notifier = ref.read(mapModeProvider.notifier);
    final isRecordingAsync = ref.watch(isRecordingProvider);
    final isRecording = isRecordingAsync.value ?? false;

    // camera follows current position
    if (mapState.position != null) {
      final currentLatLng = LatLng(
        mapState.position!.latitude,
        mapState.position!.longitude
      );

      final rotationAngle = (mapState.topMode == MapTopMode.heading)
        ? -mapState.position!.heading
        : 0.0;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _mapController.moveAndRotate(currentLatLng, 17.0, rotationAngle);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: SegmentedButton<RecordingPageMode>(
          segments: const [
            ButtonSegment(
              value: RecordingPageMode.statistics,
              label: Text('セッション情報')
            ),
            ButtonSegment(
              value: RecordingPageMode.map,
              label: Text('マップ操作')
            )
          ],
          selected: {mapState.pageMode},
          onSelectionChanged: (Set<RecordingPageMode> newSelection) {
            notifier.setRecordingPageMode(newSelection.first);
          }
        )
      ),
      body: IndexedStack(
        index: mapState.pageMode.index,
        children: [
          _buildStatisticsTabView(context, ref, mapState),
          const MapControlTabView()
        ]
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isRecording ? Colors.red : Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape:RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30)
              )
            ),
            onPressed: () async {
              final service = ref.read(trackingServiceProvider);
              if (!isRecording) {
                await service.startRecording();
              } else {
                _showStopRecordingDialog(context, ref);
              }
            },
            child: Text(
              isRecording ? '収録終了 (STOP)' : '収録開始 (REC)',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
            )
          )
        )
      )
    );
  }

  // session statistics tab
  Widget _buildStatisticsTabView(
    BuildContext context,
    WidgetRef ref,
    MapModeState mapState
  ) {
    return Column(
      children: [
        // map section (top 38%)
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.38,
          child: Stack(
            children: [
              _buildMapView(mapState),

              // compass button to toggle topMode
              Positioned(
                top: 12,
                right: 12,
                child: FloatingActionButton.small(
                  heroTag: 'compass_btn',
                  backgroundColor: Colors.transparent,
                  elevation: 2,
                  onPressed: () {
                    ref.read(mapModeProvider.notifier).toggleTopMode();
                  },
                  child: RealCompassWidget(
                    heading: mapState.position?.heading ?? 0.0,
                    isHeadingMode: mapState.topMode == MapTopMode.heading,
                    size: 40.0
                  )
                )
              )
            ]
          )
        ),

        // session info section (rest of bottom)
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _buildMetricTile('移動距離', ref.watch(totalDistanceProvider))),
                    const SizedBox(width: 8),
                    Expanded(child: _buildMetricTile('移動時間', ref.watch(elapsedTimeProvider))),
                  ]
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _buildMetricTile('現在速度', ref.watch(currentSpeedProvider))),
                    const SizedBox(width: 8),
                    Expanded(child: _buildMetricTile('平均速度', ref.watch(averageSpeedProvider))),
                  ]
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _buildMetricTile('現在高度', ref.watch(altitudeProvider))),
                    const SizedBox(width: 8),
                    Expanded(child: _buildMetricTile('獲得高度', ref.watch(elevationGainProvider))),
                  ]
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _buildMetricTile('最高高度', ref.watch(maxAltitudeProvider))),
                    const SizedBox(width: 8),
                    Expanded(child: _buildMetricTile('最低高度', ref.watch(minAltitudeProvider))),
                  ]
                ),
              ]
            )
          )
        )
      ]
    );
  }

  // flutter map builder
  Widget _buildMapView(MapModeState mapState) {
    if (mapState.position == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final currentLatLng = LatLng(
      mapState.position!.latitude,
      mapState.position!.longitude
    );

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: currentLatLng,
        initialZoom: 17.0,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.none
        )
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'net.wakuto.loctest'
        ),

        MarkerLayer(
          markers: [
            Marker(
              point: currentLatLng,
              width: 40,
              height: 40,
              child: Transform.rotate(
                angle: (mapState.position!.heading * pi) / 180,
                child: const Icon(
                  Icons.navigation,
                  size: 32,
                  color: Colors.blueAccent
                )
              )
            )
          ]
        )
      ]
    );
  }

  Widget _buildMetricTile(String title, String value) {
    return Card(
      elevation: 1.5,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
                fontWeight: FontWeight.bold
              )
            ),
            const SizedBox(height: 6),
            Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold
                    )
                  )
                ),
              ]
            )
          ]
        )
      )
    );
  }

  // popup for session end
  void _showStopRecordingDialog(BuildContext context, WidgetRef ref) async {
    final service = ref.read(trackingServiceProvider);

    // confirm stop dialog
    final shouldStop = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('トラッキング停止'),
          content: const Text('トラッキングを停止しますか?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('継続')
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('停止')
            )
          ]
        );
      }
    );

    if (shouldStop != true) return;

    final session = service.recordingSession;
    await service.stopRecording();

    // save / discard dialog
    if (!context.mounted) return;
    if (session == null) return;

    await showSaveOrDiscardDialog(
      sessionStartedAt: session.startedAt,
      onDiscard: () => service.completeSession(doSave: false),
      onSave: (sessionName, moveMethod) => service.completeSession(
        doSave: true,
        sessionName: sessionName,
        moveMethod: moveMethod
      )
    );
  }
}