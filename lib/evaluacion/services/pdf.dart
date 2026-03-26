import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

class NivelEvaluacion {
  final double valor;
  final String interpretacion;
  final String benchmarkPorCargo;
  final String obs;
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
  final String nombre;
  final String benchmarkGeneral;
  final Map<String, NivelEvaluacion> niveles;

  ReporteComportamiento({
    required this.nombre,
    required this.benchmarkGeneral,
    required this.niveles,
  });
}

class ReportePdfService {
  static Future<Uint8List> generarReportePdf(
    List<ReporteComportamiento> datos,
  ) async {
    // 🔹 Cargar fuente Roboto (Unicode)
    final fontData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final fontBoldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    final roboto = pw.Font.ttf(fontData.buffer.asByteData());
    final robotoBold = pw.Font.ttf(fontBoldData.buffer.asByteData());

    final pdf = pw.Document();
    final txtSmall = pw.TextStyle(font: roboto, fontSize: 9);
    final txtNormal = pw.TextStyle(font: roboto, fontSize: 10);
    final headerStyle = pw.TextStyle(
      font: robotoBold,
      fontSize: 12,
      fontWeight: pw.FontWeight.bold,
    );

    final evidenciaBytes = <String, Uint8List>{};

    for (final comp in datos) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          build: (context) => [
            pw.Text("BENCHMARK DE COMPORTAMIENTOS", style: headerStyle),
            pw.SizedBox(height: 6),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey700),
                color: PdfColors.grey200,
              ),
              child: pw.Text(comp.benchmarkGeneral, style: txtNormal),
            ),
            pw.SizedBox(height: 10),
            _tablaNiveles(comp, headerStyle, txtSmall, roboto),
            pw.SizedBox(height: 20),
            pw.Divider(),
            pw.SizedBox(height: 10),
            pw.Center(child: pw.Text("Resumen Gráfico", style: headerStyle)),
          ],
        ),
      );

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Center(
                child: pw.Container(
                  alignment: pw.Alignment.center,
                  width: PdfPageFormat.a4.width * 0.7,
                  height: 180,
                  child: _buildVerticalBarChartConEscala(comp, robotoBold),
                ),
              ),
              pw.SizedBox(height: 25),
              _campoRecomendacion(headerStyle),
            ],
          ),
        ),
      );

      for (final nivel in ['E', 'G', 'M']) {
        final url = comp.niveles[nivel]?.evidenciaUrl;
        if (url != null && url.isNotEmpty) {
          try {
            final response = await http.get(Uri.parse(url));
            if (response.statusCode == 200) {
              evidenciaBytes["${comp.nombre}-$nivel"] = response.bodyBytes;
            }
          } catch (_) {}
        }
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        build: (context) => [
          pw.Text("EVIDENCIAS POR COMPORTAMIENTO Y NIVEL", style: headerStyle),
          pw.SizedBox(height: 10),
          _tablaEvidencias(datos, evidenciaBytes, headerStyle, txtNormal),
        ],
      ),
    );

    return pdf.save();
  }

  static pw.Widget _tablaNiveles(
    ReporteComportamiento comp,
    pw.TextStyle headerStyle,
    pw.TextStyle cellStyle,
    pw.Font font,
  ) {
    const nivelesOrdenados = ['E', 'G', 'M'];
    String getNivelNombre(String key) {
      switch (key) {
        case 'E':
          return 'Ejecutivo';
        case 'G':
          return 'Gerente';
        case 'M':
          return 'Miembro de Equipo';
        default:
          return key;
      }
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey700, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(5),
        3: const pw.FlexColumnWidth(5),
        4: const pw.FlexColumnWidth(3),
        5: const pw.FlexColumnWidth(3),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            for (final title in [
              "Nivel",
              "Valor",
              "Interpretación",
              "Benchmark por Cargo",
              "Sistemas",
              "Hallazgos"
            ])
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(title, style: headerStyle),
              ),
          ],
        ),
        for (final key in nivelesOrdenados)
          if (comp.niveles[key] != null)
            pw.TableRow(
              children: [
                pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child:
                        pw.Text(getNivelNombre(key), style: cellStyle)),
                pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text(
                        comp.niveles[key]!.valor.toStringAsFixed(2),
                        style: cellStyle)),
                pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text(comp.niveles[key]!.interpretacion,
                        style: cellStyle)),
                pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text(
                        comp.niveles[key]!.benchmarkPorCargo,
                        style: cellStyle)),
                pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text(
                        comp.niveles[key]!.sistemasSeleccionados.isEmpty
                            ? "Sin sistemas"
                            : comp.niveles[key]!.sistemasSeleccionados.join(", "),
                        style: cellStyle)),
                pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text(comp.niveles[key]!.obs,
                        style: cellStyle)),
              ],
            ),
      ],
    );
  }

  static pw.Widget _buildVerticalBarChartConEscala(
      ReporteComportamiento comp, pw.Font fontBold) {
    final labels = ['Ejecutivo', 'Gerente', 'Miembro'];
    final values = [
      comp.niveles['E']?.valor ?? 0,
      comp.niveles['G']?.valor ?? 0,
      comp.niveles['M']?.valor ?? 0,
    ];

    const maxY = 5.0;
    const barColors = [PdfColors.orange, PdfColors.green, PdfColors.blue];
    const barWidth = 30.0;

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: List.generate(3, (i) {
        final barHeight = (values[i] / maxY) * 100;
        return pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12),
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Container(
                width: barWidth,
                height: barHeight,
                color: barColors[i],
              ),
              pw.SizedBox(height: 5),
              pw.Text(values[i].toStringAsFixed(2),
                  style: pw.TextStyle(font: fontBold, fontSize: 8)),
              pw.SizedBox(height: 3),
              pw.Text(labels[i],
                  style: pw.TextStyle(
                      font: fontBold,
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: barColors[i])),
            ],
          ),
        );
      }),
    );
  }

  static pw.Widget _campoRecomendacion(pw.TextStyle headerStyle) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        border: pw.Border.all(color: PdfColors.grey700),
      ),
      child: pw.Text("Recomendaciones:", style: headerStyle),
    );
  }

  static pw.Widget _tablaEvidencias(
    List<ReporteComportamiento> datos,
    Map<String, Uint8List> evidenciaBytes,
    pw.TextStyle headerStyle,
    pw.TextStyle txtNormal,
  ) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey700),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FlexColumnWidth(6),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text('Comportamiento', style: headerStyle)),
            pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text('Nivel', style: headerStyle)),
            pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text('Evidencia', style: headerStyle)),
          ],
        ),
        for (final comp in datos)
          for (final nivel in ['E', 'G', 'M'])
            if (comp.niveles[nivel]?.evidenciaUrl != null)
              pw.TableRow(
                children: [
                  pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text(comp.nombre, style: txtNormal)),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text(
                      nivel == 'E'
                          ? 'Ejecutivo'
                          : nivel == 'G'
                              ? 'Gerente'
                              : 'Miembro de Equipo',
                      style: txtNormal,
                    ),
                  ),
                  pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: evidenciaBytes["${comp.nombre}-$nivel"] != null
                        ? pw.Image(
                            pw.MemoryImage(
                                evidenciaBytes["${comp.nombre}-$nivel"]!),
                            height: 60)
                        : pw.Text("Sin imagen", style: txtNormal),
                  ),
                ],
              ),
      ],
    );
  }
}
