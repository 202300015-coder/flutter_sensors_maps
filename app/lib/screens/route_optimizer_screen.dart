import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../services/routing_service.dart';

/// Pantalla que muestra un mapa interactivo (OpenStreetMap vía flutter_map).
/// Al abrir, obtiene la ubicación GPS del usuario y la fija como Origen.
/// El usuario toca el mapa para marcar el Destino; en cuanto existen
/// ambos puntos, se calcula automáticamente la ruta con OSRM.
class RouteOptimizerScreen extends StatefulWidget {
  const RouteOptimizerScreen({super.key});

  @override
  State<RouteOptimizerScreen> createState() => _RouteOptimizerScreenState();
}

class _RouteOptimizerScreenState extends State<RouteOptimizerScreen> {
  final RoutingService _routingService = RoutingService();
  final MapController _mapController = MapController();

  // Puntos seleccionados.
  LatLng? _origin;
  LatLng? _destination;

  // Puntos de la ruta calculada (para dibujar la Polyline).
  List<LatLng> _routePoints = [];
  RouteResult? _routeResult;

  // Estados de carga independientes para GPS y para el cálculo de ruta.
  bool _isLocating = true;
  bool _isRoutingLoading = false;

  String? _errorMessage;

  // Centro por defecto (fallback) si no se puede obtener el GPS.
  static const LatLng _fallbackCenter = LatLng(19.4326, -99.1332); // CDMX

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  // ---------------------------------------------------------------------
  // Geolocalización
  // ---------------------------------------------------------------------

  /// Solicita permisos de ubicación, obtiene la posición actual del
  /// usuario y la establece como punto de Origen, centrando el mapa.
  Future<void> _initLocation() async {
    setState(() {
      _isLocating = true;
      _errorMessage = null;
    });

    try {
      final position = await _determinePosition();
      final userLocation = LatLng(position.latitude, position.longitude);

      setState(() {
        _origin = userLocation;
      });

      _mapController.move(userLocation, 16);
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

  /// Verifica servicio de ubicación y permisos, y devuelve la posición
  /// actual del dispositivo. Lanza [LocationPermissionException] si
  /// el usuario deniega el permiso.
  Future<Position> _determinePosition() async {
    // 1. Verifica que el servicio de ubicación esté activo (GPS encendido).
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw LocationPermissionException(
        'El servicio de ubicación está desactivado. Actívalo para continuar.',
      );
    }

    // 2. Verifica el estado actual del permiso.
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      // Solicita el permiso al usuario.
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw LocationPermissionException(
          'Permiso de ubicación denegado. No se puede centrar el mapa en tu posición.',
        );
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw LocationPermissionException(
        'El permiso de ubicación fue denegado permanentemente. '
        'Habilítalo desde la configuración de la app.',
      );
    }

    // 3. Obtiene la posición actual con buena precisión.
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  /// Muestra un SnackBar explicando el motivo por el que no se
  /// pudo acceder a la ubicación.
  void _showPermissionSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Reintentar',
          onPressed: _initLocation,
        ),
      ),
    );
  }

  /// Vuelve a centrar el mapa en la ubicación actual (botón FAB).
  Future<void> _recenterOnUser() async {
    if (_origin != null && !_isLocating) {
      // Si ya tenemos una ubicación previa, simplemente re-centramos.
      _mapController.move(_origin!, 16);
      return;
    }
    await _initLocation();
  }

  // ---------------------------------------------------------------------
  // Interacción con el mapa (toques)
  // ---------------------------------------------------------------------

  /// Maneja el toque sobre el mapa:
  /// - Si no hay destino aún -> este toque define el Destino.
  /// - Si ya existen origen y destino -> se reinicia la selección y
  ///   este toque se convierte en el nuevo Origen.
  void _handleMapTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      _errorMessage = null;

      if (_origin != null && _destination != null) {
        // Ya había una ruta completa: reiniciamos con un nuevo origen.
        _origin = point;
        _destination = null;
        _routePoints = [];
        _routeResult = null;
      } else if (_origin == null) {
        // No debería pasar normalmente (el GPS ya define el origen),
        // pero se contempla como fallback si el usuario no dio permiso.
        _origin = point;
      } else {
        // Origen ya existe, destino aún no: este toque lo define.
        _destination = point;
      }
    });

    // Si tras este toque ya tenemos ambos puntos, calculamos la ruta.
    if (_origin != null && _destination != null) {
      _calculateRoute();
    }
  }

  // ---------------------------------------------------------------------
  // Cálculo de ruta (OSRM)
  // ---------------------------------------------------------------------

  /// Consulta la ruta más corta entre origen y destino usando
  /// RoutingService, y actualiza la Polyline y el resultado en pantalla.
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
    final mapCenter = _origin ?? _fallbackCenter;

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
              initialCenter: mapCenter,
              initialZoom: 14,
              onTap: _handleMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.flutter_sensors_maps',
              ),

              // Polyline con la ruta calculada por OSRM.
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

              // Marcadores de origen y destino.
              MarkerLayer(
                markers: [
                  if (_origin != null)
                    Marker(
                      point: _origin!,
                      width: 44,
                      height: 44,
                      child: const Icon(
                        Icons.my_location,
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

          // Barra de instrucciones (superior).
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

          // Indicador de carga centrado (GPS o cálculo de ruta).
          if (_isLocating || _isRoutingLoading)
            const Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: _LoadingBadge(),
                ),
              ),
            ),

          // Mensaje de error (banner inferior, sobre el panel de resultados).
          if (_errorMessage != null)
            Positioned(
              bottom: _routeResult != null ? 100 : 16,
              left: 16,
              right: 16,
              child: _ErrorBanner(message: _errorMessage!),
            ),

          // Tarjeta flotante con distancia y tiempo estimado.
          if (_routeResult != null)
            Positioned(
              bottom: 16,
              left: 16,
              right: 16,
              child: _RouteInfoCard(result: _routeResult!),
            ),
        ],
      ),
      // FAB para volver a centrar el mapa en la ubicación actual.
      floatingActionButton: FloatingActionButton(
        onPressed: _recenterOnUser,
        tooltip: 'Centrar en mi ubicación',
        child: const Icon(Icons.my_location),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Excepciones
// ---------------------------------------------------------------------

/// Excepción lanzada cuando el usuario deniega el permiso de ubicación
/// o el servicio de ubicación está desactivado.
class LocationPermissionException implements Exception {
  final String message;
  LocationPermissionException(this.message);
}

// ---------------------------------------------------------------------
// Widgets auxiliares de UI
// ---------------------------------------------------------------------

/// Banner superior que informa el estado actual del flujo
/// (buscando ubicación, esperando destino, ruta lista).
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
      message = 'Obteniendo tu ubicación actual...';
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
      message = 'Ruta calculada. Toca de nuevo para elegir un nuevo origen.';
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

/// Insignia de carga centrada, usada tanto para el GPS como
/// para el cálculo de la ruta.
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

/// Banner de error mostrado sobre el mapa.
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
              child: Text(
                message,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta flotante inferior con la distancia y el tiempo estimado
/// de la ruta calculada.
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
            Container(
              width: 1,
              height: 36,
              color: Colors.grey.shade300,
            ),
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
        Text(
          value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}