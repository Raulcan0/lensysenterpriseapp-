import 'package:flutter/material.dart';

class TablaPuntuacionGlobal extends StatelessWidget {
  final Map<String, Map<String, double>> promediosPorDimension;

  const TablaPuntuacionGlobal({
    super.key,
    required this.promediosPorDimension,
    required Map<String, double> puntuacionGlobal,
  });

  static const List<Map<String, dynamic>> sections = [
    {
      'label': 'Impulsores Culturales (250 pts)',
      'dimensionId': '1',
      'comps': ['EJECUTIVOS', 'GERENTES', 'MIEMBROS DE EQUIPO'],
      'compsText': ['EJECUTIVOS 50%', 'GERENTES 30%', 'MIEMBROS DE EQUIPO 20%'],
      'puntos': [125.0, 75.0, 50.0],
      'maxDim': 250.0,
    },
    {
      'label': 'Mejora Continua (350 pts)',
      'dimensionId': '2',
      'comps': ['EJECUTIVOS', 'GERENTES', 'MIEMBROS DE EQUIPO'],
      'compsText': ['EJECUTIVOS 20%', 'GERENTES 30%', 'MIEMBROS DE EQUIPO 50%'],
      'puntos': [70.0, 105.0, 175.0],
      'maxDim': 350.0,
    },
    {
      'label': 'Alineamiento Empresarial (200 pts)',
      'dimensionId': '3',
      'comps': ['EJECUTIVOS', 'GERENTES', 'MIEMBROS DE EQUIPO'],
      'compsText': ['EJECUTIVOS 55%', 'GERENTES 30%', 'MIEMBROS DE EQUIPO 15%'],
      'puntos': [110.0, 60.0, 30.0],
      'maxDim': 200.0,
    },
  ];

  String _normalizeCargo(String c) {
    final up = c.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (up == 'MIEMBRO' || up == 'MIEMBRO DE EQUIPO' || up == 'MIEMBROS') {
      return 'MIEMBROS DE EQUIPO';
    }
    return up;
  }

  double _valorCargo5(String dimensionId, String cargo) {
    final mapa = promediosPorDimension[dimensionId];
    if (mapa == null || mapa.isEmpty) return 0.0;

    final objetivo = _normalizeCargo(cargo);
    for (final entry in mapa.entries) {
      if (_normalizeCargo(entry.key) == objetivo) return entry.value;
    }
    return 0.0;
  }

  double _porcentajeCargo(String dimensionId, String cargo) {
    final v = _valorCargo5(dimensionId, cargo).clamp(0.0, 5.0);
    return (v / 5.0) * 100.0;
  }

  double _puntosCargo(String dimensionId, String cargo, double puntosPosibles) {
    return _porcentajeCargo(dimensionId, cargo) / 100.0 * puntosPosibles;
  }

  double _promedioGeneralDimension(String dimensionId) {
    final mapa = promediosPorDimension[dimensionId];
    if (mapa == null || mapa.isEmpty) return 0.0;

    final Map<String, double> norm = {};
    for (final e in mapa.entries) {
      final k = _normalizeCargo(e.key);
      if (k == 'EJECUTIVOS' || k == 'GERENTES' || k == 'MIEMBROS DE EQUIPO') {
        norm[k] = e.value;
      }
    }

    if (norm.isEmpty) return 0.0;
    return norm.values.reduce((a, b) => a + b) / norm.length;
  }

