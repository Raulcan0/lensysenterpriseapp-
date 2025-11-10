import 'dart:convert';
import 'dart:io';
import 'package:applensys/evaluacion/screens/shingo_result.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class ShingoReporteService {
  static Future<String> generarReporteShingoWord({
    required ShingoResultData data,
    required String nombreEmpresa,
  }) async {
    final buffer = StringBuffer();

    buffer.writeln('<html><body>');
    buffer.writeln('<h2 style="text-align:center;">Reporte de Resultados Shingo</h2>');
    buffer.writeln('<p><b>Empresa:</b> $nombreEmpresa</p>');
    buffer.writeln('<p><b>Calificación:</b> ${data.calificacion} / 5</p>');

    if (data.imagen != null && data.imagen!.existsSync()) {
      final bytes = await data.imagen!.readAsBytes();
      final base64Img = base64Encode(bytes);
      buffer.writeln('<img src="data:image/png;base64,$base64Img" width="500"/>');
    }

    buffer.writeln('<hr>');

    data.campos.forEach((clave, valor) {
      buffer.writeln('<p><b>$clave:</b><br>${valor.isEmpty ? "Sin información" : valor}</p>');
    });

    buffer.writeln('</body></html>');

    final dir = await getApplicationDocumentsDirectory();
    final uuid = const Uuid().v4();
    final filePath = '${dir.path}/Reporte_Shingo_$uuid.doc';
    final file = File(filePath);
    await file.writeAsString(buffer.toString());
    return file.path;
  }

  static Future<String> subirAStorage(File file) async {
    final supabase = Supabase.instance.client;
    final fileName = file.path.split('/').last;

    final bucket = supabase.storage.from('reportes');

    // Borrar anterior si existía
    try {
      await bucket.remove([fileName]);
    } catch (e) {
      // Ignorar error si no existía o hubo algún problema al borrar
    }

    // Subir nuevo
    await bucket.upload(fileName, file);

    return bucket.getPublicUrl(fileName);
  }
}
