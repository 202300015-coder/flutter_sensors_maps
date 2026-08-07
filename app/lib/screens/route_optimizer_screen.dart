import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Servicio para obtener la ruta navegable utilizando la API pública de OSRM.
class RoutingService {
  Future<Map<String, dynamic>?> getRoute(LatLng origin, LatLng destination) async {
    final url = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${origin.longitude},${origin.latitude};${destination.longitude},${destination.latitude}'
      '?overview=full&geometries=geojson',
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final coordinates = route['geometry']['coordinates'] as List;
          final points = coordinates
              .map((coord) => LatLng(coord[1].toDouble(), coord[0].toDouble()))
              .toList();

          final double distanceMeters = (route['distance'] as num).toDouble();
          final double durationSeconds = (route['duration'] as num).toDouble();

          return {
            'points': points,
            'distanceKm': distanceMeters / 1000,
            'durationMin': durationSeconds / 60,
          };
        }
      }
    } catch (e) {
      debugPrint('Error en RoutingService: $e');
    }
    return null;
  }
}

class RouteOptimizerScreen extends StatefulWidget {
  const RouteOptimizerScreen({super.key});

  @override
  State<RouteOptimizerScreen> createState() => _RouteOptimizerScreenState();
}

class _RouteOptimizerScreenState extends State<RouteOptimizerScreen> {
  final MapController _mapController = MapController();
  final RoutingService _routingService = RoutingService();

  LatLng? _currentLocation;
  LatLng? _origin;
  LatLng? _destination;

  List<LatLng> _routePoints = [];
  double? _routeDistanceKm;
  double? _routeDurationMin;

  bool _isLoadingLocation = true;
  bool _isFetchingRoute = false;

  // Ubicación por defecto (Ciudad de México) si falla el GPS
  final LatLng _defaultCenter = const LatLng(19.432608, -99.133208);

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  /// Gestiona los permisos e inicializa la posición actual del usuario.
  Future<void> _initLocation() async {
    setState(() => _isLoadingLocation = true);

    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _showSnackBar('Los servicios de ubicación están desactivados.');
      _useFallbackLocation();
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        _showSnackBar('Permiso de ubicación denegado.');
        _useFallbackLocation();
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      _showSnackBar('Los permisos de ubicación están denegados permanentemente.');
      _useFallbackLocation();
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final userLatLng = LatLng(position.latitude, position.longitude);

      if (!mounted) return;
      setState(() {
        _currentLocation = userLatLng;
        _origin = userLatLng;
        _isLoadingLocation = false;
      });

      _mapController.move(userLatLng, 15.0);
    } catch (e) {
      _showSnackBar('Error al obtener la ubicación actual.');
      _useFallbackLocation();
    }
  }

  void _useFallbackLocation() {
    if (!mounted) return;
    setState(() {
      _isLoadingLocation = false;
      _origin = _defaultCenter;
    });
    _mapController.move(_defaultCenter, 13.0);
  }

  /// Lógica al presionar sobre el mapa.
  void _handleTap(TapPosition tapPosition, LatLng point) {
    if (_origin == null || (_origin != null && _destination != null)) {
      // Caso 1 o 3: Primer toque o reinicio de selección
      setState(() {
        _origin = point;
        _destination = null;
        _routePoints = [];
        _routeDistanceKm = null;
        _routeDurationMin = null;
      });
    } else if (_origin != null && _destination == null) {
      // Caso 2: Segundo toque (Destino)
      setState(() => _destination = point);
      _calculateRoute();
    }
  }

  /// Llama al servicio de ruteo y traza la Polyline.
  Future<void> _calculateRoute() async {
    if (_origin == null || _destination == null) return;

    setState(() => _isFetchingRoute = true);

    final result = await _routingService.getRoute(_origin!, _destination!);

    if (!mounted) return;

    if (result != null) {
      setState(() {
        _routePoints = result['points'] as List<LatLng>;
        _routeDistanceKm = result['distanceKm'] as double;
        _routeDurationMin = result['durationMin'] as double;
        _isFetchingRoute = false;
      });
    } else {
      setState(() => _isFetchingRoute = false);
      _showSnackBar('No se pudo calcular la ruta entre los puntos.');
    }
  }

  /// Restablece la selección de origen y destino.
  void _clearRoute() {
    setState(() {
      _origin = _currentLocation;
      _destination = null;
      _routePoints = [];
      _routeDistanceKm = null;
      _routeDurationMin = null;
    });
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 15.0);
    }
  }

  /// Centra el mapa en la posición actual del GPS.
  void _recenterToCurrentLocation() {
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 15.0);
    } else {
      _initLocation();
    }
  }

  void _showSnackBar(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final initialCenter = _currentLocation ?? _defaultCenter;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Optimizador de Ruta'),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: 'Limpiar Ruta',
            onPressed: _clearRoute,
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: 14.0,
              onTap: _handleTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.route_optimizer',
              ),
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 5.0,
                      color: Colors.blue,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  if (_origin != null)
                    Marker(
                      point: _origin!,
                      width: 40.0,
                      height: 40.0,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.green,
                        size: 40.0,
                      ),
                    ),
                  if (_destination != null)
                    Marker(
                      point: _destination!,
                      width: 40.0,
                      height: 40.0,
                      child: const Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 40.0,
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Indicador de estado de carga inicial de GPS
          if (_isLoadingLocation)
            Container(
              color: Colors.black26,
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(width: 16),
                        Text('Obteniendo ubicación...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          // Indicador de estado de carga de la ruta
          if (_isFetchingRoute)
            const Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Card(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      SizedBox(width: 16),
                      Text('Trazando ruta...'),
                    ],
                  ),
                ),
              ),
            ),

          // Card informativo con distancia y duración estimada
          if (_routeDistanceKm != null && _routeDurationMin != null && !_isFetchingRoute)
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.straighten, color: Colors.blue),
                          const SizedBox(width: 8),
                          Text(
                            '${_routeDistanceKm!.toStringAsFixed(2)} km',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Icon(Icons.timer, color: Colors.orange),
                          const SizedBox(width: 8),
                          Text(
                            '${_routeDurationMin!.toStringAsFixed(0)} min',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'recenter_btn',
            onPressed: _recenterToCurrentLocation,
            tooltip: 'Mi Ubicación',
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'clear_btn',
            backgroundColor: Colors.redAccent,
            onPressed: _clearRoute,
            tooltip: 'Limpiar Ruta',
            child: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}