import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../services/routing_service.dart';

/// Pantalla de optimización de rutas.
///
/// Flujo:
/// 1. Al abrir, solicita permisos de GPS y centra el mapa en la
///    ubicación actual del usuario.
/// 2. El usuario toca el mapa:
///    - Sin origen -> el toque fija el Origen.
///    - Con origen y sin destino -> el toque fija el Destino y
///      dispara el cálculo de ruta con OSRM.
///    - Con origen y destino -> el toque reinicia la selección
///      (limpia todo) y no fija nada hasta el siguiente toque.
/// 3. Botones: "Usar mi ubicación actual como Origen" y "Limpiar selección".
class RouteOptimizerScreen extends StatefulWidget {
  const RouteOptimizerScreen({super.key});

  @override
  State<RouteOptimizerScreen> createState() => _RouteOptimizerScreenState();
}

class _RouteOptimizerScreenState extends State<RouteOptimizerScreen> {
  final RoutingService _routingService = RoutingService();
  final MapController _mapController = MapController();

  // Puntos seleccionados por el usuario.
  LatLng? _origin;
  LatLng? _destination;

  // Ruta calculada.
  List<LatLng> _routePoints = [];
  RouteResult? _routeResult;

  // Última posición GPS conocida (para el botón "usar mi ubicación").
  LatLng? _currentUserLocation;

  // Estados de carga.
  bool _isLocating = true;
  bool _isRoutingLoading = false;

  // Flag para saber si el mapa ya terminó su primer frame
  // (evita mover la cámara antes de que esté listo).
  bool _mapReady = false;

  String? _errorMessage;

  static const LatLng _fallbackCenter = LatLng(19.4326, -99.1332); // CDMX

