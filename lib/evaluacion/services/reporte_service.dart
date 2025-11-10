import 'dart:io';
import 'package:applensys/evaluacion/services/pdf.dart' as pdf;
import 'package:applensys/evaluacion/services/word.dart' as word;
import 'package:applensys/evaluacion/services/excel.dart';

import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class ReporteService {
  static Future<void> generarYSubirReporte({
    required String formato,
    required List<pdf.ReporteComportamiento> datos,
    required String nombreEmpresa,
    List<String>? recomendaciones,
    required Function(String mensaje) onStatus,
  }) async {
    final directory = await getApplicationDocumentsDirectory();
    final nombreEmpresaSan = nombreEmpresa.replaceAll(' ', '_');
    String fileName;
    File file;

    try {
      onStatus('Generando reporte...');

      // 🔹 WORD
      if (formato.toUpperCase().contains('WORD')) {
        fileName = 'Reporte_$nombreEmpresaSan.docx';

        // 🔄 Convertir lista PDF → WORD
        final datosWord = datos.map((d) => word.ReporteComportamiento(
              nombre: d.nombre,
              benchmarkGeneral: d.benchmarkGeneral,
              niveles: d.niveles.map((k, v) => MapEntry(k, word.NivelEvaluacion(
                valor: v.valor,
                interpretacion: v.interpretacion,
                benchmarkPorCargo: v.benchmarkPorCargo,
                obs: v.obs,
                sistemasSeleccionados: v.sistemasSeleccionados,
                evidenciaUrl: v.evidenciaUrl,
              ))),
            )).toList();

        final path = await word.ReporteWordService.generarReporteWord(
          datosWord,
          nombreEmpresa,
        );

        file = File(path);
      }

      // 🔹 PDF
      else if (formato.toUpperCase().contains('PDF')) {
        fileName = 'Reporte_$nombreEmpresaSan.pdf';
        final pdfBytes = await pdf.ReportePdfService.generarReportePdf(datos);
        file = File('${directory.path}/$fileName');
        await file.writeAsBytes(pdfBytes);
      }

      // 🔹 EXCEL
      else {
        fileName = 'Reporte_$nombreEmpresaSan.xlsx';
        final excelBytes = ReporteExcelService.generarReporteExcel(datos);
        file = File('${directory.path}/$fileName');
        await file.writeAsBytes(excelBytes);
      }

      // 📤 Subir archivo a Supabase
      try {
        final supabase = Supabase.instance.client;

        await supabase.storage.from('reportes').remove([fileName]);
        await supabase.storage.from('reportes').upload(fileName, file);

        final publicUrl =
            supabase.storage.from('reportes').getPublicUrl(fileName);

        onStatus('✅ Reporte generado y subido: $publicUrl');

        // Abrir según el tipo
        if (formato.toUpperCase().contains('PDF') ||
            formato.toUpperCase().contains('EXCEL')) {
          await OpenFilex.open(file.path);
        } else {
          final uri = Uri.parse(publicUrl);
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } catch (e) {
        onStatus('⚠️ Reporte generado pero error al subir: $e');
      }
    } catch (e) {
      onStatus('❌ Error al generar reporte: $e');
    }
  }
}
