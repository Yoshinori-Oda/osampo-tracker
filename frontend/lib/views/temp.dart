import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../database/app_database.dart'; // TrackPointモデル

class SessionDetailMapView extends StatefulWidget {
  final List<TrackPoint> trackPoints;
  final bool showAllMarkers; // モード切り替えフラグ

  const SessionDetailMapView({
    super.key,
    required this.trackPoints,
    required this.showAllMarkers,
  });

  @override
  State<SessionDetailMapView> createState() => _SessionDetailMapViewState();
}

class _SessionDetailMapViewState extends State<SessionDetailMapView> {
  final MapController _mapController = MapController();

  @override
  Widget build(BuildContext context) {
    if (widget.trackPoints.isEmpty) {
      return const Center(child: Text('位置情報データがありません。'));
    }

    // 1. 全トラックポイントを LatLng リストに変換
    final points = widget.trackPoints
        .map((tp) => LatLng(tp.latitude, tp.longitude))
        .toList();

    // 2. ルート全体を包み込む LatLngBounds（バウンディングボックス）を作成
    final bounds = LatLngBounds.fromPoints(points);

    // 3. 初回描画完了時に全体のルートが綺麗に収まるようカメラを自動調整
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          // 画面端とルートの間に適度な余白（20px〜30px）を持たせる設定
          padding: const EdgeInsets.all(24.0),
        ),
      );
    });

    final startPoint = points.first;
    final endPoint = points.last;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        // 初期位置（fitCamera が効くまでの一時的な中心指定）
        initialCenter: bounds.center,
        initialZoom: 14.0,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.none, // 操作無効化
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'jp.example.gpstrackingapp',
        ),

        // 1. ルート描画 (Polyline)
        PolylineLayer(
          polylines: [
            Polyline(
              points: points,
              strokeWidth: 4.0,
              color: Colors.blueAccent,
            ),
          ],
        ),

        // 2. マーカー描画（モードで分岐）
        MarkerLayer(
          markers: widget.showAllMarkers
              ? _buildAllPointsMarkers(points) // 全トラックポイントにピン
              : _buildStartEndMarkers(startPoint, endPoint), // スタート＆ゴールのみ
        ),
      ],
    );
  }

  /// モード1: スタート(緑) & ゴール(赤) マーカー
  List<Marker> _buildStartEndMarkers(LatLng start, LatLng end) {
    return [
      Marker(
        point: start,
        width: 30,
        height: 30,
        child: const Icon(Icons.play_circle_fill, color: Colors.green, size: 28),
      ),
      Marker(
        point: end,
        width: 30,
        height: 30,
        child: const Icon(Icons.flag, color: Colors.redAccent, size: 28),
      ),
    ];
  }

  /// モード2: 全トラックポイント マーカー (小さなドット)
  List<Marker> _buildAllPointsMarkers(List<LatLng> points) {
    return points.map((p) {
      return Marker(
        point: p,
        width: 8,
        height: 8,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
          ),
        ),
      );
    }).toList();
  }
}