  @override
  void initState() {
    super.initState();
    // Se ejecuta después de que el primer frame se haya renderizado,
    // garantizando que el MapController ya esté "attached" al widget
    // FlutterMap antes de intentar mover la cámara.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapReady = true;
      _initLocation();
    });
  }

  // ---------------------------------------------------------------------
  // Geolocalización
  // ---------------------------------------------------------------------

  /// Solicita permisos de ubicación y obtiene la posición actual,
  /// centrando el mapa y fijándola como Origen si aún no hay uno.
  Future<void> _initLocation() async {
    setState(() {
      _isLocating = true;
      _errorMessage = null;
    });

    try {
      final position = await _requestLocationAndGetPosition();
      final userLocation = LatLng(position.latitude, position.longitude);

      setState(() {
        _currentUserLocation = userLocation;
        // Solo fijamos el origen automáticamente si el usuario aún
        // no ha marcado nada manualmente en el mapa.
        _origin ??= userLocation;
      });

      _moveMapSafely(userLocation, 16);
    } on LocationPermissionException catch (e) {
      _showPermissionSnackBar(e.message);
    } catch (e) {
      setState(() {
        _errorMessage = 'No se pudo obtener tu ubicación: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLocating = false);
      }
    }
  }

  /// Paso a paso: verifica servicio de ubicación activo, solicita
  /// el permiso explícitamente con requestPermission(), y luego
  /// obtiene la posición actual con getCurrentPosition().
  Future<Position> _requestLocationAndGetPosition() async {
    // 1. ¿Está el servicio de ubicación (GPS) encendido en el dispositivo?
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw LocationPermissionException(
        'El GPS está desactivado. Actívalo en la configuración del dispositivo.',
      );
    }

    // 2. Solicita el permiso de forma explícita (dispara el diálogo
    // nativo de Android/iOS si aún no se ha concedido).
    LocationPermission permission = await Geolocator.requestPermission();

    if (permission == LocationPermission.denied) {
      throw LocationPermissionException(
        'Permiso de ubicación denegado. No se puede centrar el mapa en tu posición.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw LocationPermissionException(
        'El permiso de ubicación fue denegado permanentemente. '
        'Habilítalo manualmente desde los ajustes de la app.',
      );
    }

    // 3. Ya con permiso concedido (whileInUse o always), obtenemos
    // la posición actual del dispositivo.
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  /// Mueve la cámara del mapa solo si el controller ya está listo
  /// (evita excepciones o congelamientos si se llama demasiado pronto).
  void _moveMapSafely(LatLng target, double zoom) {
    if (!_mapReady) return;
    try {
      _mapController.move(target, zoom);
    } catch (_) {
      // Si el controller aún no está attached, se ignora silenciosamente;
      // el usuario puede recentrar manualmente con el FAB.
    }
  }

  void _showPermissionSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Reintentar',
          onPressed: _initLocation,
        ),
      ),
    );
  }

  /// Botón: "Usar mi ubicación actual como Origen".
  /// Si ya tenemos una posición GPS conocida, la usa directamente;
  /// si no, la solicita de nuevo.
  Future<void> _useCurrentLocationAsOrigin() async {
    if (_currentUserLocation == null) {
      await _initLocation();
      if (_currentUserLocation == null) return; // no se pudo obtener
    }

    setState(() {
      _origin = _currentUserLocation;
      _destination = null;
      _routePoints = [];
      _routeResult = null;
      _errorMessage = null;
    });

    _moveMapSafely(_currentUserLocation!, 16);
  }

  // ---------------------------------------------------------------------
  // Interacción con el mapa (toques)
  // ---------------------------------------------------------------------

  /// Maneja el toque sobre el mapa según las 3 reglas solicitadas.
  void _handleMapTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      _errorMessage = null;

      if (_origin == null) {
        // Regla 1: no hay origen -> este toque lo fija.
        _origin = point;
      } else if (_destination == null) {
        // Regla 2: hay origen pero no destino -> este toque fija destino
        // y se dispara el cálculo de ruta (fuera del setState).
        _destination = point;
      } else {
        // Regla 3: ya existen ambos -> se reinicia la selección.
        _origin = null;
        _destination = null;
        _routePoints = [];
        _routeResult = null;
      }
    });

    if (_origin != null && _destination != null && _routePoints.isEmpty) {
      _calculateRoute();
    }
  }

  /// Botón: "Limpiar selección".
  void _clearSelection() {
    setState(() {
      _origin = null;
      _destination = null;
      _routePoints = [];
      _routeResult = null;
      _errorMessage = null;
    });
  }

  // ---------------------------------------------------------------------
  // Cálculo de ruta (OSRM)
  // ---------------------------------------------------------------------

  Future<void> _calculateRoute() async {
    if (_origin == null || _destination == null) return;

    setState(() {
      _isRoutingLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _routingService.getRoute(
        origin: _origin!,
        destination: _destination!,
        profile: 'driving',
      );

      setState(() {
        _routePoints = result.points;
        _routeResult = result;
      });

      if (_routePoints.isNotEmpty) {
        _mapController.fitCamera(
          CameraFit.coordinates(
            coordinates: _routePoints,
            padding: const EdgeInsets.all(48),
          ),
        );
      }
    } on RoutingException catch (e) {
      setState(() {
        _errorMessage = 'No se pudo calcular la ruta: ${e.message}';
        _routePoints = [];
        _routeResult = null;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error de red al consultar OSRM. Verifica tu conexión.';
        _routePoints = [];
        _routeResult = null;
      });
    } finally {
      if (mounted) {
        setState(() => _isRoutingLoading = false);
      }
    }
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Optimizador de Rutas'),
      ),
      body: Stack(
        children: [
          // Mapa interactivo.
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _fallbackCenter,
              initialZoom: 12,
              onTap: _handleMapTap,
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
                      strokeWidth: 5,
                      color: Colors.blueAccent,
                    ),
                  ],
                ),

              MarkerLayer(
                markers: [
                  if (_origin != null)
                    Marker(
                      point: _origin!,
                      width: 44,
                      height: 44,
                      child: const Icon(
                        Icons.trip_origin,
                        color: Colors.blue,
                        size: 32,
                      ),
                    ),
                  if (_destination != null)
                    Marker(
                      point: _destination!,
                      width: 44,
                      height: 44,
                      child: const Icon(
                        Icons.flag,
                        color: Colors.red,
                        size: 32,
                      ),
                    ),
                ],
              ),
            ],
          ),

          // Banner superior con instrucciones dinámicas.
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: _InstructionBanner(
              isLocating: _isLocating,
              hasOrigin: _origin != null,
              hasDestination: _destination != null,
            ),
          ),

          // Indicador de carga (GPS o cálculo de ruta).
          if (_isLocating || _isRoutingLoading)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(child: _LoadingBadge()),
              ),
            ),

          // Banner de error.
          if (_errorMessage != null)
            Positioned(
              bottom: _routeResult != null ? 170 : 90,
              left: 16,
              right: 16,
              child: _ErrorBanner(message: _errorMessage!),
            ),

          // Tarjeta con distancia y tiempo estimado.
          if (_routeResult != null)
            Positioned(
              bottom: 90,
              left: 16,
              right: 16,
              child: _RouteInfoCard(result: _routeResult!),
            ),

          // Barra inferior con los botones de acción.
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLocating ? null : _useCurrentLocationAsOrigin,
                    icon: const Icon(Icons.my_location, size: 18),
                    label: const Text('Usar mi ubicación'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_origin != null || _destination != null)
                        ? _clearSelection
                        : null,
                    icon: const Icon(Icons.clear, size: 18),
                    label: const Text('Limpiar selección'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isLocating
            ? null
            : () {
                if (_currentUserLocation != null) {
                  _moveMapSafely(_currentUserLocation!, 16);
                } else {
                  _initLocation();
                }
              },
        tooltip: 'Centrar en mi ubicación',
        child: _isLocating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.center_focus_strong),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Excepciones
