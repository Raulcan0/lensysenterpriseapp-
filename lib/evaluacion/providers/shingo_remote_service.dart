import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../evaluacion/screens/shingo_result.dart';
import '../services/evaluacion_cache_service.dart';

class ShingoRemoteService extends ChangeNotifier {
  final String empresaId;
  final SupabaseClient _supabase = Supabase.instance.client;

  Map<String, ShingoResultData> _tabla = {};
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;

  ShingoRemoteService({required this.empresaId});

  Map<String, ShingoResultData> get tabla => _tabla;

  Future<void> iniciar() async {
    await _cargarDesdeSupabase();
    _suscribirseASupabase();
  }

  Future<void> _cargarDesdeSupabase() async {
    final response = await _supabase
        .from('shingo_resultados')
        .select()
        .eq('id_empresa', empresaId);

    final mapa = _parseResultados(response);
    _tabla = mapa;
    await EvaluacionCacheService().guardarObservaciones(
      mapa.map((k, v) => MapEntry(k, v.toJson() as String)),
    );
    notifyListeners();
  }

  void _suscribirseASupabase() {
    _subscription = _supabase
        .from('shingo_resultados')
        .stream(primaryKey: ['id_empresa', 'categoria', 'subcategoria'])
        .eq('id_empresa', empresaId)
        .listen((data) {
      final mapa = _parseResultados(data);
      _tabla = mapa;
      EvaluacionCacheService().guardarObservaciones(
        mapa.map((k, v) => MapEntry(k, v.toJson() as String)),
      );
      notifyListeners();
    });
  }

  Future<void> actualizarCalificacion(String categoria, String? subcategoria, int calificacion) async {
    await _supabase.from('shingo_resultados').upsert({
      'id_empresa': empresaId,
      'categoria': categoria,
      'subcategoria': subcategoria,
      'calificacion': calificacion,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Map<String, ShingoResultData> _parseResultados(List<dynamic> data) {
    final mapa = <String, ShingoResultData>{};
    for (final row in data) {
      final categoria = row['categoria'] ?? '';
      final subcategoria = row['subcategoria'];
      final calificacion = row['calificacion'] ?? 0;

      mapa.putIfAbsent(categoria, () => ShingoResultData(calificacion: 0, subcategorias: {}));
      if (subcategoria == null) {
        mapa[categoria]!.calificacion = calificacion;
      } else {
        mapa[categoria]!.subcategorias[subcategoria] =
            ShingoResultData(calificacion: calificacion, subcategorias: {});
      }
    }
    return mapa;
  }

  Future<void> cargarDesdeCache() async {
    final cache = await EvaluacionCacheService().cargarObservaciones();
    _tabla = cache.map((k, v) => MapEntry(k, ShingoResultData.fromJson(v as Map<String, dynamic>)));
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
