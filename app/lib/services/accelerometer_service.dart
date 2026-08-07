import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';

/// Modelo simple para representar una lectura del acelerómetro.
class AccelerometerReading {
  final double x;
  final double y;
  final double z;
  final DateTime timestamp;

  AccelerometerReading({
    required this.x,
    required this.y,
    required this.z,
    required this.timestamp,
  });

  @override
  String toString() =>
      'X: ${x.toStringAsFixed(2)}, Y: ${y.toStringAsFixed(2)}, Z: ${z.toStringAsFixed(2)}';
}

/// Servicio que expone un stream con los datos del acelerómetro
/// usando el paquete sensors_plus.
class AccelerometerService {
  StreamSubscription<AccelerometerEvent>? _subscription;
  final StreamController<AccelerometerReading> _controller =
      StreamController<AccelerometerReading>.broadcast();

  /// Stream público al que se pueden suscribir los widgets.
  Stream<AccelerometerReading> get readings => _controller.stream;

  /// Inicia la escucha del sensor.
  /// [samplingPeriod] permite ajustar la frecuencia de muestreo.
  void start({Duration samplingPeriod = SensorInterval.normalInterval}) {
    _subscription?.cancel();
    _subscription = accelerometerEventStream(
      samplingPeriod: samplingPeriod,
    ).listen(
      (AccelerometerEvent event) {
        _controller.add(
          AccelerometerReading(
            x: event.x,
            y: event.y,
            z: event.z,
            timestamp: DateTime.now(),
          ),
        );
      },
      onError: (Object error) {
        _controller.addError(error);
      },
      cancelOnError: false,
    );
  }

  /// Detiene la escucha del sensor.
  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  /// Libera los recursos. Llamar en el dispose() del widget que lo use.
  void dispose() {
    stop();
    _controller.close();
  }
}