// ---------------------------------------------------------------------

class LocationPermissionException implements Exception {
  final String message;
  LocationPermissionException(this.message);
}

// ---------------------------------------------------------------------
// Widgets auxiliares de UI
// ---------------------------------------------------------------------

class _InstructionBanner extends StatelessWidget {
  final bool isLocating;
  final bool hasOrigin;
  final bool hasDestination;

  const _InstructionBanner({
    required this.isLocating,
    required this.hasOrigin,
    required this.hasDestination,
  });

  @override
  Widget build(BuildContext context) {
    String message;
    IconData icon;
    Color color;

    if (isLocating) {
      message = 'Solicitando permiso y obteniendo tu ubicación...';
      icon = Icons.gps_fixed;
      color = Colors.blueGrey;
    } else if (!hasOrigin) {
      message = 'Toca el mapa para marcar el ORIGEN';
      icon = Icons.trip_origin;
      color = Colors.blue;
    } else if (!hasDestination) {
      message = 'Origen listo. Toca el mapa para marcar el DESTINO';
      icon = Icons.flag;
      color = Colors.red;
    } else {
      message = 'Ruta trazada. Toca de nuevo para reiniciar la selección.';
      icon = Icons.check_circle;
      color = Colors.green;
    }

    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(10),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: color, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingBadge extends StatelessWidget {
  const _LoadingBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const CircularProgressIndicator(
        color: Colors.white,
        strokeWidth: 3,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(10),
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message, style: const TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteInfoCard extends StatelessWidget {
  final RouteResult result;

  const _RouteInfoCard({required this.result});

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _InfoColumn(
              icon: Icons.straighten,
              value: '${result.distanceKm.toStringAsFixed(2)} km',
              label: 'Distancia',
            ),
            Container(width: 1, height: 36, color: Colors.grey.shade300),
            _InfoColumn(
              icon: Icons.access_time,
              value: '${result.durationMinutes.toStringAsFixed(0)} min',
              label: 'Tiempo estimado',
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoColumn extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;

  const _InfoColumn({
    required this.icon,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: Colors.blueAccent, size: 22),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}