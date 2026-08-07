import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../services/routing_service.dart';

/// Pantalla que muestra un mapa interactivo (OpenStreetMap vía flutter_map)
/// donde el usuario puede tocar para marcar Origen y Destino, calcular
/// la ruta más corta con OSRM y visualizar distancia/tiempo estimado.
class RouteOptimizerScreen extends StatefulWidget {
  const RouteOptimizerScreen({super.key});

  @override
  State<RouteOptimizerScreen> createState() => _RouteOptimizerScreenState();
}

/// Modo de selección activo: qué punto se está marcando al tocar el mapa.
enum _SelectionMode { origin, destination }

class _RouteOptimizerScreenState extends State<RouteOptimizerScreen> {
  final RoutingService _routingService = RoutingService();
  final MapController _mapController = MapController();

  // Puntos seleccionados por el usuario.
  LatLng? _origin;
  LatLng? _destination;

  // Puntos de la ruta calculada (para dibujar la Polyline).
  List<LatLng> _routePoints = [];

  // Modo actual de selección (origen o destino).
  _SelectionMode _selectionMode = _SelectionMode.origin;

  // Estado de carga y error.
  bool _isLoading = false;
  String? _errorMessage;

  // Resultado de la ruta (distancia y duración).
  RouteResult? _routeResult;

  /// Maneja el toque sobre el mapa: asigna el punto tocado como
  /// origen o destino según el modo de selección activo.
  void _handleMapTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      _errorMessage = null;
      if (_selectionMode == _SelectionMode.origin) {
        _origin = point;
        // Tras marcar origen, pasamos automáticamente a destino.
        _selectionMode = _SelectionMode.destination;
      } else {
        _destination = point;
      }
      // Si el usuario vuelve a tocar, se invalida la ruta previa
      // hasta que se recalcule.
      _routePoints = [];
      _routeResult = null;
    });
  }

  /// Limpia todos los puntos y la ruta actual.
  void _resetSelection() {
    setState(() {
      _origin = null;
      _destination = null;
      _routePoints = [];
      _routeResult = null;
      _errorMessage = null;
      _selectionMode = _SelectionMode.origin;
    });
  }

  /// Solicita al servicio de rutas la ruta más corta entre
  /// el origen y destino seleccionados, y actualiza el mapa.
  Future<void> _calculateRoute() async {
    if (_origin == null || _destination == null) {
      setState(() {
        _errorMessage = 'Selecciona primero un origen y un destino en el mapa.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
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

      // Ajustamos la cámara para que se vea toda la ruta.
      if (_routePoints.isNotEmpty) {
        _mapController.fitCamera(
          CameraFit.coordinates(
            coordinates: _routePoints,
            padding: const EdgeInsets.all(48),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'No se pudo calcular la ruta: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Optimizador de Rutas'),
        actions: [
          IconButton(
            tooltip: 'Limpiar selección',
            icon: const Icon(Icons.refresh),
            onPressed: _resetSelection,
          ),
        ],
      ),
      body: Column(
        children: [
          // Barra de instrucciones: indica qué punto se está seleccionando.
          _InstructionBar(
            selectionMode: _selectionMode,
            hasOrigin: _origin != null,
            hasDestination: _destination != null,
          ),

          // Mapa interactivo.
          Expanded(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                // Centro inicial de ejemplo (Ciudad de México).
                initialCenter: const LatLng(19.4326, -99.1332),
                initialZoom: 12,
                onTap: _handleMapTap,
              ),
              children: [
                // Capa base de tiles de OpenStreetMap.
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
                          Icons.trip_origin,
                          color: Colors.green,
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
          ),

          // Mensaje de error, si existe.
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),

          // Panel inferior con resultado (distancia/tiempo) y botón de acción.
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 6,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_routeResult != null) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _ResultChip(
                        icon: Icons.straighten,
                        label:
                            '${_routeResult!.distanceKm.toStringAsFixed(2)} km',
                      ),
                      _ResultChip(
                        icon: Icons.access_time,
                        label:
                            '${_routeResult!.durationMinutes.toStringAsFixed(0)} min',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _calculateRoute,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.alt_route),
                    label: Text(
                      _isLoading ? 'Calculando ruta...' : 'Calcular ruta más corta',
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Barra superior que guía al usuario sobre qué punto debe tocar
/// a continuación en el mapa (origen o destino).
class _InstructionBar extends StatelessWidget {
  final _SelectionMode selectionMode;
  final bool hasOrigin;
  final bool hasDestination;

  const _InstructionBar({
    required this.selectionMode,
    required this.hasOrigin,
    required this.hasDestination,
  });

  @override
  Widget build(BuildContext context) {
    String message;
    IconData icon;
    Color color;

    if (!hasOrigin) {
      message = 'Toca el mapa para marcar el ORIGEN';
      icon = Icons.trip_origin;
      color = Colors.green;
    } else if (!hasDestination) {
      message = 'Toca el mapa para marcar el DESTINO';
      icon = Icons.flag;
      color = Colors.red;
    } else {
      message = 'Origen y destino listos. Presiona "Calcular ruta".';
      icon = Icons.check_circle;
      color = Colors.blue;
    }

    return Container(
      width: double.infinity,
      color: color.withOpacity(0.1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
    );
  }
}

/// Chip pequeño para mostrar un resultado (distancia o tiempo) con ícono.
class _ResultChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ResultChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 18, color: Colors.blueAccent),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      backgroundColor: Colors.blue.shade50,
    );
  }
}