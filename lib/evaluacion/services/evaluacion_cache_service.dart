import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:applensys/evaluacion/screens/tablas_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Parser local y tolerante para sistemas (List, JSON string, CSV)
List<String> _parseSistemasDynamic(dynamic raw) {
  if (raw == null) return <String>[];
  if (raw is List) {
    return raw
        .map((s) => s.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  if (raw is String) {
    final str = raw.trim();
    if (str.isEmpty) return <String>[];
    try {
      final decoded = json.decode(str);
      if (decoded is List) {
        return decoded
            .map((s) => s.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return str
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  return [raw.toString().trim()].where((s) => s.isNotEmpty).toList();
}

/// Servicio para sincronizar y escuchar las tres dimensiones en todos los dispositivos
class DimensionesSyncService {
  static final ValueNotifier<
    Map<String, Map<String, List<Map<String, dynamic>>>>
  >
  dimensionesNotifier =
      ValueNotifier<Map<String, Map<String, List<Map<String, dynamic>>>>>({
        'Dimensión 1': {},
        'Dimensión 2': {},
        'Dimensión 3': {},
      });

  /// Sincroniza las tres dimensiones desde la base remota y actualiza el notifier
  static Future<void> syncTodasDimensiones(String empresaId) async {
    final supabase = Supabase.instance.client;
    final response = await supabase
        .from('calificaciones')
        .select()
        .eq('id_empresa', empresaId);

    final List<Map<String, dynamic>> calificaciones =
        List<Map<String, dynamic>>.from(response);

    final Map<String, Map<String, List<Map<String, dynamic>>>> tabla = {
      'Dimensión 1': {},
      'Dimensión 2': {},
      'Dimensión 3': {},
    };

    for (final cal in calificaciones) {
      final dimensionId = cal['id_dimension']?.toString() ?? '1';
      final asociadoId = cal['id_asociado'] ?? '';
      final comportamiento = cal['comportamiento'] ?? '';
      final principio = cal['principio'] ?? 'Principio Desconocido';
      final cargo = cal['cargo'] ?? 'Desconocido';
      final observaciones = cal['observaciones'] ?? '';
      final sistemasRaw = cal['sistemas'] ?? [];
      final puntaje = (cal['puntaje'] ?? 0) as int;

      // Usar parser tolerante (soporta List, JSON-string, CSV)
      final List<String> sistemas =
          _parseSistemasDynamic(sistemasRaw).map((s) => s.titleCase()).toList();

      final String dimensionNombre =
          dimensionId == '2'
              ? 'Dimensión 2'
              : dimensionId == '3'
              ? 'Dimensión 3'
              : 'Dimensión 1';

      String capitalizar(String s) {
        if (s.isEmpty) return s;
        return s[0].toUpperCase() + s.substring(1).toLowerCase();
      }

      final fila = {
        'principio': principio,
        'comportamiento': comportamiento,
        'cargo': cargo.trim().isNotEmpty ? capitalizar(cargo.trim()) : cargo,
        'cargo_raw': cargo,
        'valor': puntaje,
        'sistemas': sistemas,
        'dimension_id': dimensionId,
        'asociado_id': asociadoId,
        'observaciones': observaciones,
        'updatedAt': DateTime.now().toIso8601String(),
      };

      final lista = tabla[dimensionNombre]!.putIfAbsent(asociadoId, () => []);
      final idx = lista.indexWhere(
        (f) =>
            (f['principio']?.toString().toLowerCase().trim() ==
                principio.toLowerCase().trim()) &&
            (f['comportamiento']?.toString().toLowerCase().trim() ==
                comportamiento.toLowerCase().trim()) &&
            (f['cargo_raw']?.toString().toLowerCase().trim() ==
                cargo.toLowerCase().trim()),
      );

      if (idx >= 0) {
        final existente = lista[idx];
        if ((sistemas.isEmpty) && existente['sistemas'] is List) {
          fila['sistemas'] = List<String>.from(existente['sistemas'] ?? []);
        }
        if ((observaciones.toString().trim().isEmpty) &&
            existente['observaciones'] is String) {
          fila['observaciones'] = existente['observaciones'];
        }
        lista[idx] = fila;
      } else {
        lista.add(fila);
      }
    }

    dimensionesNotifier.value = tabla;
  }

  /// Escucha los cambios en las dimensiones (útil para widgets)
  static void addListener(VoidCallback listener) {
    dimensionesNotifier.addListener(listener);
  }

  static void removeListener(VoidCallback listener) {
    dimensionesNotifier.removeListener(listener);
  }

  /// Obtiene los datos actuales de todas las dimensiones
  static Map<String, Map<String, List<Map<String, dynamic>>>> obtenerDatos() {
    return dimensionesNotifier.value;
  }

  /// Actualiza una dimensión específica y sincroniza el notifier (realmente actualiza todas)
  static Future<void> actualizarDimension(String empresaId) async {
    await syncTodasDimensiones(empresaId);
  }
}

class EvaluacionCacheService {
  static const _keyEvaluacionPendiente = 'evaluacion_pendiente';
  static const _keyTablaDatos = 'tabla_datos';
  static const _keyEvaluacionAsociados = 'evaluacion_asociados';
  static const _keyEvaluacionPrincipios = 'evaluacion_principios';
  static const _keyEvaluacionComportamientos = 'evaluacion_comportamientos';
  static const _keyEvaluacionDetalles = 'evaluacion_detalles';
  static const _keyObservaciones = 'evaluacion_observaciones';

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> guardarPendiente(String evaluacionId) async {
    await init();
    await _prefs!.setString(_keyEvaluacionPendiente, evaluacionId);
  }

  Future<String?> obtenerPendiente() async {
    await init();
    return _prefs!.getString(_keyEvaluacionPendiente);
  }

  Future<void> eliminarPendiente() async {
    await init();
    await _prefs!.remove(_keyEvaluacionPendiente);
    // Si quieres eliminar también la tabla, descomenta la siguiente línea:
    // await _prefs!.remove(_keyTablaDatos);
  }

  Future<void> guardarTablas(
    Map<String, Map<String, List<Map<String, dynamic>>>> data,
  ) async {
    await init();
    // Persist cache: normalize text fields to Title Case to backfill older uppercase data
    final normalized = data.map(
      (dim, map) => MapEntry(
        dim,
        map.map(
          (id, filas) => MapEntry(
            id,
            filas.map((fila) {
              final f = Map<String, dynamic>.from(fila);
              if (f.containsKey('principio')) {
                f['principio'] = f['principio'].toString().titleCase();
              }
              if (f.containsKey('comportamiento')) {
                f['comportamiento'] =
                    f['comportamiento'].toString().titleCase();
              }
              if (f.containsKey('cargo')) {
                f['cargo'] = f['cargo'].toString().titleCase();
              }
              // preserve cargo_raw as original; do not mutate
              if (f.containsKey('sistemas') && f['sistemas'] is List) {
                f['sistemas'] =
                    (f['sistemas'] as List)
                        .map((s) => s.toString().titleCase())
                        .toList();
              }
              return f;
            }).toList(),
          ),
        ),
      ),
    );

    final encoded = jsonEncode(normalized);
    await _prefs!.setString(_keyTablaDatos, encoded);
  }

  Future<Map<String, Map<String, List<Map<String, dynamic>>>>>
  cargarTablas() async {
    await init();
    final raw = _prefs!.getString(_keyTablaDatos);
    if (raw == null || raw.isEmpty) {
      return {'Dimensión 1': {}, 'Dimensión 2': {}, 'Dimensión 3': {}};
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      // Normalize decoded cache fields to Title Case (backfill older uppercase values)
      return decoded.map((dim, map) {
        final sub = (map as Map<String, dynamic>).map(
          (id, filas) => MapEntry(
            id,
            List<Map<String, dynamic>>.from(
              (filas as List).map((e) {
                final f = Map<String, dynamic>.from(e);
                if (f.containsKey('principio')) {
                  f['principio'] = f['principio'].toString().titleCase();
                }
                if (f.containsKey('comportamiento')) {
                  f['comportamiento'] =
                      f['comportamiento'].toString().titleCase();
                }
                if (f.containsKey('cargo')) {
                  f['cargo'] = f['cargo'].toString().titleCase();
                }
                if (f.containsKey('sistemas') && f['sistemas'] is List) {
                  f['sistemas'] =
                      (f['sistemas'] as List)
                          .map((s) => s.toString().titleCase())
                          .toList();
                }
                return f;
              }),
            ),
          ),
        );
        return MapEntry(dim, sub);
      });
    } catch (e) {
      return {'Dimensión 1': {}, 'Dimensión 2': {}, 'Dimensión 3': {}};
    }
  }

  Future<void> syncEvaluacionPorEmpresa(String empresaId) async {
    await init();
    final supabase = Supabase.instance.client;

    final response = await supabase
        .from('calificaciones')
        .select()
        .eq('id_empresa', empresaId);

    final List<Map<String, dynamic>> calificaciones =
        List<Map<String, dynamic>>.from(response);

    final Map<String, Map<String, List<Map<String, dynamic>>>> tabla = {
      'Dimensión 1': {},
      'Dimensión 2': {},
      'Dimensión 3': {},
    };

    for (final cal in calificaciones) {
      final dimensionId = cal['id_dimension']?.toString() ?? '1';
      final asociadoId = cal['id_asociado'] ?? '';
      final comportamiento = cal['comportamiento'] ?? '';
      final principio = cal['principio']?.toString().trim() ?? '';
      final cargo = cal['cargo'] ?? 'Desconocido';
      final observaciones = cal['observaciones'] ?? '';
      final sistemasRaw = cal['sistemas'] ?? [];
      final puntaje = (cal['puntaje'] ?? 0) as int;

      // Usar parser tolerante (soporta List, JSON-string, CSV)
      final List<String> sistemas =
          _parseSistemasDynamic(sistemasRaw).map((s) => s.titleCase()).toList();

      final String dimensionNombre = switch (dimensionId) {
        '2' => 'Dimensión 2',
        '3' => 'Dimensión 3',
        _ => 'Dimensión 1',
      };

      String capitalizar(String s) {
        if (s.isEmpty) return s;
        return s[0].toUpperCase() + s.substring(1).toLowerCase();
      }

      final fila = {
        'principio': principio,
        'comportamiento': comportamiento,
        'cargo': cargo.trim().isNotEmpty ? capitalizar(cargo.trim()) : cargo,
        'cargo_raw': cargo,
        'valor': puntaje,
        'sistemas': sistemas,
        'dimension_id': dimensionId,
        'asociado_id': asociadoId,
        'observaciones': observaciones,
        'updatedAt': DateTime.now().toIso8601String(),
      };

      tabla[dimensionNombre]!.putIfAbsent(asociadoId, () => []).add(fila);
    }

    await guardarTablas(tabla);

    // actualiza el global de pantalla
    TablasDimensionScreen.tablaDatos = tabla;
    TablasDimensionScreen.dataChanged.value =
        !TablasDimensionScreen.dataChanged.value;
  }

  Future<void> limpiarCacheTablaDatos() async {
    await init();
    await _prefs!.remove(_keyTablaDatos);
  }

  Future<void> limpiarEvaluacionCompleta() async {
    await init();
    await _prefs!.remove(_keyEvaluacionPendiente);
    await _prefs!.remove(_keyTablaDatos);
    await _prefs!.remove(_keyEvaluacionAsociados);
    await _prefs!.remove(_keyEvaluacionPrincipios);
    await _prefs!.remove(_keyEvaluacionComportamientos);
    await _prefs!.remove(_keyEvaluacionDetalles);
  }

  Future<List<Map<String, dynamic>>> cargarPromediosSistemas() async {
    final tabla = await cargarTablas();
    final Map<String, List<double>> acumulador = {};
    tabla.forEach((_, submap) {
      submap.values.expand((rows) => rows).forEach((item) {
        final List<dynamic> sistemasDelItemRaw =
            item['sistemas'] as List<dynamic>? ?? [];
        final List<String> sistemasDelItem =
            sistemasDelItemRaw.map((s) => s.toString().toUpperCase()).toList();
        final rawValor = item['valor'];
        final valorNumerico =
            rawValor is num
                ? rawValor.toDouble()
                : double.tryParse(rawValor.toString()) ?? 0.0;
        for (final nombreSistema in sistemasDelItem) {
          if (nombreSistema.isNotEmpty) {
            acumulador.putIfAbsent(nombreSistema, () => []).add(valorNumerico);
          }
        }
      });
    });
    final List<Map<String, dynamic>> promedios = [];
    acumulador.forEach((sistema, valores) {
      if (valores.isNotEmpty) {
        final promedio = valores.reduce((a, b) => a + b) / valores.length;
        promedios.add({
          'sistema': sistema,
          'promedio': promedio,
          'cantidad': valores.length,
        });
      }
    });
    promedios.sort(
      (a, b) => (b['promedio'] as double).compareTo(a['promedio'] as double),
    );
    return promedios;
  }

  Future<void> guardarObservaciones(Map<String, String> observaciones) async {
    await init();
    final encoded = jsonEncode(observaciones);
    await _prefs!.setString(_keyObservaciones, encoded);
  }

  Future<Map<String, String>> cargarObservaciones() async {
    await init();
    final raw = _prefs!.getString(_keyObservaciones);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, value as String));
    } catch (e) {
      return {};
    }
  }

  Future<void> limpiarObservaciones() async {
    await init();
    await _prefs!.remove(_keyObservaciones);
  }

  Future<void> guardarObservacionesshingo(
    Map<String, String> observaciones,
  ) async {
    await init();
    final encoded = jsonEncode(observaciones);
    await _prefs!.setString(_keyObservaciones, encoded);
  }

  Future<Map<String, String>> cargarObservacionesshingo() async {
    await init();
    final raw = _prefs!.getString(_keyObservaciones);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((key, value) => MapEntry(key, value as String));
    } catch (e) {
      return {};
    }
  }

  Future<void> limpiarObservacionesshingo() async {
    await init();
    await _prefs!.remove(_keyObservaciones);
  }
}
