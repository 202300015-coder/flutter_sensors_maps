import 'dart:async';

import 'package:app/services/routing_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

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

  bool _isFetchingRoute = false;

  final LatLng _defaultCenter = const LatLng(19.432608, -99.133208);

  void _showSnackBar(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 4)),
    );
  }

  /// Pide ubicación únicamente cuando el usuario presiona el botón.
  Future<void> _initLocation() async {
    _showSnackBar('Buscando señal de GPS...');

    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnackBar('El GPS está apagado en tu teléfono.');
        unawaited(Geolocator.openLocationSettings());
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showSnackBar('Permiso de GPS denegado.');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showSnackBar('Permiso denegado permanentemente en Android.');
        unawaited(Geolocator.openAppSettings());
        return;
      }

      Position? position = await Geolocator.getLastKnownPosition();
      position ??= await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 5),
        ),
      );

      final userLatLng = LatLng(position.latitude, position.longitude);
      debugPrint(
        'UBICACIÓN REAL ENCONTRADA: ${position.latitude}, ${position.longitude}',
      );

      if (!mounted) return;
      setState(() {
        _currentLocation = userLatLng;
      });

      _mapController.move(userLatLng, 15.0);
      _showSnackBar('¡Ubicación encontrada!');
    } catch (e) {
      _showSnackBar('Error obteniendo GPS: $e');
    }
  }

  void _handleTap(TapPosition tapPosition, LatLng point) {
    if (_origin == null || (_origin != null && _destination != null)) {
      setState(() {
        _origin = point;
        _destination = null;
        _routePoints = [];
        _routeDistanceKm = null;
        _routeDurationMin = null;
      });
    } else if (_origin != null && _destination == null) {
      setState(() => _destination = point);
      _calculateRoute();
    }
  }

  Future<void> _calculateRoute() async {
    if (_origin == null || _destination == null) return;

    setState(() => _isFetchingRoute = true);

    try {
      final result = await _routingService.getRoute(
        origin: _origin!,
        destination: _destination!,
      );

      if (!mounted) return;
      setState(() {
        _routePoints = result.points;
        _routeDistanceKm = result.distanceKm;
        _routeDurationMin = result.durationMinutes;
        _isFetchingRoute = false;
      });
    } on RoutingException catch (e) {
      if (!mounted) return;
      setState(() => _isFetchingRoute = false);
      _showSnackBar(e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isFetchingRoute = false);
      _showSnackBar('No se pudo calcular la ruta entre los puntos.');
    }
  }

  void _clearRoute() {
    setState(() {
      _origin = null;
      _destination = null;
      _routePoints = [];
      _routeDistanceKm = null;
      _routeDurationMin = null;
    });
  }

  void _recenterToCurrentLocation() {
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 15.0);
      return;
    }
    _initLocation();
  }

  @override
  Widget build(BuildContext context) {
    final initialCenter = _currentLocation ?? _defaultCenter;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Optimizador de Ruta'),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'Mi Ubicación',
            onPressed: _initLocation,
          ),
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
                  if (_currentLocation != null)
                    Marker(
                      point: _currentLocation!,
                      width: 36.0,
                      height: 36.0,
                      child: const Icon(
                        Icons.my_location,
                        color: Colors.blue,
                        size: 28.0,
                      ),
                    ),
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
          if (_isFetchingRoute)
            const Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Card(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: 12.0,
                    horizontal: 16.0,
                  ),
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
          if (_routeDistanceKm != null &&
              _routeDurationMin != null &&
              !_isFetchingRoute)
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
