// ignore_for_file: use_build_context_synchronously, curly_braces_in_flow_control_structures

import 'dart:convert';
import 'package:applensys/evaluacion/services/pdf.dart';
import 'package:applensys/evaluacion/services/reporte_service.dart' as reporte_service;
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:applensys/evaluacion/charts/multiring.dart';
import 'package:flutter/material.dart';
import 'package:applensys/evaluacion/widgets/chat_screen.dart';
import 'package:applensys/evaluacion/widgets/drawer_lensys.dart';
import 'package:applensys/evaluacion/models/empresa.dart';
import 'package:applensys/evaluacion/utils/evaluacion_chart_data.dart';
import 'package:applensys/evaluacion/models/dimension.dart';
import 'package:applensys/evaluacion/models/principio.dart';
import 'package:applensys/evaluacion/models/comportamiento.dart';
import 'package:applensys/evaluacion/services/evaluacion_cache_service.dart';
import 'package:applensys/evaluacion/screens/tablas_screen.dart';
import 'package:applensys/evaluacion/charts/scatter_bubble_chart.dart';
import 'package:applensys/evaluacion/charts/grouped_bar_chart.dart';
import 'package:applensys/evaluacion/charts/horizontal_bar_systems_chart.dart';
import 'package:applensys/custom/table_names.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DashboardScreen extends StatefulWidget {
  final String evaluacionId;
  final Empresa empresa;

  const DashboardScreen({
    super.key,
    required this.evaluacionId,
    required this.empresa,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Datos crudos extraídos del cache o Supabase:
  List<Map<String, dynamic>> _dimensionesRaw = [];

  // Modelos procesados para gráficos:
  List<Dimension> _dimensiones = [];

  // Flag para saber si aún estamos cargando
  bool _isLoading = true;
  // Debounce timer para evitar recargas muy frecuentes al recibir notificaciones
  Timer? _reloadTimer;

  // Getters públicos para acceder a los datos desde otras screens
  List<Dimension> get dimensiones => _dimensiones;
  Map<String, Map<String, double>> get promediosPorDimensionCargo => _calcularPromediosPorDimensionCargo();

  // Lista ordenada de sistemas para el gráfico de barras horizontales
  // DEBES ACTUALIZAR ESTA LISTA CON TUS SISTEMAS REALES Y EN EL ORDEN DESEADO
 

  @override
  void initState() {
    super.initState();
    _loadCachedOrRemoteData();
    // Escuchar cambios globales de tablas (cuando se actualizan calificaciones/sistemas)
    try {
      TablasDimensionScreen.dataChanged.addListener(_onTablasDataChanged);
    } catch (_) {}
  }

  void _onTablasDataChanged() {
    // Debounce: esperar 300ms para agrupar múltiples cambios seguidos
    _reloadTimer?.cancel();
    _reloadTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      debugPrint('🔔 Tablas cambiadas - recargando datos para dashboard');
      await _loadCachedOrRemoteData();
      if (!mounted) return;
      setState(() {});
    });
  }

  Future<void> _loadCachedOrRemoteData() async {
    final cacheService = EvaluacionCacheService();
    await cacheService.init();

    dynamic rawTables = await cacheService.cargarTablas();

    if (rawTables != null) {
      // Si viene un Map<String, Map<String, List<Map<String, dynamic>>>>
      final List<Map<String, dynamic>> flattened = [];
      if (rawTables is Map<String, dynamic>) {
        for (final dimEntry in rawTables.entries) {
          final innerMap = dimEntry.value;
          if (innerMap is Map<String, dynamic>) {
            for (final listEntry in innerMap.entries) {
              final rowsList = listEntry.value;
              if (rowsList is List<dynamic>) {
                for (final row in rowsList) {
                  if (row is Map<String, dynamic>) {
                    flattened.add(row);
                  }
                }
              }
            }
          }
        }
        _dimensionesRaw = flattened;
      }
      // Si rawTables ya era List<Map<String, dynamic>>
      else if (rawTables is List<dynamic>) {
        _dimensionesRaw = rawTables.cast<Map<String, dynamic>>();
      }
    }

    // Si no hay datos en caché, consultamos Supabase
    if (_dimensionesRaw.isEmpty) {
      try {
        final supabase = Supabase.instance.client;
        final data = await supabase
            .from(TableNames.detallesEvaluacion)
            .select()
            .eq('evaluacion_id', widget.evaluacionId);
        _dimensionesRaw =
            List<Map<String, dynamic>>.from(data as List<dynamic>);
      } catch (e) {
        debugPrint('Error cargando datos de Supabase: $e');
        _dimensionesRaw = [];
      }
    }

    if (_dimensionesRaw.isNotEmpty) {
      _procesarDimensionesDesdeRaw(_dimensionesRaw);
    }

    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  
  void _procesarDimensionesDesdeRaw(List<Map<String, dynamic>> raw) {
    final Map<String, List<Map<String, dynamic>>> porDimension = {};
    for (final fila in raw) {
      final dimNombre = (fila['dimension_id']?.toString()) ?? 'Sin dimensión';
      porDimension.putIfAbsent(dimNombre, () => []).add(fila);
    }

    final List<Dimension> dimsModel = [];

    porDimension.forEach((dimNombre, filasDim) {
      double sumaGeneralDim = 0;
      int conteoGeneralDim = 0;

      // Agrupar por 'principio'
      final Map<String, List<Map<String, dynamic>>> porPrincipio = {};
      for (final fila in filasDim) {
        final priNombre = (fila['principio'] as String?) ?? 'Sin principio';
        porPrincipio.putIfAbsent(priNombre, () => []).add(fila);
      }

      final List<Principio> principiosModel = [];

      porPrincipio.forEach((priNombre, filasPri) {
        // Para calcular el promedio del principio, necesitamos sumar TODOS los valores 
        // del principio y dividir por el total de calificaciones
        double sumaTotalPrincipio = 0;
        int conteoTotalPrincipio = 0;

        // Agrupar por 'comportamiento'
        final Map<String, List<Map<String, dynamic>>> porComportamiento = {};
        for (final filaP in filasPri) {
          final compNombre =
              (filaP['comportamiento'] as String?) ?? 'Sin comportamiento';
          porComportamiento.putIfAbsent(compNombre, () => []).add(filaP);
        }

        final List<Comportamiento> compsModel = [];

        porComportamiento.forEach((compNombre, filasComp) {
          double sumaEj = 0, sumaGe = 0, sumaMi = 0;
          int countEj = 0, countGe = 0, countMi = 0;

          for (final row in filasComp) {
            final valor = (row['valor'] as num?)?.toDouble() ?? 0.0;
            final cargoRaw =
                (row['cargo_raw'] as String?)?.toLowerCase().trim() ?? '';
            
            // Sumar al total del principio TODOS los valores válidos
            if (valor > 0) {
              sumaTotalPrincipio += valor;
              conteoTotalPrincipio++;
            }
            
            if (cargoRaw.contains('ejecutivo')) {
              sumaEj += valor;
              countEj++;
            } else if (cargoRaw.contains('gerente')) {
              sumaGe += valor;
              countGe++;
            } else if (cargoRaw.contains('miembro')) {
              sumaMi += valor;
              countMi++;
            }
          }

          final double promEj = (countEj > 0) ? (sumaEj / countEj) : 0.0;
          final double promGe = (countGe > 0) ? (sumaGe / countGe) : 0.0;
          final double promMi = (countMi > 0) ? (sumaMi / countMi) : 0.0;

          // Extraer todos los sistemas únicos de las filas de este comportamiento
          final Set<String> sistemasSet = {};
          String observacionesEj = '';
          String observacionesGe = '';
          String observacionesMi = '';
          
          for (final row in filasComp) {
            final cargoRaw = (row['cargo_raw'] as String?)?.toLowerCase().trim() ?? '';
            
            // Extraer sistemas
            final listaSistemas = (row['sistemas'] as List<dynamic>?)
              ?.map((s) => s.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList() ?? <String>[];
            
            sistemasSet.addAll(listaSistemas);
            
            // Extraer observaciones por cargo
            final obs = (row['observaciones'] as String?) ?? '';
            if (obs.isNotEmpty) {
              if (cargoRaw.contains('ejecutivo')) {
                observacionesEj = obs;
              } else if (cargoRaw.contains('gerente')) {
                observacionesGe = obs;
              } else if (cargoRaw.contains('miembro')) {
                observacionesMi = obs;
              }
            }
          }
          
          final List<String> sistemas = sistemasSet.toList();
          sistemas.sort(); // Ordenamos los sistemas alfabéticamente

          compsModel.add(
            Comportamiento(
              nombre: compNombre,
              promedioEjecutivo: promEj,
              promedioGerente: promGe,
              promedioMiembro: promMi,
              sistemas: sistemas,
              observaciones: observacionesEj.isNotEmpty ? observacionesEj : 
                             observacionesGe.isNotEmpty ? observacionesGe : 
                             observacionesMi.isNotEmpty ? observacionesMi : null,
              nivel: null,
              principioId: priNombre,
              id: '',
              cargo: null,
            ),
          );
        });

        // Promedio general del principio (todas las calificaciones)
        final double promedioPri = (conteoTotalPrincipio > 0) ? (sumaTotalPrincipio / conteoTotalPrincipio) : 0.0;

        // Debug: Imprimir información del cálculo del principio
        debugPrint('Principio: $priNombre');
        debugPrint('  Total valores: $conteoTotalPrincipio, Suma total: $sumaTotalPrincipio');
        debugPrint('  Promedio calculado: $promedioPri');

        principiosModel.add(
          Principio(
            id: priNombre,
            dimensionId: dimNombre,
            nombre: priNombre,
            promedioGeneral: promedioPri,
            comportamientos: compsModel,
          ),
        );

        if (promedioPri > 0) {
          sumaGeneralDim += promedioPri;
          conteoGeneralDim++;
        }
      });

      final double promedioDim =
          (conteoGeneralDim > 0) ? (sumaGeneralDim / conteoGeneralDim) : 0.0;

      dimsModel.add(
        Dimension(
          id: dimNombre,
          nombre: dimNombre,
          promedioGeneral: promedioDim,
          principios: principiosModel,
        ),
      );
    });

    _dimensiones = dimsModel;
    debugPrint('Dimensiones procesadas: ${_dimensiones.length}');
    if (_dimensiones.isNotEmpty) {
      debugPrint('Primera dimensión: ${_dimensiones.first.nombre}, promedio: ${_dimensiones.first.promedioGeneral}');
    }
  }

  /// Calcula promedios por dimensión y cargo para la tabla de puntuación global
  Map<String, Map<String, double>> _calcularPromediosPorDimensionCargo() {
    final Map<String, Map<String, double>> resultado = {};
    
    for (final dim in _dimensiones) {
      // Mapear nombres de dimensión a IDs numericos
      String dimId;
      if (dim.nombre.toUpperCase().contains('IMPULSORES CULTURALES')) {
        dimId = '1';
      } else if (dim.nombre.toUpperCase().contains('MEJORA CONTINUA')) {
        dimId = '2';
      } else if (dim.nombre.toUpperCase().contains('ALINEAMIENTO EMPRESARIAL')) {
        dimId = '3';
      } else {
        continue; // Saltar dimensiones que no reconocemos
      }
      
      // Inicializar estructura para esta dimensión
      resultado[dimId] = {
        'EJECUTIVOS': 0.0,
        'GERENTES': 0.0,
        'MIEMBROS DE EQUIPO': 0.0,
      };
      
      // Calcular sumas y conteos por cargo para esta dimensión
      double sumaEj = 0, sumaGe = 0, sumaMi = 0;
      int countEj = 0, countGe = 0, countMi = 0;
      
      for (final pri in dim.principios) {
        for (final comp in pri.comportamientos) {
          if (comp.promedioEjecutivo > 0) {
            sumaEj += comp.promedioEjecutivo;
            countEj++;
          }
          if (comp.promedioGerente > 0) {
            sumaGe += comp.promedioGerente;
            countGe++;
          }
          if (comp.promedioMiembro > 0) {
            sumaMi += comp.promedioMiembro;
            countMi++;
          }
        }
      }
      
      // Calcular promedios
      resultado[dimId]!['EJECUTIVOS'] = (countEj > 0) ? (sumaEj / countEj) : 0.0;
      resultado[dimId]!['GERENTES'] = (countGe > 0) ? (sumaGe / countGe) : 0.0;
      resultado[dimId]!['MIEMBROS DE EQUIPO'] = (countMi > 0) ? (sumaMi / countMi) : 0.0;
    }
    
    return resultado;
  }

  /// Calcula promedios por cargo para cada principio
  Map<String, Map<String, double>> _calcularPromediosPorCargoPrincipio() {
    final Map<String, Map<String, double>> promediosPorPrincipio = {};
    
    // Inicializar estructura para cada principio
    for (final dim in _dimensiones) {
      for (final pri in dim.principios) {
        promediosPorPrincipio[pri.nombre] = {
          'ejecutivo': 0.0,
          'gerente': 0.0,
          'miembro': 0.0,
        };
      }
    }
    
    // Calcular sumas y conteos por principio y cargo
    final Map<String, Map<String, double>> sumas = {};
    final Map<String, Map<String, int>> conteos = {};
    
    for (final principio in promediosPorPrincipio.keys) {
      sumas[principio] = {'ejecutivo': 0.0, 'gerente': 0.0, 'miembro': 0.0};
      conteos[principio] = {'ejecutivo': 0, 'gerente': 0, 'miembro': 0};
    }
    
    // Procesar datos raw
    for (final row in _dimensionesRaw) {
      final principio = row['principio'] as String?;
      if (principio == null || !sumas.containsKey(principio)) continue;
      
      final valor = (row['valor'] as num?)?.toDouble() ?? 0.0;
      final cargoRaw = (row['cargo_raw'] as String?)?.toLowerCase().trim() ?? '';
      
      if (valor > 0) {
        if (cargoRaw.contains('ejecutivo')) {
          sumas[principio]!['ejecutivo'] = sumas[principio]!['ejecutivo']! + valor;
          conteos[principio]!['ejecutivo'] = conteos[principio]!['ejecutivo']! + 1;
        } else if (cargoRaw.contains('gerente')) {
          sumas[principio]!['gerente'] = sumas[principio]!['gerente']! + valor;
          conteos[principio]!['gerente'] = conteos[principio]!['gerente']! + 1;
        } else if (cargoRaw.contains('miembro')) {
          sumas[principio]!['miembro'] = sumas[principio]!['miembro']! + valor;
          conteos[principio]!['miembro'] = conteos[principio]!['miembro']! + 1;
        }
      }
    }
    
    // Calcular promedios finales
    for (final principio in promediosPorPrincipio.keys) {
      for (final cargo in ['ejecutivo', 'gerente', 'miembro']) {
        final suma = sumas[principio]![cargo]!;
        final conteo = conteos[principio]![cargo]!;
        promediosPorPrincipio[principio]![cargo] = (conteo > 0) ? (suma / conteo) : 0.0;
      }
      
      // Solo debug para "Respetar a Cada Individuo" para verificar
      if (principio == 'Respetar a Cada Individuo') {
        debugPrint('🔍 VERIFICACIÓN - Principio: $principio');
        debugPrint('  Ejecutivo: ${promediosPorPrincipio[principio]!['ejecutivo']!.toStringAsFixed(2)} (suma: ${sumas[principio]!['ejecutivo']}, count: ${conteos[principio]!['ejecutivo']})');
        debugPrint('  Gerente: ${promediosPorPrincipio[principio]!['gerente']!.toStringAsFixed(2)} (suma: ${sumas[principio]!['gerente']}, count: ${conteos[principio]!['gerente']})');
        debugPrint('  Miembro: ${promediosPorPrincipio[principio]!['miembro']!.toStringAsFixed(2)} (suma: ${sumas[principio]!['miembro']}, count: ${conteos[principio]!['miembro']})');
      }
    }
    
    return promediosPorPrincipio;
  }

  /// Datos para el gráfico MultiRing (promedio general por dimensión).
  Map<String, double> _buildMultiringData() {
    const nombresDimensiones = {
      '1': 'IMPULSORES CULTURALES',
      '2': 'MEJORA CONTINUA',
      '3': 'ALINEAMIENTO EMPRESARIAL',
    };
    final Map<String, double> data = {};
    for (final dim in _dimensiones) {
      final nombre = nombresDimensiones[dim.id] ?? dim.nombre;
      // El promedio de la dimensión debe ser el promedio de TODOS los valores de todos los principios de esa dimensión
      // Ya está calculado correctamente en promedioGeneral de Dimension
      data[nombre] = dim.promedioGeneral;
    }
    return data;
  }
  
  /// Construye ScatterData usando promedios calculados POR CARGO para cada principio
  List<ScatterData> _buildScatterData() {
    const double dotRadius = 8.0;

    final promediosPorCargo = _calcularPromediosPorCargoPrincipio();
    final List<ScatterData> list = [];

    // Normalizador que quita acentos, puntuación y normaliza espacios/minúsculas
    String normalizeForCompare(String s) {
      var t = s.toString().trim().toLowerCase();
      if (t.isEmpty) return '';
      const accents = {
        'á': 'a',
        'é': 'e',
        'í': 'i',
        'ó': 'o',
        'ú': 'u',
        'ü': 'u',
        'ñ': 'n'
      };
      accents.forEach((k, v) => t = t.replaceAll(k, v));
      t = t.replaceAll(RegExp(r"[^a-z0-9\s]"), '');
      t = t.replaceAll(RegExp(r"\s+"), ' ').trim();
      return t;
    }

    // Crear índice canónico a partir de los nombres de ScatterBubbleChart
    final Map<String, int> canonIndex = {};
    for (int i = 0; i < ScatterBubbleChart.principleNames.length; i++) {
      final key = normalizeForCompare(ScatterBubbleChart.principleNames[i]);
      if (key.isNotEmpty) canonIndex[key] = i;
    }

    for (final principio in promediosPorCargo.keys) {
      final norm = normalizeForCompare(principio);
      int? yRawIndex;

      if (norm.isNotEmpty && canonIndex.containsKey(norm)) {
        yRawIndex = canonIndex[norm];
      } else if (norm.isNotEmpty) {
        // Fallback: buscar coincidencia tolerante
        final match = canonIndex.keys.firstWhere(
          (k) => k.contains(norm) || norm.contains(k),
          orElse: () => '',
        );
        if (match.isNotEmpty) yRawIndex = canonIndex[match];
      }

      if (yRawIndex == null) {
        debugPrint('⚠️ Principio "$principio" NO ENCONTRADO en ScatterBubbleChart.principleNames.');
        continue;
      }

      final double yIndex = (yRawIndex + 1).toDouble();
      final promEj = promediosPorCargo[principio]!['ejecutivo']!;
      final promGe = promediosPorCargo[principio]!['gerente']!;
      final promMi = promediosPorCargo[principio]!['miembro']!;

      if (promEj > 0) {
        list.add(ScatterData(x: promEj.clamp(0.0, 5.0), y: yIndex, color: Colors.orange, radius: dotRadius, cargo: 'Ejecutivo'));
      }
      if (promGe > 0) {
        list.add(ScatterData(x: promGe.clamp(0.0, 5.0), y: yIndex, color: Colors.green, radius: dotRadius, cargo: 'Gerente'));
      }
      if (promMi > 0) {
        list.add(ScatterData(x: promMi.clamp(0.0, 5.0), y: yIndex, color: Colors.blue, radius: dotRadius, cargo: 'Miembro'));
      }
    }

    debugPrint('🎯 ScatterChart: Total ${list.length} puntos generados');
    return list;
  }

  Map<String, List<double>> _buildGroupedBarData() {
    final Map<String, List<double>> data = {};
    final comps = EvaluacionChartData.extractComportamientos(_dimensiones).cast<Comportamiento>();

    // Normalizador (quita acentos, puntuación, normaliza espacios y minúsculas)
    String normalize(String s) {
      var t = s.toString().trim().toLowerCase();
      if (t.isEmpty) return '';
      const accents = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};
      accents.forEach((k, v) { t = t.replaceAll(k, v); });
      t = t.replaceAll(RegExp(r"[^a-z0-9\s]"), '');
      t = t.replaceAll(RegExp(r"\s+"), ' ').trim();
      return t;
    }

    // Build map normalizedName -> Comportamiento
    final Map<String, Comportamiento> compsByNorm = {};
    for (final c in comps) {
      final key = normalize(c.nombre);
      if (key.isNotEmpty) compsByNorm[key] = c;
    }

    for (final label in GroupedBarChart.labels) {
      final normLabel = normalize(label);
      Comportamiento? matched;
      if (normLabel.isNotEmpty && compsByNorm.containsKey(normLabel)) {
        matched = compsByNorm[normLabel];
      } else if (normLabel.isNotEmpty) {
        // fallback contains-based matching
        final matchKey = compsByNorm.keys.firstWhere(
          (k) => k.contains(normLabel) || normLabel.contains(k),
          orElse: () => '',
        );
        if (matchKey.isNotEmpty) matched = compsByNorm[matchKey];
      }

      if (matched != null) {
        data[label] = [
          matched.promedioEjecutivo.clamp(0.0, 5.0),
          matched.promedioGerente.clamp(0.0, 5.0),
          matched.promedioMiembro.clamp(0.0, 5.0),
        ];
      } else {
        // No match: leave zeros so chart renders empty for this label
        data[label] = [0.0, 0.0, 0.0];
        debugPrint('⚠️ GroupedBar: no se encontró comportamiento para etiqueta "$label"');
      }
    }

    return data;
  }

  Map<String, Map<String, double>> _buildHorizontalBarsData() {
    // Lista de sistemas ordenados (misma que en HorizontalBarSystemsChart)
    const List<String> sistemasOrdenados = [
    
    'Ambiental',
    'Compromiso',
    'Comunicación',
    'Despliegue de Estrategia',
    'Desarrollo de Personal',
    'EHS',
    'Gestión Visual',
    'Ideas de Mejora',
    'Involucramiento',
    'Medición',
    'Planificación y Programación',
    'Recompensas',
    'Reconocimiento',
    'Seguridad',
    'Sistemas de Mejora',
    'Solución de Problemas',
    'Voz del Cliente',
    'Visitas al Gemba',
    ];
    
    // Mapas para acumular sumas y conteos
    final Map<String, Map<String, double>> sumasPorSistemaNivel = {};
    final Map<String, Map<String, int>> conteosPorSistemaNivel = {};

    // Normalizador para sistemas: quita acentos, puntuación y normaliza espacios
    String normalizeSys(String s) {
      var t = s.toString().trim().toLowerCase();
      if (t.isEmpty) return t;
      const accents = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};
      accents.forEach((k, v) { t = t.replaceAll(k, v); });
      t = t.replaceAll(RegExp(r"[^a-z0-9\s]"), '');
      t = t.replaceAll(RegExp(r"\s+"), ' ').trim();
      return t;
    }

    // Parser tolerante para el campo 'sistemas' (List, JSON string, CSV)
    List<String> parseSistemasDynamic(dynamic raw) {
      if (raw == null) return <String>[];
      if (raw is List) return raw.map((s) => s.toString().trim()).where((s) => s.isNotEmpty).toList();
      if (raw is String) {
        final str = raw.trim();
        if (str.isEmpty) return <String>[];
        try {
          final decoded = json.decode(str);
          if (decoded is List) return decoded.map((s) => s.toString().trim()).where((s) => s.isNotEmpty).toList();
        } catch (_) {}
        return str.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      }
      return [raw.toString().trim()].where((s) => s.isNotEmpty).toList();
    }

    // Inicializar mapas para todos los sistemas ordenados y niveles
    for (final sistemaNombre in sistemasOrdenados) {
      sumasPorSistemaNivel[sistemaNombre] = {'E': 0.0, 'G': 0.0, 'M': 0.0};
      conteosPorSistemaNivel[sistemaNombre] = {'E': 0, 'G': 0, 'M': 0};
    }

    // Mapa canonical: normalized -> canonical display name
    final Map<String, String> canonicalMap = {};
    for (final sys in sistemasOrdenados) {
      canonicalMap[normalizeSys(sys)] = sys;
    }

    for (final row in _dimensionesRaw) {
      String? nivelKey;
      if (row.containsKey('cargo_raw') && row['cargo_raw'] != null) {
        final cargoRaw = row['cargo_raw'].toString().toLowerCase().trim();
        if (cargoRaw.contains('ejecutivo')) {
          nivelKey = 'E';
        } else if (cargoRaw.contains('gerente')) {
          nivelKey = 'G';
        } else if (cargoRaw.contains('miembro')) {
          nivelKey = 'M';
        }
      } else if (row.containsKey('nivel') && row['nivel'] != null) {
        final nivel = row['nivel'].toString().toUpperCase();
        if (['E', 'G', 'M'].contains(nivel)) {
          nivelKey = nivel;
        }
      }

      if (nivelKey == null) {
        // Si no se puede determinar el nivel, saltar esta fila
        continue;
      }

      // Obtener el valor de la calificación para este row
      final double valorCalificacion = (row['valor'] as num?)?.toDouble() ?? 0.0;

      final listaSistemasEnFila = parseSistemasDynamic(row['sistemas']);

      // Evitar doble conteo por fila
      final seenThisRow = <String>{};

      for (final rawSistema in listaSistemasEnFila) {
        final key = normalizeSys(rawSistema);
        String? sistemaCanon = canonicalMap[key];

        if (sistemaCanon == null && key.isNotEmpty) {
          final match = canonicalMap.keys.firstWhere((k) => k.contains(key) || key.contains(k), orElse: () => '');
          if (match.isNotEmpty) sistemaCanon = canonicalMap[match];
        }

        if (sistemaCanon != null) {
          if (seenThisRow.contains(sistemaCanon)) continue;
          if (valorCalificacion > 0) {
            sumasPorSistemaNivel[sistemaCanon]![nivelKey] = (sumasPorSistemaNivel[sistemaCanon]![nivelKey] ?? 0.0) + valorCalificacion;
            conteosPorSistemaNivel[sistemaCanon]![nivelKey] = (conteosPorSistemaNivel[sistemaCanon]![nivelKey] ?? 0) + 1;
          }
          seenThisRow.add(sistemaCanon);
        } else {
          debugPrint('⚠️ Sistema no mapeado: "$rawSistema" (normalizado: "$key")');
        }
      }
    }

    // Calcular promedios
    final Map<String, Map<String, double>> promediosData = {};
    for (final sistemaNombre in sistemasOrdenados) {
      promediosData[sistemaNombre] = {'E': 0.0, 'G': 0.0, 'M': 0.0};
      for (final nivelKey in ['E', 'G', 'M']) {
        final double suma = sumasPorSistemaNivel[sistemaNombre]![nivelKey]!;
        final int conteo = conteosPorSistemaNivel[sistemaNombre]![nivelKey]!;
        if (conteo > 0) {
          promediosData[sistemaNombre]![nivelKey] = suma / conteo;
        } else {
          promediosData[sistemaNombre]![nivelKey] = 0.0;
        }
      }
    }
    return promediosData;
  }

  /// Carga los datos de benchmark desde los archivos JSON
  Future<List<Map<String, dynamic>>> _cargarDatosBenchmark() async {
    final List<Map<String, dynamic>> allData = [];
    
    // Cargar los 3 archivos JSON
    for (int i = 1; i <= 3; i++) {
      try {
        final jsonString = await rootBundle.loadString('assets/t$i.json');
        final List<dynamic> data = json.decode(jsonString);
        allData.addAll(data.cast<Map<String, dynamic>>());
      } catch (e) {
        debugPrint('Error cargando t$i.json: $e');
      }
    }
    
    return allData;
  }

 /// Obtiene la interpretación del JSON según comportamiento, nivel y calificación
