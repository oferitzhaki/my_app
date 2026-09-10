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
  geo.Position? _currentPos;
  double _currentBearing = 0.0;
  StreamSubscription<geo.Position>? _positionStream;
  final String token =
      "pk.eyJ1Ijoib2ZlcjY0IiwiYSI6ImNtbnR2NnFuZDA4bzQydHIxbnJjaWo0amoifQ.P3zTYWAbT8SYR8rjz9QYdQ";
  PointAnnotationManager? _annotationManager;

  // נקודת תרגול בשוהם (רחוב המצפה)
  final double trainingLat = 31.9515;
  final double trainingLon = 34.9458;

  @override
  void initState() {
    super.initState();
    _startTracking();
  }

  void _startTracking() async {
    bool serviceEnabled = await geo.Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    geo.LocationPermission permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
      if (permission == geo.LocationPermission.denied) return;
    }

    _positionStream =
        geo.Geolocator.getPositionStream(
          locationSettings: const geo.LocationSettings(
            accuracy: geo.LocationAccuracy.bestForNavigation,
          ),
        ).listen((pos) {
          if (mounted) {
            setState(() {
              _currentSpeed = pos.speed * 3.6;
              _currentBearing = pos.heading;
              _currentPos = pos;
            });
            _updateBusIcon(pos.latitude, pos.longitude, pos.heading);
          }
        });
  }

  void _updateBusIcon(double lat, double lon, double bearing) async {
    if (mapboxMap == null) return;
    _annotationManager ??= await mapboxMap?.annotations
        .createPointAnnotationManager();
    await _annotationManager?.deleteAll();

    _annotationManager?.create(
      PointAnnotationOptions(
        geometry: Point(coordinates: Position(lon, lat)),
        iconImage: "bus",
        iconSize: 1.0,
        iconRotate: bearing,
        iconColor: 0xFF2ECC71.toInt(),
      ),
    );
  }

  Future<void> _applyStyle() async {
    if (mapboxMap == null) return;
    final style = mapboxMap!.style;

    try {
      // תלת ממד חכם (כחול לגבוהים, בטון לנמוכים)
      if (await style.styleLayerExists("3d-buildings"))
        await style.removeStyleLayer("3d-buildings");
      await style.addLayer(
        FillExtrusionLayer(
          id: "3d-buildings",
          sourceId: "composite",
          sourceLayer: "building",
          fillExtrusionOpacity: 0.85,
        ),
      );

      await style.setStyleLayerProperty(
        "3d-buildings",
        "fill-extrusion-color",
        [
          "interpolate",
          ["linear"],
          ["get", "height"],
          0,
          "#EAE6DA",
          25,
          "#EAE6DA",
          50,
          "#82B1FF",
          100,
          "#2979FF",
        ],
      );
      await style.setStyleLayerProperty(
        "3d-buildings",
        "fill-extrusion-height",
        ["get", "height"],
      );

      // עברית ופירוט רחובות
      final layers = ["road-label", "poi-label", "place-neighborhood-label"];
      for (var l in layers) {
        if (await style.styleLayerExists(l)) {
          await style.setStyleLayerProperty(l, "text-field", [
            "coalesce",
            ["get", "name_he"],
            ["get", "name"],
          ]);
          await style.setStyleLayerProperty(l, "text-size", 13.5);
          await style.setStyleLayerProperty(l, "text-padding", 2.0);
        }
      }
    } catch (e) {}
    _drawRoute();
  }

  Future<void> _drawRoute() async {
    if (mapboxMap == null) return;
    // מסלול בשוהם לתרגול
    final url =
        "https://api.mapbox.com/directions/v5/mapbox/driving/$trainingLon,$trainingLat;34.9422,31.9442?geometries=geojson&overview=full&access_token=$token";
    try {
      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final geometry = data['routes'][0]['geometry'];
        final style = mapboxMap!.style;
        if (await style.styleSourceExists("route-source")) {
          await style.removeStyleLayer("route-layer");
          await style.removeStyleSource("route-source");
        }
        await style.addSource(
          GeoJsonSource(
            id: "route-source",
            data: json.encode({"type": "Feature", "geometry": geometry}),
          ),
        );
        await style.addLayer(
          LineLayer(
            id: "route-layer",
            sourceId: "route-source",
            lineColor: 0xFFAA00FF.toInt(),
            lineWidth: 8.0,
            lineCap: LineCap.ROUND,
          ),
        );
      }
    } catch (e) {}
    _updateBusIcon(trainingLat, trainingLon, 0.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          MapWidget(
            key: const ValueKey("v35"),
            styleUri: MapboxStyles.MAPBOX_STREETS,
            onMapCreated: (c) {
              mapboxMap = c;
              mapboxMap?.setCamera(
                CameraOptions(
                  center: Point(
                    coordinates: Position(trainingLon, trainingLat),
                  ),
                  zoom: 17.5,
                  pitch: 65.0,
                ),
              );
              Future.delayed(const Duration(seconds: 2), _applyStyle);
            },
          ),
          // לוח מחוונים צף בסטייל "זכוכית"
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  color: Colors.white.withOpacity(0.85),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _stat(_currentSpeed.toStringAsFixed(0), "קמ\"ש"),
                      _stat("500", "קו שוהם"),
                      _stat("המצפה", "תחנה"),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String val, String label) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        val,
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ),
      Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
    ],
  );

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }
}
