import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class NivelEvaluacion {
  final double valor;
  final String interpretacion, benchmarkPorCargo, obs;
  final List<String> sistemasSeleccionados;
  final String? evidenciaUrl;

  NivelEvaluacion({
    required this.valor,
    required this.interpretacion,
    required this.benchmarkPorCargo,
    required this.obs,
    required this.sistemasSeleccionados,
    this.evidenciaUrl,
  });
}

class ReporteComportamiento {
  final String nombre, benchmarkGeneral;
  final Map<String, NivelEvaluacion> niveles;

  ReporteComportamiento({
    required this.nombre,
    required this.benchmarkGeneral,
    required this.niveles,
  });
}

class ReporteWordService {
  static Future<String> generarReporteWord(
      List<ReporteComportamiento> datos, String nombreEmpresa) async {
    final evidencias = <String, Uint8List>{};

    // Descargar evidencias
    for (final c in datos) {
      for (final nKey in ['E', 'G', 'M']) {
        final n = c.niveles[nKey];
        if (n?.evidenciaUrl != null && n!.evidenciaUrl!.isNotEmpty) {
          try {
            final r = await http.get(Uri.parse(n.evidenciaUrl!));
            if (r.statusCode == 200) {
              evidencias['${c.nombre}-$nKey'] = r.bodyBytes;
            }
          } catch (_) {}
        }
      }
    }

    final b = StringBuffer();
    b.writeln('''
<html><head><meta charset="UTF-8"><style>
body{font-family:Arial;font-size:11pt;margin:0;}
@page Section1{size:297mm 210mm;margin:1.5cm;}
div.Section1{page:Section1;}
table{border-collapse:collapse;width:100%;margin-bottom:16px;}
th,td{border:1px solid #888;padding:5px;text-align:left;}th{background:#f0f0f0;}
h2{font-size:14pt;margin-top:10px;}
</style></head><body><div class="Section1">
<h1 style="text-align:center;">REPORTE DE COMPORTAMIENTOS</h1>
<h3 style="text-align:center;">Empresa: ${_e(nombreEmpresa)}</h3><hr>
''');

    for (final c in datos) {
      b.writeln('<h2>${_e(c.nombre)}</h2>'
          '<p><b>Benchmark general:</b> ${_e(c.benchmarkGeneral)}</p>'
          '<table>'
          '<tr><th>Nivel</th><th>Valor</th><th>Interpretación</th><th>Benchmark</th><th>Sistemas</th><th>Obs</th></tr>');

      // Fila por cada nivel
      for (final k in ['E', 'G', 'M']) {
        final n = c.niveles[k];
        final nivel = {'E': 'Ejecutivo', 'G': 'Gerente', 'M': 'Miembro'}[k]!;
        if (n == null) {
          b.writeln(
              '<tr><td>$nivel</td><td>0.00</td><td>-</td><td>-</td><td>-</td><td>-</td></tr>');
        } else {
          b.writeln('<tr>'
              '<td>$nivel</td>'
              '<td>${n.valor.toStringAsFixed(2)}</td>'
              '<td>${_e(n.interpretacion)}</td>'
              '<td>${_e(n.benchmarkPorCargo)}</td>'
              '<td>${n.sistemasSeleccionados.isEmpty ? 'Sin sistemas' : _e(n.sistemasSeleccionados.join(", "))}</td>'
              '<td>${_e(n.obs)}</td>'
              '</tr>');
        }
      }
      b.writeln('</table>');

      // === GRÁFICO DE BARRAS ===
      final eVal = c.niveles['E']?.valor ?? 0;
      final gVal = c.niveles['G']?.valor ?? 0;
      final mVal = c.niveles['M']?.valor ?? 0;

      final chartCfg = {
        'type': 'bar',
        'data': {
          'labels': ['Ejecutivo', 'Gerente', 'Miembro'],
          'datasets': [
            {
              'label': 'Nivel',
              'data': [eVal, gVal, mVal],
              'backgroundColor': ['#4caf50', '#2196f3', '#ffca28'],
              'barPercentage': 0.6,
              'categoryPercentage': 0.8
            }
          ]
        },
        'options': {
          'responsive': false,
          'maintainAspectRatio': false,
          'plugins': {
            'legend': {'display': false},
            'title': {'display': false}
          },
          'scales': {
            'x': {
              'grid': {'display': false},
              'ticks': {'color': 'black', 'font': {'size': 12}}
            },
            'y': {
              'beginAtZero': true,
              'max': 5,
              'ticks': {'stepSize': 1, 'color': 'black', 'font': {'size': 12}},
              'grid': {'color': 'rgba(0,0,0,0.1)'}
            }
          }
        }
      };

      Uint8List? chart;
      try {
        final uri =
            'https://quickchart.io/chart?width=600&height=300&c=${Uri.encodeComponent(jsonEncode(chartCfg))}';
        final r = await http.get(Uri.parse(uri));
        if (r.statusCode == 200) chart = r.bodyBytes;
      } catch (_) {}

      if (chart != null) {
        b.writeln(
            '<p style="text-align:center;"><img src="data:image/png;base64,${base64Encode(chart)}" width="600" height="300"/></p>');
      } else {
        b.writeln(
            '<div style="width:600px;height:300px;border:1px dashed #999;text-align:center;">[Sin gráfico]</div>');
      }

      b.writeln('<hr>');
    }

    // Evidencias
    b.writeln('<h2>Evidencias</h2>'
        '<table><tr><th>Comportamiento</th><th>Nivel</th><th>Imagen</th></tr>');
    for (final c in datos) {
      for (final k in ['E', 'G', 'M']) {
        final key = '${c.nombre}-$k';
        final n = c.niveles[k];
        final nivel = {'E': 'Ejecutivo', 'G': 'Gerente', 'M': 'Miembro'}[k]!;
        b.writeln('<tr><td>${_e(c.nombre)}</td><td>$nivel</td>');
        if (n != null && evidencias.containsKey(key)) {
          b.writeln(
              '<td><img src="data:image/png;base64,${base64Encode(evidencias[key]!)}" style="max-height:90px;"/></td>');
        } else {
          b.writeln('<td>Sin imagen</td>');
        }
        b.writeln('</tr>');
      }
    }
    b.writeln('</table></div></body></html>');

    // Guardar archivo
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/Reporte_${nombreEmpresa.replaceAll(' ', '_')}.doc');
    await f.writeAsString(b.toString(), encoding: utf8);
    return f.path;
  }

  static String _e(String? s) => s == null
      ? ''
      : s
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;')
          .replaceAll('"', '&quot;');
}