String _getInterpretacionFromJson(
  List<Map<String, dynamic>> benchmarkData,
  String comportamiento,
  String nivel,
  double promedio,
) {
  // Convertir promedio a calificación C1-C5
  String calificacion;
  if (promedio <= 1.0) calificacion = 'C1';
  else if (promedio <= 2.0) calificacion = 'C2';
  else if (promedio <= 3.0) calificacion = 'C3';
  else if (promedio <= 4.0) calificacion = 'C4';
  else calificacion = 'C5';

  // Normalizador tolerante
  String normalize(String s) {
    var t = s.toLowerCase().trim();
    const accents = {'á':'a','é':'e','í':'i','ó':'o','ú':'u','ü':'u','ñ':'n'};
    accents.forEach((k,v)=>t=t.replaceAll(k,v));
    t = t.replaceAll(RegExp(r'[^a-z0-9\s:]'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    return t;
  }

  // Mapear comportamiento desde nuestro modelo al JSON
  String comportamientoJson = _mapearComportamientoAJson(comportamiento);
  final normComp = normalize(comportamientoJson);

  // Mapear nivel a formato JSON
  String nivelJson;
  switch (nivel) {
    case 'E':
      nivelJson = 'EJECUTIVO';
      break;
    case 'G':
      nivelJson = 'GERENTE';
      break;
    case 'M':
      nivelJson = 'MIEMBRO DE EQUIPO';
      break;
    default:
      nivelJson = 'EJECUTIVO';
  }

  // Buscar en el JSON (coincidencia parcial antes de los “:”)
  for (final item in benchmarkData) {
    final raw = item['BENCHMARK DE COMPORTAMIENTOS']?.toString() ?? '';
    final normItem = normalize(raw);
    final baseName = normItem.split(':').first.trim();

    if ((baseName.contains(normComp) || normComp.contains(baseName)) &&
        item['NIVEL'] == nivelJson) {
      return item[calificacion]?.toString() ?? 'Sin interpretación disponible';
    }
  }

  return 'Interpretación no encontrada para $comportamiento - $nivel - $calificacion';
}

/// Obtiene el benchmark por cargo del JSON
String _getBenchmarkFromJson(
  List<Map<String, dynamic>> benchmarkData,
  String comportamiento,
  String nivel,
) {
  // Normalizador tolerante
  String normalize(String s) {
    var t = s.toLowerCase().trim();
    const accents = {'á':'a','é':'e','í':'i','ó':'o','ú':'u','ü':'u','ñ':'n'};
    accents.forEach((k,v)=>t=t.replaceAll(k,v));
    t = t.replaceAll(RegExp(r'[^a-z0-9\s:]'), ' ');
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    return t;
  }

  // Mapear comportamiento desde nuestro modelo al JSON
  String comportamientoJson = _mapearComportamientoAJson(comportamiento);
  final normComp = normalize(comportamientoJson);

  // Mapear nivel a formato JSON
  String nivelJson;
  switch (nivel) {
    case 'E':
      nivelJson = 'EJECUTIVO';
      break;
    case 'G':
      nivelJson = 'GERENTE';
      break;
    case 'M':
      nivelJson = 'MIEMBRO DE EQUIPO';
      break;
    default:
      nivelJson = 'EJECUTIVO';
  }

  // Buscar en el JSON (coincidencia parcial antes de los “:”)
  for (final item in benchmarkData) {
    final raw = item['BENCHMARK DE COMPORTAMIENTOS']?.toString() ?? '';
    final normItem = normalize(raw);
    final baseName = normItem.split(':').first.trim();

    if ((baseName.contains(normComp) || normComp.contains(baseName)) &&
        item['NIVEL'] == nivelJson) {
      return item['BENCHMARK POR NIVEL']?.toString() ?? 'Benchmark no disponible';
    }
  }

  return 'Benchmark no encontrado para $comportamiento - $nivel';
}

  /// Mapea los nombres de comportamientos de nuestro modelo a los del JSON
  String _mapearComportamientoAJson(String comportamiento) {
    // Mapeo de nombres de comportamientos
    final Map<String, String> mapeo = {
      'Soporte': 'Soporte',
      'Reconocer': 'Reconocer',
      'Comunidad': 'Comunidad',
      'Liderazgo de Servidor': 'Liderazgo de Servidor',
      'Valorar': 'Valorar',
      'Empoderar': 'Empoderar',
      'Mentalidad': 'Mentalidad',
      'Estructura': 'Estructura',
      'Reflexionar': 'Reflexionar',
      'Análisis': 'Análisis',
      'Colaborar': 'Colaborar',
      'Comprender': 'Comprender',
      'Diseño': 'Diseño',
      'Atribución': 'Atribución',
      'A Prueba de Errores': 'A Prueba de Errores',
      'Propiedad': 'Propiedad',
      'Conectar': 'Conectar',
      'Ininterrumpido': 'Ininterrumpido',
      'Demanda': 'Demanda',
      'Eliminar': 'Eliminar',
      'Optimizar': 'Optimizar',
      'Impacto': 'Impacto',
      'Alinear': 'Alinear',
      'Aclarar': 'Aclarar',
      'Comunicar': 'Comunicar',
      'Relación': 'Relación',
      'Valor': 'Valor',
      'Medida': 'Medida'
};


    return mapeo[comportamiento] ?? comportamiento;
  }

/// Prepara los datos para el reporte PDF (modo horizontal)
Future<List<ReporteComportamiento>> _prepararDatosPdf() async {
  final List<ReporteComportamiento> reporteData = [];

  // Cargar datos de benchmark desde JSON
  final benchmarkData = await _cargarDatosBenchmark();

  // Agrupar todas las filas de _dimensionesRaw por comportamiento y nivel
  final Map<String, Map<String, List<Map<String, dynamic>>>> datosAgrupados = {};

  for (final row in _dimensionesRaw) {
    final compNombre = row['comportamiento'] as String?;
    if (compNombre == null) continue;

    String? nivelKey;
    final cargoRaw = (row['cargo_raw'] as String?)?.toLowerCase().trim() ?? '';
    if (cargoRaw.contains('ejecutivo')) {
      nivelKey = 'E';
    } else if (cargoRaw.contains('gerente')) {
      nivelKey = 'G';
    } else if (cargoRaw.contains('miembro')) {
      nivelKey = 'M';
    }
    if (nivelKey == null) continue;

    datosAgrupados.putIfAbsent(compNombre, () => {}).putIfAbsent(nivelKey, () => []).add(row);
  }

  // Extraer los comportamientos en orden desde el modelo
  final todosLosComportamientos = EvaluacionChartData.extractComportamientos(_dimensiones);

  for (final comp in todosLosComportamientos) {
    final Map<String, NivelEvaluacion> nivelesData = {};

    if (datosAgrupados.containsKey(comp.nombre)) {
      for (final nivelEntry in datosAgrupados[comp.nombre]!.entries) {
        final nivel = nivelEntry.key; // 'E', 'G', 'M'
        final filasNivel = nivelEntry.value;

        if (filasNivel.isEmpty) continue;

        // Calcular promedio para este grupo
        double suma = 0;
        int conteo = 0;
        final Set<String> sistemas = {};
        final List<String> observaciones = [];

        for (final fila in filasNivel) {
          final valor = (fila['valor'] as num?)?.toDouble() ?? 0.0;
          if (valor > 0) {
            suma += valor;
            conteo++;
          }

          // Extraer sistemas
          final sistemasFila = (fila['sistemas'] as List<dynamic>?)?.map((s) => s.toString()).toList() ?? [];
          sistemas.addAll(sistemasFila);

          // Observaciones
          final obs = fila['observaciones'] as String?;
          if (obs != null && obs.isNotEmpty) {
            observaciones.add(obs);
          }
        }

        if (conteo > 0) {
          final promedio = suma / conteo;
          final interpretacion = _getInterpretacionFromJson(benchmarkData, comp.nombre, nivel, promedio);
          final benchmark = _getBenchmarkFromJson(benchmarkData, comp.nombre, nivel);
          final hallazgos = observaciones.isNotEmpty ? '- ${observaciones.join('\n- ')}' : 'Sin observaciones';

          nivelesData[nivel] = NivelEvaluacion(
              valor: promedio,
            interpretacion: interpretacion,
            benchmarkPorCargo: benchmark,
            obs: hallazgos,
            sistemasSeleccionados: sistemas.toList(),
          );
        }
      }
    }

  final benchmarkGeneral = benchmarkData.firstWhere(
  (item) =>
      item['BENCHMARK DE COMPORTAMIENTOS'] != null &&
      item['BENCHMARK DE COMPORTAMIENTOS']
          .toString()
          .toLowerCase()
          .contains(_mapearComportamientoAJson(comp.nombre).toLowerCase()),
  orElse: () => {},
)['BENCHMARK DE COMPORTAMIENTOS'] ?? 'Benchmark no disponible';

reporteData.add(
  ReporteComportamiento(
    nombre: comp.nombre,
    benchmarkGeneral: benchmarkGeneral,
    niveles: nivelesData,
  ),
);
  }

  return reporteData;
}


  /// Callback al presionar "Generar Word"
  Future<void> _onGenerarReporteWord(List<String> recomendaciones) async {
    final datos = await _prepararDatosPdf();
    final nombreEmpresa = widget.empresa.nombre;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Generando reporte Word...')));
  await reporte_service.ReporteService.generarYSubirReporte(
      formato: 'WORD',
      datos: datos,
      nombreEmpresa: nombreEmpresa,
      recomendaciones: recomendaciones,
      onStatus: (msg) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      },
    );
  }

  /// Callback al presionar "Generar PDF"
  Future<void> _onGenerarReportePdf(List<String> recomendaciones) async {
    final datos = await _prepararDatosPdf();
    final nombreEmpresa = widget.empresa.nombre;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Generando reporte PDF...')));
  await reporte_service.ReporteService.generarYSubirReporte(
      formato: 'PDF',
      datos: datos,
      nombreEmpresa: nombreEmpresa,
      recomendaciones: recomendaciones,
      onStatus: (msg) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      },
    );
  }

  /// Callback al presionar "Generar Excel"
  Future<void> _onGenerarReporteExcel(List<String> recomendaciones) async {
    final datos = await _prepararDatosPdf();
    final nombreEmpresa = widget.empresa.nombre;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Generando reporte Excel...')));
  await reporte_service.ReporteService.generarYSubirReporte(
      formato: 'EXCEL',
      datos: datos,
      nombreEmpresa: nombreEmpresa,
      recomendaciones: recomendaciones,
      onStatus: (msg) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Preparar datos para el gráfico de sistemas
    final horizontalData = _buildHorizontalBarsData();

    return Scaffold(
      key: _scaffoldKey,

      // Drawer izquierdo para chat (80% del ancho)
      drawer: SizedBox(child: const ChatWidgetDrawer()),

      // EndDrawer derecho normal (sin envolver en SizedBox)
      endDrawer: const DrawerLensys(),

      appBar: AppBar(
        backgroundColor: const Color(0xFF003056),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        title: Text(
          'Dashboard - ${widget.empresa.nombre}',
          style: const TextStyle(color: Colors.white, fontSize: 20),
        ),
        centerTitle: true,
      ),

      body: Row(
        children: [
          // ► Lado izquierdo: ListView con los 4 gráficos (ocupa todo el espacio restante)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                children: [
                  _buildChartContainer(
                    child: MultiRingChart(
                      puntosObtenidos: _buildMultiringData(),
                      isDetail: false,
                    ),
                    color: const Color.fromARGB(255, 218, 221, 221),
                    title: 'PROGRESO DIMENSION',
                  ),

                  _buildChartContainer(
                    color: const Color.fromARGB(255, 225, 226, 226),
                    child: ScatterBubbleChart(
                      key: ValueKey(
                        'scatter_${DateTime.now().millisecondsSinceEpoch}',
                      ),
                      data: _buildScatterData(),
                      isDetail: false,
                    ),
                    title: 'EVALUACION-PRINCIPIO-ROL',
                  ),

                  _buildChartContainer(
                    color: const Color.fromARGB(255, 225, 226, 226),
                    title: 'EVALUACION COMPORTAMIENTO-ROL',
                    child: GroupedBarChart(
                      data: _buildGroupedBarData(),
                      minY: 0,
                      maxY: 5,
                      isDetail: false,
                    ),
                  ),

                  _buildChartContainer(
                    color: const Color.fromARGB(255, 225, 226, 226),
                    title: 'EVALUACION SISTEMAS-ROL',
                    child: HorizontalBarSystemsChart(
                      data: horizontalData,
                      minY: 0,
                      maxY: 5, // Adecuado para promedios en escala 0-5
                    ),
                  ),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          Container(
            width: 56, // ancho normal de sidebar
            color: const Color.fromARGB(255, 3, 51, 90), // mismo color del AppBar
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 18),
                Tooltip(
                  message: 'Ejecutivo',
                  child: Column(
                    children: [
                      Icon(Icons.help_outline, color: Colors.orange, size: 32),
                      const SizedBox(height: 4),
                      Text(
                        'Ejecutivo',
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Tooltip(
                  message: 'Gerente',
                  child: Column(
                    children: [
                      Icon(Icons.help_outline, color: Colors.green, size: 32),
                      const SizedBox(height: 4),
                      Text(
                        'Gerente',
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Tooltip(
                  message: 'Miembro de equipo',
                  child: Column(
                    children: [
                      Icon(Icons.help_outline, color: Colors.blue, size: 32),
                      const SizedBox(height: 4),
                      Text(
                        'Miembro de equipo',
                        style: TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                // Chat interno
                IconButton(
                  icon: const Icon(Icons.chat, color: Colors.white),
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  tooltip: 'Chat Interno',
                ),
                // Menú de reportes (PDF, Excel)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.file_present, color: Colors.amber),
                  tooltip: 'Generar Reporte',
                  itemBuilder:
                      (context) => [
                        PopupMenuItem(
                          value: 'word',
                          child: Row(
                            children: [
                              const Icon(Icons.description, color: Colors.blue),
                              SizedBox(width: 8),
                              Text('Reporte Word'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'pdf',
                          child: Row(
                            children: [
                              const Icon(
                                Icons.picture_as_pdf,
                                color: Colors.red,
                              ),
                              SizedBox(width: 8),
                              Text('Reporte PDF'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'excel',
                          child: Row(
                            children: [
                              const Icon(
                                Icons.table_chart,
                                color: Colors.green,
                              ),
                              SizedBox(width: 8),
                              Text('Reporte Excel'),
                            ],
                          ),
                        ),
                      ],
                  onSelected: (formato) async {
                    // Eliminado requerimiento de recomendaciones: generar reporte sin ellas
                    final recomendaciones = <String>[];
                    if (formato == 'word') {
                      await _onGenerarReporteWord(recomendaciones);
                    } else if (formato == 'pdf') {
                      await _onGenerarReportePdf(recomendaciones);
                    } else if (formato == 'excel') {
                      await _onGenerarReporteExcel(recomendaciones);
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Cada gráfico está dentro de un contenedor redondeado, con encabezado y margen.
  Widget _buildChartContainer({
    required Color color,
    required String title,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          // Encabezado interno (subtítulo) con fondo blanco
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
            color: Color(0xFF003056), // mismo color del AppBar
              ),
            ),
          ),

          // Espacio para el gráfico (alto fijo de 420px)
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: SizedBox(height: 428, child: child),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Quitar listener de TablasDimensionScreen y cancelar timer de debounce
    try {
      TablasDimensionScreen.dataChanged.removeListener(_onTablasDataChanged);
    } catch (_) {}
    _reloadTimer?.cancel();
    super.dispose();
  }
}