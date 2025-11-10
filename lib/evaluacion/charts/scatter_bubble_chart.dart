// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

/// Datos individuales por cargo en cada principio
class ScatterData {
  final double x; // Promedio obtenido (0.0 - 5.0)
  final double y; // Índice fijo del principio (1 - 10)
  final Color color; // Color según el cargo (Ejecutivo, Gerente, Miembro)
  final String cargo;
  final double radius;

  const ScatterData({
    required this.x,
    required this.y,
    required this.color,
    required this.cargo,
    this.radius = 18,
  });
}

/// Gráfico de burbujas fijo (principios en eje Y, promedios en eje X)
class ScatterBubbleChart extends StatelessWidget {
  final List<ScatterData> data;

  // Lista fija de principios (no se modifica)
  static const List<String> principleNames = [
    'Respetar A Cada Individuo',
    'Liderar Con Humildad',
    'Buscar La Perfección',
    'Abrazar el Pensamiento Científico',
    'Enfocarse En El Proceso',
    'Asegurar la Calidad en la Fuente',
    'Mejorar el Flujo y Jalón de Valor',
    'Pensar Sistémicamente',
    'Crear Constancia de Propósito',
    'Crear Valor para el Cliente',
  ];

  const ScatterBubbleChart({
    super.key,
    required this.data, required bool isDetail,
  });

  @override
  Widget build(BuildContext context) {
    const double minX = 0.0;
    const double maxX = 5.0;
    const double minY = 1.0;
    final double maxY = principleNames.length.toDouble();

    // Generar puntos dinámicos, pero sin alterar estructura
    final puntos = data.map((d) {
      return ScatterSpot(
        d.x.clamp(minX, maxX),
        d.y.clamp(minY, maxY),
        dotPainter: FlDotCirclePainter(
          color: d.color,
          radius: d.radius,
        ),
      );
    }).toList();

    // Calculamos un ancho proporcional para que haya scroll horizontal
    const double baseWidthPerStep = 120; // espacio horizontal base por paso 0.5
    final double totalWidth = (maxX - minX) / 0.5 * baseWidthPerStep;

    return ScrollConfiguration(
      behavior: const ScrollBehavior().copyWith(scrollbars: true),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: totalWidth,
          height: principleNames.length * 50 + 150,
          child: ScatterChart(
            ScatterChartData(
              minX: minX,
              maxX: maxX,
              minY: minY,
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawHorizontalLine: true,
                drawVerticalLine: true,
                horizontalInterval: 1,
                verticalInterval: 0.5,
                getDrawingHorizontalLine: (value) => FlLine(
                  color: Colors.grey.withOpacity(0.3),
                  strokeWidth: 1,
                ),
                getDrawingVerticalLine: (value) => FlLine(
                  color: Colors.grey.withOpacity(0.3),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: const Border(
                  bottom: BorderSide(color: Colors.black, width: 2),
                  left: BorderSide(color: Colors.black, width: 2),
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    reservedSize: 200,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (idx >= 1 && idx <= principleNames.length) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: SizedBox(
                            width: 180,
                            child: Text(
                              principleNames[idx - 1],
                              style: const TextStyle(
                                fontSize: 13,
                                color: Colors.black,
                              ),
                              textAlign: TextAlign.right,
                              maxLines: 2,
                              overflow: TextOverflow.visible,
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 0.5,
                    getTitlesWidget: (value, meta) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        value.toStringAsFixed(1),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.black,
                        ),
                      ),
                    ),
                  ),
                ),
                topTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              scatterSpots: puntos,
              scatterTouchData: ScatterTouchData(
                enabled: true,
                handleBuiltInTouches: true,
                touchTooltipData: ScatterTouchTooltipData(
                  getTooltipItems: (ScatterSpot touchedSpot) {
                    return ScatterTooltipItem(
                      'Promedio: ${touchedSpot.x.toStringAsFixed(2)}',
                      textStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
