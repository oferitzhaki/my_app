import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:http/http.dart' as http;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MapboxOptions.setAccessToken(
    "pk.eyJ1Ijoib2ZlcjY0IiwiYSI6ImNtbnR2NnFuZDA4bzQydHIxbnJjaWo0amoifQ.P3zTYWAbT8SYR8rjz9QYdQ",
  );
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: EggedLiveCockpit(),
    ),
  );
}

class EggedLiveCockpit extends StatefulWidget {
  const EggedLiveCockpit({super.key});
  @override
  State<EggedLiveCockpit> createState() => _EggedLiveCockpitState();
}

class _EggedLiveCockpitState extends State<EggedLiveCockpit> {
  MapboxMap? mapboxMap;
  double _currentSpeed = 0.0;
  StreamSubscription<geo.Position>? _positionStream;
  final String token =
      "pk.eyJ1Ijoib2ZlcjY0IiwiYSI6ImNtbnR2NnFuZDA4bzQydHIxbnJjaWo0amoifQ.P3zTYWAbT8SYR8rjz9QYdQ";

  @override
  void initState() {
    super.initState();
    _startTracking();
  }

  void _startTracking() async {
    await geo.Geolocator.requestPermission();
    _positionStream =
        geo.Geolocator.getPositionStream(
          locationSettings: const geo.LocationSettings(
            accuracy: geo.LocationAccuracy.bestForNavigation,
          ),
        ).listen((pos) {
          if (mounted) setState(() => _currentSpeed = pos.speed * 3.6);
        });
  }

  Future<void> _apply3D() async {
    try {
      await mapboxMap?.style.addSource(
        VectorSource(id: "composite", url: "mapbox://mapbox.mapbox-streets-v8"),
      );
      await mapboxMap?.style.addLayer(
        FillExtrusionLayer(
          id: "3d-buildings",
          sourceId: "composite",
          sourceLayer: "building",
          minZoom: 15.0,
          // התיקון הסופי: מספרים קבועים (double) במקום נוסחה כדי לעבור 100% נקי
          fillExtrusionHeight: 35.0,
          fillExtrusionBase: 0.0,
          fillExtrusionColor: 0xCCD3D3D3,
          fillExtrusionOpacity: 0.8,
        ),
      );
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> _drawRoute() async {
    const waypoints = "34.8647,32.1035;34.8621,32.1023;34.8510,32.0925";
    final url =
        "https://api.mapbox.com/directions/v5/mapbox/driving/$waypoints?geometries=geojson&overview=full&access_token=$token";

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final route = json.decode(response.body)['routes'][0]['geometry'];
        await mapboxMap?.style.addSource(
          GeoJsonSource(
            id: "s",
            data: json.encode({"type": "Feature", "geometry": route}),
          ),
        );
        await mapboxMap?.style.addLayer(
          LineLayer(
            id: "l",
            sourceId: "s",
            lineColor: 0xFFFFD700,
            lineWidth: 8.0,
            lineCap: LineCap.ROUND,
            lineJoin: LineJoin.ROUND,
          ),
        );
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          MapWidget(
            key: const ValueKey("m"),
            styleUri: MapboxStyles.LIGHT,
            onMapCreated: (c) {
              mapboxMap = c;
              mapboxMap?.setCamera(
                CameraOptions(
                  center: Point(coordinates: Position(34.8647, 32.1035)),
                  zoom: 17.5,
                  pitch: 70.0,
                ),
              );
              Timer(const Duration(seconds: 2), () {
                _apply3D();
                _drawRoute();
              });
            },
          ),
          Positioned(bottom: 40, left: 20, right: 20, child: _buildDashboard()),
        ],
      ),
    );
  }

  Widget _buildDashboard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0x99000000),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat(_currentSpeed.toStringAsFixed(0), "קמ\"ש", Colors.white),
              _stat("947", "קו", const Color(0xFFFFD700)),
              _stat("חיפה", "יעד", const Color(0xFF2ECC71)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String v, String l, Color c) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        v,
        style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: c),
      ),
      Text(l, style: const TextStyle(fontSize: 12, color: Colors.white54)),
    ],
  );

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }
}
