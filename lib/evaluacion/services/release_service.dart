import 'dart:io' show Platform, File, Process, exit;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class ReleaseInfo {
  final String appId;
  final String plataforma; // 'android' | 'windows'
  final String version;    // '1.2.3'
  final int build;         // 45
  final String url;
  final String? notas;
  final bool obligatoria;

  ReleaseInfo({
    required this.appId,
    required this.plataforma,
    required this.version,
    required this.build,
    required this.url,
    this.notas,
    required this.obligatoria,
  });

  factory ReleaseInfo.fromMap(Map<String, dynamic> m) => ReleaseInfo(
    appId: (m['app_id'] ?? '') as String,
    plataforma: (m['plataforma'] ?? '') as String,
    version: (m['version'] ?? '') as String,
    build: (m['build'] ?? 0) as int,
    url: (m['url'] ?? '') as String,
    notas: m['notas'] as String?,
    obligatoria: (m['obligatoria'] as bool?) ?? false,
  );
}

class ReleasesService {
  final SupabaseClient _db = Supabase.instance.client;

  /// Obtiene el último release por plataforma para el appId indicado.
  Future<ReleaseInfo?> fetchLatestRelease({
    required String appId,
    String canal = 'stable',
  }) async {
    final plataforma = Platform.isAndroid ? 'android' : 'windows';

    final row = await _db
        .from('releases')
        .select()
        .eq('app_id', appId)
        .eq('plataforma', plataforma)
        .eq('canal', canal)
        .order('build', ascending: false)
        .limit(1)
        .maybeSingle();

    if (row == null) return null;
    final rel = ReleaseInfo.fromMap(row);
    // Si la columna url no contiene http, asumimos que es un storage path
    // y tratamos de generar un signed URL del bucket 'releases'. Si no
    // funciona, devolvemos el valor tal cual.
    try {
      final raw = rel.url;
      if (raw.isNotEmpty && !raw.toLowerCase().startsWith('http')) {
        try {
          final signed = await _db.storage.from('releases').createSignedUrl(raw, 60 * 60);
          if (signed.isNotEmpty) {
            return ReleaseInfo(
              appId: rel.appId,
              plataforma: rel.plataforma,
              version: rel.version,
              build: rel.build,
              url: signed,
              notas: rel.notas,
              obligatoria: rel.obligatoria,
            );
          }
        } catch (_) {
          // ignore and fallback to raw url
        }
      }
    } catch (_) {}

    return rel;
  }

  /// Compara builds (preferible a comparar versiones semánticas).
  bool isNewer({required int currentBuild, required int latestBuild}) {
    return latestBuild > currentBuild;
  }

  /// Descarga el ejecutable/archivo apuntado por [info.url] (puede ser una URL pública
  /// o un storage path que ya fue convertido a signed URL por fetchLatestRelease).
  /// Guarda el archivo en temporal y lo ejecuta (Windows). Devuelve true si se lanzó.
  Future<bool> downloadAndLaunchRelease(ReleaseInfo info, {void Function(double progress)? onProgress}) async {
    try {
      final uri = Uri.parse(info.url);
      final client = http.Client();
      final req = await client.send(http.Request('GET', uri));
      if (req.statusCode != 200 && req.statusCode != 206) {
        client.close();
        return false;
      }

      final total = req.contentLength ?? 0;
      final tmpDir = await getTemporaryDirectory();
      final filename = p.basename(uri.path);
      final outPath = p.join(tmpDir.path, filename);
      final outFile = File(outPath);
      final sink = outFile.openWrite();

      int received = 0;
      await for (final chunk in req.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null && total > 0) onProgress(received / total);
      }
      await sink.close();
      client.close();

      if (Platform.isWindows) {
        // Intentamos ejecutar el instalador en Windows. Esto puede pedir elevación.
        try {
          await Process.start(outPath, []);
          // Opcional: salir de la app para permitir que el instalador reemplace archivos.
          try {
            exit(0);
          } catch (_) {}
          return true;
        } catch (e) {
          return false;
        }
      } else {
        // En otras plataformas solo abrimos el archivo con el proceso del sistema
        try {
          await Process.start(outPath, []);
          return true;
        } catch (_) {
          return false;
        }
      }
    } catch (e) {
      return false;
    }
  }
}
