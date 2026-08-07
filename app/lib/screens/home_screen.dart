import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/accelerometer_service.dart';
import '../services/routing_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    _AccelerometerTab(),
    _RouteOptimizerTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentIndex == 0 ? 'Acelerómetro' : 'Optimizador de Rutas'),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.speed),
            label: 'Acelerómetro',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Rutas',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Tab 1: Acelerómetro
// ---------------------------------------------------------------------
class _AccelerometerTab extends StatefulWidget {
  const _AccelerometerTab();

  @override
  State<_AccelerometerTab> createState() => _AccelerometerTabState();
}

class _AccelerometerTabState extends State<_AccelerometerTab> {
  final AccelerometerService _service = AccelerometerService();
  AccelerometerReading? _lastReading;

  @override
  void initState() {
    super.initState();
    _service.readings.listen((reading) {
      if (mounted) {
        setState(() => _lastReading = reading);
      }
    });
    _service.start();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Widget _axisBar(String label, double value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value.toStringAsFixed(2)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final reading = _lastReading;

    return Center(
      child: reading == null
          ? const CircularProgressIndicator()
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.vibration, size: 64, color: Colors.blue),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _axisBar('X', reading.x, Colors.red),
                    _axisBar('Y', reading.y, Colors.green),
                    _axisBar('Z', reading.z, Colors.blue),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Última actualización: '
                  '${reading.timestamp.hour.toString().padLeft(2, '0')}:'
                  '${reading.timestamp.minute.toString().padLeft(2, '0')}:'
                  '${reading.timestamp.second.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------
// Tab 2: Optimizador de Rutas (OSRM + flutter_map)
// ---------------------------------------------------------------------
class _RouteOptimizerTab extends StatefulWidget {
  const _RouteOptimizerTab();

  @override
  State<_RouteOptimizerTab> createState() => _RouteOptimizerTabState();
}

class _RouteOptimizerTabState extends State<_RouteOptimizerTab> {
  final RoutingService _routingService = RoutingService();
  final MapController _mapController = MapController();

  // Puntos de ejemplo (origen y destino). Reemplázalos con
  // selección real del usuario en el mapa si lo necesitas.
  final LatLng _origin = const LatLng(19.4326, -99.1332); // CDMX
  final LatLng _destination = const LatLng(19.3910, -99.2837); // Santa Fe

  List<LatLng> _routePoints = [];
  bool _isLoading = false;
  String? _errorMessage;
  RouteResult? _result;

  Future<void> _fetchRoute() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _routingService.getRoute(
        origin: _origin,
        destination: _destination,
        profile: 'driving',
      );
      setState(() {
        _routePoints = result.points;
        _result = result;
      });

      if (_routePoints.isNotEmpty) {
        _mapController.fitCamera(
          CameraFit.coordinates(
            coordinates: _routePoints,
            padding: const EdgeInsets.all(40),
          ),
        );
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _origin,
              initialZoom: 12,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.flutter_sensors_maps',
              ),
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 4,
                      color: Colors.blueAccent,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _origin,
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.location_on, color: Colors.green),
                  ),
                  Marker(
                    point: _destination,
                    width: 40,
                    height: 40,
                    child: const Icon(Icons.flag, color: Colors.red),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        if (_result != null)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Distancia: ${_result!.distanceKm.toStringAsFixed(2)} km · '
              'Duración: ${_result!.durationMinutes.toStringAsFixed(1)} min',
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: ElevatedButton.icon(
            onPressed: _isLoading ? null : _fetchRoute,
            icon: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.route),
            label: const Text('Calcular ruta más corta'),
          ),
        ),
      ],
    );
  }
}