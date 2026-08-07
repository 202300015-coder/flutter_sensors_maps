import 'dart:math';
import 'package:flutter/material.dart';

import '../services/accelerometer_service.dart';

/// Pantalla que muestra en tiempo real los valores del acelerómetro
/// (X, Y, Z) junto con un indicador visual de inclinación tipo "burbuja".
class AccelerometerScreen extends StatefulWidget {
  const AccelerometerScreen({super.key});

  @override
  State<AccelerometerScreen> createState() => _AccelerometerScreenState();
}

class _AccelerometerScreenState extends State<AccelerometerScreen> {
  // Servicio que expone el stream de lecturas del sensor.
  final AccelerometerService _service = AccelerometerService();

  // Última lectura recibida del acelerómetro.
  AccelerometerReading? _lastReading;

  // Controla si la lectura está activa o pausada.
  bool _isRunning = true;

  @override
  void initState() {
    super.initState();
    // Nos suscribimos al stream de lecturas.
    _service.readings.listen((reading) {
      // Solo actualizamos el estado si la pantalla sigue montada
      // y la lectura no está pausada.
      if (mounted && _isRunning) {
        setState(() => _lastReading = reading);
      }
    });
    _service.start();
  }

  @override
  void dispose() {
    // Liberamos los recursos del servicio al salir de la pantalla.
    _service.dispose();
    super.dispose();
  }

  /// Alterna entre pausar y reanudar la lectura del sensor.
  void _togglePauseResume() {
    setState(() {
      _isRunning = !_isRunning;
      if (_isRunning) {
        _service.start();
      } else {
        _service.stop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final reading = _lastReading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Acelerómetro'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Indicador visual: burbuja de nivel que se mueve
            // según los ejes X e Y del acelerómetro.
            _TiltIndicator(
              x: reading?.x ?? 0.0,
              y: reading?.y ?? 0.0,
            ),
            const SizedBox(height: 40),

            // Valores numéricos de cada eje.
            reading == null
                ? const CircularProgressIndicator()
                : Column(
                    children: [
                      _AxisValueRow(
                        label: 'X',
                        value: reading.x,
                        color: Colors.redAccent,
                      ),
                      const SizedBox(height: 8),
                      _AxisValueRow(
                        label: 'Y',
                        value: reading.y,
                        color: Colors.green,
                      ),
                      const SizedBox(height: 8),
                      _AxisValueRow(
                        label: 'Z',
                        value: reading.z,
                        color: Colors.blueAccent,
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
            const SizedBox(height: 40),

            // Botón de pausar / reanudar.
            ElevatedButton.icon(
              onPressed: _togglePauseResume,
              icon: Icon(_isRunning ? Icons.pause : Icons.play_arrow),
              label: Text(_isRunning ? 'Pausar lectura' : 'Reanudar lectura'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fila que muestra el label y el valor numérico de un eje del acelerómetro.
class _AxisValueRow extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const _AxisValueRow({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 10,
          backgroundColor: color,
          child: Text(
            label,
            style: const TextStyle(fontSize: 10, color: Colors.white),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 80,
          child: Text(
            value.toStringAsFixed(2),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// Indicador visual sencillo tipo "nivel de burbuja" (bubble level).
/// La burbuja se desplaza dentro de un círculo según la inclinación
/// del teléfono, calculada a partir de los ejes X e Y del acelerómetro.
class _TiltIndicator extends StatelessWidget {
  final double x;
  final double y;

  const _TiltIndicator({required this.x, required this.y});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: CustomPaint(
        painter: _TiltPainter(x: x, y: y),
      ),
    );
  }
}

class _TiltPainter extends CustomPainter {
  final double x;
  final double y;

  _TiltPainter({required this.x, required this.y});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;
    final ballRadius = 16.0;

    // Círculo exterior (marco del indicador).
    final framePaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    canvas.drawCircle(center, outerRadius - 2, framePaint);

    // Fondo del indicador.
    final backgroundPaint = Paint()..color = Colors.grey.shade100;
    canvas.drawCircle(center, outerRadius - 4, backgroundPaint);

    // Cálculo de la posición de la burbuja según X e Y.
    // Se limita (clamp) el desplazamiento para que la burbuja
    // no se salga del círculo exterior.
    final maxOffset = outerRadius - ballRadius - 4;
    final dx = (x / 9.8) * maxOffset; // 9.8 ≈ gravedad en m/s²
    final dy = (-y / 9.8) * maxOffset; // Se invierte Y para coincidir
                                        // con la orientación de pantalla.

    final distance = sqrt(dx * dx + dy * dy);
    final clampedFactor = distance > maxOffset ? maxOffset / distance : 1.0;

    final ballCenter = Offset(
      center.dx + dx * clampedFactor,
      center.dy + dy * clampedFactor,
    );

    // Color de la burbuja: cambia de verde (nivelado) a rojo (muy inclinado)
    // según qué tan lejos esté del centro.
    final tiltRatio = (distance / maxOffset).clamp(0.0, 1.0);
    final ballColor = Color.lerp(
      Colors.green,
      Colors.red,
      tiltRatio,
    )!;

    final ballPaint = Paint()..color = ballColor;
    canvas.drawCircle(ballCenter, ballRadius, ballPaint);

    // Punto central de referencia (nivel perfecto).
    final centerDotPaint = Paint()..color = Colors.grey.shade400;
    canvas.drawCircle(center, 3, centerDotPaint);
  }

  @override
  bool shouldRepaint(covariant _TiltPainter oldDelegate) {
    return oldDelegate.x != x || oldDelegate.y != y;
  }
}