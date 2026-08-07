import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Excepción personalizada para errores del servicio de rutas.
class RoutingException implements Exception {
  final String message;
  RoutingException(this.message);

  @override
  String toString() => 'RoutingException: $message';
}

/// Resultado de una consulta de ruta a OSRM.
class RouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;

  RouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
  });

  double get distanceKm => distanceMeters / 1000;
  double get durationMinutes => durationSeconds / 60;
}

/// Servicio que consulta la API pública de OSRM (sin API Key)
/// para obtener la ruta más corta entre dos coordenadas.
///
/// Usa el servidor demo público: https://router.project-osrm.org
/// Nota: este servidor es solo para pruebas/demostración, no tiene
/// SLA garantizado. Para producción se recomienda self-host de OSRM.
class RoutingService {
  static const String _baseUrl = 'https://router.project-osrm.org';

  /// Obtiene la ruta más corta entre [origin] y [destination]
  /// usando el perfil 'driving' (auto), 'walking' o 'cycling'.
  Future<RouteResult> getRoute({
    required LatLng origin,
    required LatLng destination,
    String profile = 'driving',
  }) async {
    // OSRM espera coordenadas como lon,lat
    final coordinates =
        '${origin.longitude},${origin.latitude};'
        '${destination.longitude},${destination.latitude}';

    final uri = Uri.parse(
      '$_baseUrl/route/v1/$profile/$coordinates'
      '?overview=full&geometries=geojson',
    );

    http.Response response;
    try {
      response = await http.get(uri).timeout(const Duration(seconds: 15));
    } catch (e) {
      throw RoutingException('Error de conexión con OSRM: $e');
    }

    if (response.statusCode != 200) {
      throw RoutingException(
        'OSRM respondió con código ${response.statusCode}',
      );
    }

    final Map<String, dynamic> data = jsonDecode(response.body);

    if (data['code'] != 'Ok') {
      throw RoutingException(
        'OSRM no pudo calcular la ruta: ${data['code']}',
      );
    }

    final List<dynamic> routes = data['routes'];
    if (routes.isEmpty) {
      throw RoutingException('No se encontraron rutas disponibles.');
    }

    final route = routes.first;
    final geometry = route['geometry'];
    final List<dynamic> coords = geometry['coordinates'];

    // GeoJSON devuelve [lon, lat], hay que invertir a LatLng(lat, lon)
    final List<LatLng> points = coords
        .map<LatLng>((c) => LatLng(c[1] as double, c[0] as double))
        .toList();

    return RouteResult(
      points: points,
      distanceMeters: (route['distance'] as num).toDouble(),
      durationSeconds: (route['duration'] as num).toDouble(),
    );
  }
}