  @override
  Widget build(BuildContext context) {
    final rows = <DataRow>[];
    double totalPuntosObtenidos = 0.0;
    double totalPuntosPosibles = 0.0;

    for (final section in sections) {
      final label = section['label'] as String;
      final dimensionId = section['dimensionId'] as String;
      final comps = (section['comps'] as List).cast<String>();
      final compsText = (section['compsText'] as List).cast<String>();
      final puntos = (section['puntos'] as List).cast<double>();
      final maxDim = section['maxDim'] as double;

      final p0 = _puntosCargo(dimensionId, comps[0], puntos[0]);
      final p1 = _puntosCargo(dimensionId, comps[1], puntos[1]);
      final p2 = _puntosCargo(dimensionId, comps[2], puntos[2]);

      final promDim = _promedioGeneralDimension(dimensionId).clamp(0.0, 5.0);
      final ptsDim = (promDim / 5.0) * maxDim;
      final pctDim = (promDim / 5.0) * 100.0;

      totalPuntosObtenidos += (p0 + p1 + p2);
      totalPuntosPosibles += (puntos[0] + puntos[1] + puntos[2]);

      rows.addAll([
        DataRow(
          color: WidgetStateProperty.all(const Color(0xFF003056)),
          cells: [
            DataCell(Text(label, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12))),
            DataCell(Text(compsText[0], style: const TextStyle(color: Colors.white, fontSize: 12))),
            DataCell(Text(compsText[1], style: const TextStyle(color: Colors.white, fontSize: 12))),
            DataCell(Text(compsText[2], style: const TextStyle(color: Colors.white, fontSize: 12))),
          ],
        ),
        DataRow(
          cells: [
            const DataCell(Text('Puntos posibles', style: TextStyle(fontSize: 12))),
            DataCell(Text(puntos[0].toStringAsFixed(0), style: const TextStyle(fontSize: 12))),
            DataCell(Text(puntos[1].toStringAsFixed(0), style: const TextStyle(fontSize: 12))),
            DataCell(Text(puntos[2].toStringAsFixed(0), style: const TextStyle(fontSize: 12))),
          ],
        ),
        DataRow(
          cells: [
            const DataCell(Text('% Obtenido por cargo', style: TextStyle(fontSize: 12))),
            DataCell(Text('${_porcentajeCargo(dimensionId, comps[0]).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12))),
            DataCell(Text('${_porcentajeCargo(dimensionId, comps[1]).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12))),
            DataCell(Text('${_porcentajeCargo(dimensionId, comps[2]).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12))),
          ],
        ),
        DataRow(
          cells: [
            const DataCell(Text('Puntos obtenidos por cargo', style: TextStyle(fontSize: 12))),
            DataCell(Text(p0.toStringAsFixed(1), style: const TextStyle(fontSize: 12))),
            DataCell(Text(p1.toStringAsFixed(1), style: const TextStyle(fontSize: 12))),
            DataCell(Text(p2.toStringAsFixed(1), style: const TextStyle(fontSize: 12))),
          ],
        ),
        DataRow(
          cells: [
            const DataCell(Text('Total Dimensión', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
            DataCell(Text('${ptsDim.toStringAsFixed(1)} pts', style: const TextStyle(fontSize: 12))),
            DataCell(Text('${pctDim.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12))),
            const DataCell(Text('')),
          ],
        ),
      ]);
    }

    rows.add(
      DataRow(
        color: WidgetStateProperty.all(const Color(0xFF003056)),
        cells: [
          const DataCell(Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12))),
          DataCell(Text(
            '${totalPuntosObtenidos.toStringAsFixed(1)} / ${totalPuntosPosibles.toStringAsFixed(0)}',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 12),
          )),
          const DataCell(Text('')),
          const DataCell(Text('')),
        ],
      ),
    );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 2,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: DataTable(
            headingRowHeight: 0,
            dataRowMinHeight: 22,
            dataRowMaxHeight: 30,
            columnSpacing: 24,
            border: TableBorder.all(color: const Color(0xFF003056), width: 0.6),
            columns: const [
              DataColumn(label: SizedBox.shrink()),
              DataColumn(label: SizedBox.shrink()),
              DataColumn(label: SizedBox.shrink()),
              DataColumn(label: SizedBox.shrink()),
            ],
            rows: rows,
          ),
        ),
      ),
    );
  }
}
