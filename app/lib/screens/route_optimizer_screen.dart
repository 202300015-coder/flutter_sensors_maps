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

class _RouteOptimizerScreenState extends State<RouteOptimizerScreen>
    with WidgetsBindingObserver {
  final MapController _mapController = MapController();
  final RoutingService _routingService = RoutingService();

  LatLng? _currentLocation;
  LatLng? _origin;
  LatLng? _destination;

  List<LatLng> _routePoints = [];
  double? _routeDistanceKm;
  double? _routeDurationMin;

  bool _isFetchingRoute = false;

  // Recuerda si el permiso ya fue revocado, para detectar el caso en que
  // se revoca estando la app en background (Corrección #4).
  LocationPermission? _lastKnownPermission;

  final LatLng _defaultCenter = const LatLng(19.432608, -99.133208);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    // Corrección #4: si el permiso fue revocado mientras la app estaba en
    // background, aunque ya tuviéramos _currentLocation, hay que detectarlo
    // y limpiar el estado dependiente del GPS.
    _detectPermissionRevokedInBackground();

    // Corrección #2: no recentrar/mover la cámara si el usuario ya está
    // viendo una ruta trazada — solo se re-intenta obtener ubicación si
    // realmente no la teníamos y no hay una ruta activa en pantalla.
    if (_currentLocation == null && _routePoints.isEmpty) {
      _checkAndRestoreLocationSilently();
    }
  }

  Future<void> _detectPermissionRevokedInBackground() async {
    if (_currentLocation == null) return; // nada que invalidar

    final permission = await Geolocator.checkPermission();
    final wasGranted = _lastKnownPermission == LocationPermission.always ||
        _lastKnownPermission == LocationPermission.whileInUse;
    final nowRevoked = permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever;

    if (wasGranted && nowRevoked && mounted) {
      setState(() {
        _currentLocation = null;
      });
      _showSnackBar('Se revocó el permiso de ubicación. Actualiza el GPS de nuevo.');
    }

    _lastKnownPermission = permission;
  }

  // Corrección #1: verificación realmente silenciosa — no muestra
  // SnackBars de "Buscando..." / "Ubicación encontrada" cuando se dispara
  // automáticamente al volver del background.
  Future<void> _checkAndRestoreLocationSilently() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    final LocationPermission permission = await Geolocator.checkPermission();

    if (serviceEnabled &&
        (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse)) {
      _initLocation(
        setAsDefaultOrigin: true,
        openSettingsIfNeeded: false,
        silent: true,
      );
    }
  }

  void _showSnackBar(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
    );
  }

  /// Solicita permisos y obtiene la posición actual.
  ///
  /// [setAsDefaultOrigin] fija el resultado como Origen si aún no hay uno.
  /// [openSettingsIfNeeded] controla si se abre Ajustes automáticamente
  /// cuando el GPS está apagado o el permiso fue denegado para siempre.
  /// [silent] suprime los SnackBars informativos (usado en el flujo
  /// automático de reintento al volver del background).
  Future<void> _initLocation({
    bool setAsDefaultOrigin = false,
    bool openSettingsIfNeeded = true,
    bool silent = false,
  }) async {
    if (!silent) _showSnackBar('Buscando señal de GPS...');

    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!silent) _showSnackBar('El GPS está apagado en tu teléfono.');
        if (openSettingsIfNeeded) {
          unawaited(Geolocator.openLocationSettings());
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!silent) _showSnackBar('Permiso de GPS denegado.');
          _lastKnownPermission = permission;
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!silent) {
          _showSnackBar('Permiso denegado permanentemente en los ajustes.');
        }
        if (openSettingsIfNeeded) {
          unawaited(Geolocator.openAppSettings());
        }
        _lastKnownPermission = permission;
        return;
      }

      _lastKnownPermission = permission;

      Position position;
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
      } on TimeoutException {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown == null) rethrow;
        position = lastKnown;
        if (!silent) {
          _showSnackBar('Ubicación obtenida por señal de respaldo (Caché).');
        }
      }

      final userLatLng = LatLng(position.latitude, position.longitude);

      if (!mounted) return;

      setState(() {
        _currentLocation = userLatLng;
        if (setAsDefaultOrigin) {
          _origin ??= userLatLng;
        }
      });

      // No secuestrar la cámara si ya hay una ruta trazada en pantalla.
      if (_routePoints.isEmpty) {
        _mapController.move(userLatLng, 15.0);
      }

      if (!silent) _showSnackBar('¡Ubicación encontrada!');
    } catch (e) {
      if (!silent) _showSnackBar('Error obteniendo GPS: $e');
    }
  }

  Future<void> _useCurrentLocationAsOrigin() async {
    if (_currentLocation == null) {
      await _initLocation(setAsDefaultOrigin: true);
      if (_currentLocation == null) return;
    }

    setState(() {
      _origin = _currentLocation;
      _destination = null;
      _routePoints = [];
      _routeDistanceKm = null;
      _routeDurationMin = null;
    });

    _mapController.move(_currentLocation!, 15.0);
    _showSnackBar('Ubicación actual establecida como origen.');
  }

  void _handleTap(TapPosition tapPosition, LatLng point) {
    if (_isFetchingRoute) return;

    if (_origin == null || (_origin != null && _destination != null)) {
      setState(() {
        _origin = point;
        _destination = null;
        _routePoints = [];
        _routeDistanceKm = null;
        _routeDurationMin = null;
      });
    } else if (_origin != null && _destination == null) {
      setState(() {
        _destination = point;
        _isFetchingRoute = true;
      });
      _calculateRoute();
    }
  }

  Future<void> _calculateRoute() async {
    if (_origin == null || _destination == null) return;

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

      if (_routePoints.isNotEmpty) {
        final bounds = LatLngBounds.fromPoints(_routePoints);
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(50.0),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _destination = null;
        _routePoints = [];
        _routeDistanceKm = null;
        _routeDurationMin = null;
        _isFetchingRoute = false;
      });

      if (e is RoutingException) {
        _showSnackBar(e.message);
      } else {
        _showSnackBar('No se pudo calcular la ruta entre los puntos.');
      }
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

  Future<void> _recenterToCurrentLocation() async {
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 15.0);
      return;
    }
    await _initLocation();
  }

  /// Corrección #5: evita dibujar dos marcadores superpuestos cuando el
  /// origen o el destino coinciden exactamente con la ubicación actual.
  bool _isSamePoint(LatLng? a, LatLng? b) {
    if (a == null || b == null) return false;
    return a.latitude == b.latitude && a.longitude == b.longitude;
  }

  @override
  Widget build(BuildContext context) {
    final bool currentLocationHidden = _currentLocation != null &&
        (_isSamePoint(_currentLocation, _origin) ||
            _isSamePoint(_currentLocation, _destination));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Optimizador de Ruta'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar GPS',
            onPressed: () => _initLocation(),
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
              initialCenter: _currentLocation ?? _defaultCenter,
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
                  if (_currentLocation != null && !currentLocationHidden)
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
            heroTag: 'use_location_origin_btn',
            backgroundColor: Colors.green,
            onPressed: _useCurrentLocationAsOrigin,
            tooltip: 'Usar mi ubicación como origen',
            child: const Icon(Icons.trip_origin, color: Colors.white),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'recenter_btn',
            onPressed: _recenterToCurrentLocation,
            tooltip: 'Centrar en Mi Ubicación',
            child: const Icon(Icons.my_location),
          ),
          const SizedBox(height: 10),
          FloatingActionButton(
            heroTag: 'clear_btn',
            backgroundColor: Colors.redAccent,
            onPressed: _clearRoute,
            tooltip: 'Limpiar Ruta',
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
        ],
      ),
    );
  }
}