import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class MultiRingChart extends StatelessWidget {
  final Map<String, double>
  puntosObtenidos; // e.g. {'Impulsores Culturales': 3.5, ...}
  final bool isDetail;

  const MultiRingChart({
    super.key,
    required this.puntosObtenidos,
    this.isDetail = false,
  });

  // Puntaje máximo por dimensión (convertido de escala 5.0 a puntos)
  static const Map<String, double> puntosTotales = {
    'IMPULSORES CULTURALES': 250.0, // 250 puntos máximo
    'MEJORA CONTINUA': 350.0, // 350 puntos máximo
    'ALINEAMIENTO EMPRESARIAL': 200.0, // 200 puntos máximo
  };

  static const Map<String, Color> coloresPorDimension = {
    'IMPULSORES CULTURALES': Color.fromARGB(255, 122, 141, 245), // azul
    'MEJORA CONTINUA': Color.fromARGB(255, 67, 78, 141), // azul oscuro
    'ALINEAMIENTO EMPRESARIAL': Color.fromARGB(
      255,
      14,
      24,
      78,
    ), // azul más oscuro
  };

  @override
  Widget build(BuildContext context) {
    final List<String> dimensiones = puntosTotales.keys.toList();
    final int n = dimensiones.length;

    // Log para depuración
    debugPrint('MultiRingChart recibió datos: $puntosObtenidos');

    return LayoutBuilder(
      builder: (context, constraints) {
        final double chartSize =
            (isDetail ? 0.8 : 0.6) *
            (constraints.maxWidth < constraints.maxHeight
                ? constraints.maxWidth
                : constraints.maxHeight);
        final double maxRadius = chartSize / 2;
        final double ringWidth = (maxRadius * 0.6) / n;
        final double centerRadius = maxRadius * 0.3;

        return Column(
          children: [
            const SizedBox(height: 40),
            SizedBox(
              width: chartSize,
              height: chartSize,
              child: Stack(
                alignment: Alignment.center,
                children: List.generate(n, (index) {
                  final nombre = dimensiones[index];
                  final double totalPuntos = puntosTotales[nombre]!;
                  final double promedioObtenido = puntosObtenidos[nombre] ?? 0;
                  final double porcentaje = (promedioObtenido / 5.0).clamp(
                    0.0,
                    1.0,
                  );
                  final double outerRadius = maxRadius - index * ringWidth;
                  final double innerRadius = outerRadius - ringWidth;
                  final double actualCenterRadius =
                      index == n - 1 ? centerRadius : innerRadius;
                  return PieChart(
                    PieChartData(
                      startDegreeOffset: -90,
                      sectionsSpace: 0,
                      centerSpaceRadius: actualCenterRadius,
                      sections: [
                        PieChartSectionData(
                          value: porcentaje * totalPuntos,
                          color: coloresPorDimension[nombre],
                          radius: outerRadius,
                          showTitle: false,
                        ),
                        PieChartSectionData(
                          value: (1 - porcentaje) * totalPuntos,
                          color: Colors.white,
                          radius: outerRadius,
                          showTitle: false,
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 32),
            _buildLegend(),
            const SizedBox(height: 4),
          ],
        );
      },
    );
  }

  Widget _buildLegend() {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 8,
      children:
          puntosTotales.keys.map((nombre) {
            final promedioObtenido =
                puntosObtenidos[nombre] ?? 0; // Promedio 0-5
            final totalPuntos = puntosTotales[nombre]!;

            // Convertir promedio (0-5) a puntos (0-totalPuntos)
            final puntosCalculados = (promedioObtenido / 5.0) * totalPuntos;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color.fromARGB(255, 255, 255, 255),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Indicador de color
                  Container(
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      color: coloresPorDimension[nombre],
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Texto con nombre y valor
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        nombre,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF003056),
                        ),
                      ),
                      Text(
                        '${puntosCalculados.round()}/${totalPuntos.round()}pts',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color.fromARGB(255, 0, 0, 0),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
    );
  }
}
