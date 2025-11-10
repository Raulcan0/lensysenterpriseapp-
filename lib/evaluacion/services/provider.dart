// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final tablaProvider = StateNotifierProvider<TablaNotifier, Map<String, Map<String, List<Map<String, dynamic>>>>>((ref) {
  return TablaNotifier();
});

class TablaNotifier extends StateNotifier<Map<String, Map<String, List<Map<String, dynamic>>>>> {
  TablaNotifier()
      : super({
          'Dimensión 1': {},
          'Dimensión 2': {},
          'Dimensión 3': {},
        });

  final SupabaseClient _db = Supabase.instance.client;
  SharedPreferences? _prefs;

  static const _keyTablaDatos = 'tabla_datos';

  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> sincronizar(String empresaId) async {
    final res = await _db.from('calificaciones').select().eq('id_empresa', empresaId);
    final datos = List<Map<String, dynamic>>.from(res);
    final Map<String, Map<String, List<Map<String, dynamic>>>> nuevaTabla = {
      'Dimensión 1': <String, List<Map<String, dynamic>>>{},
      'Dimensión 2': <String, List<Map<String, dynamic>>>{},
      'Dimensión 3': <String, List<Map<String, dynamic>>>{},
    };

    for (final cal in datos) {
      final dimensionId = cal['id_dimension']?.toString() ?? '1';
      final asociadoId = cal['id_asociado'] ?? '';
      final comportamiento = cal['comportamiento']?.toString() ?? '';
      final principio = cal['principio']?.toString() ?? '';
      final cargo = cal['cargo']?.toString() ?? '';
      final observaciones = cal['observaciones']?.toString() ?? '';
      final sistemasRaw = cal['sistemas'] ?? [];
      final puntaje = (cal['puntaje'] ?? 0) as int;
      final List<String> sistemas = sistemasRaw is List ? List<String>.from(sistemasRaw) : [];

      final String dimensionNombre = switch (dimensionId) {
        '2' => 'Dimensión 2',
        '3' => 'Dimensión 3',
        _ => 'Dimensión 1',
      };

      final fila = {
        'principio': principio,
        'comportamiento': comportamiento,
        'cargo': cargo,
        'cargo_raw': cargo,
        'valor': puntaje,
        'sistemas': sistemas,
        'dimension_id': dimensionId,
        'asociado_id': asociadoId,
        'observaciones': observaciones,
        'updatedAt': DateTime.now().toIso8601String(),
      };

      nuevaTabla[dimensionNombre]!.putIfAbsent(asociadoId, () => <Map<String, dynamic>>[]).add(fila);
    }

    state = nuevaTabla;
    await _guardarEnCache();
  }

  Future<void> cargarDesdeCache() async {
    await init();
    final raw = _prefs!.getString(_keyTablaDatos);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final tabla = decoded.map((dim, submap) {
        final sub = (submap as Map<String, dynamic>).map((id, filas) {
          return MapEntry(
            id,
            List<Map<String, dynamic>>.from(filas as List),
          );
        });
        return MapEntry(dim, sub);
      });
      state = tabla;
    } catch (_) {
      state = {
        'Dimensión 1': {},
        'Dimensión 2': {},
        'Dimensión 3': {},
      };
    }
  }

  Future<void> _guardarEnCache() async {
    await init();
    final encoded = jsonEncode(state);
    await _prefs!.setString(_keyTablaDatos, encoded);
  }
} 
