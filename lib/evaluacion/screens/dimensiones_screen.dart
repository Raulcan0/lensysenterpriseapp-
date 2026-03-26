// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:applensys/evaluacion/models/empresa.dart';
import 'package:applensys/evaluacion/screens/asociado_screen.dart';
import 'package:applensys/evaluacion/screens/empresas_screen.dart';
import 'package:applensys/evaluacion/screens/tablas_screen.dart';
import 'package:applensys/evaluacion/screens/shingo_result.dart' as shingo_screen;
import 'package:applensys/evaluacion/screens/tabla_resumen_global.dart';
import 'package:applensys/evaluacion/services/evaluacion_cache_service.dart';
import 'package:applensys/evaluacion/services/supabase_service.dart';
import 'package:applensys/evaluacion/widgets/drawer_lensys.dart';
import 'package:applensys/evaluacion/widgets/chat_screen.dart';

class DimensionesScreen extends StatefulWidget {
  final Empresa empresa;
  final String evaluacionId;

  const DimensionesScreen({
    super.key,
    required this.empresa,
    required this.evaluacionId,
  });

  @override
  State<DimensionesScreen> createState() => _DimensionesScreenState();
}

class _DimensionesScreenState extends State<DimensionesScreen> {
  final List<Map<String, dynamic>> dimensiones = const [
    {
      'id': '1',
      'nombre': 'IMPULSORES CULTURALES',
      'icono': Icons.group,
      'color': Color.fromARGB(255, 122, 141, 245),
    },
    {
      'id': '2',
      'nombre': 'MEJORA CONTINUA',
      'icono': Icons.update,
      'color': Color.fromARGB(255, 67, 78, 141),
    },
    {
      'id': '3',
      'nombre': 'ALINEAMIENTO EMPRESARIAL',
      'icono': Icons.business,
      'color': Color.fromARGB(255, 14, 24, 78),
    },
    {
      'id': 'shingo',
      'nombre': 'EVALUACION RESULTADOS',
      'icono': Icons.insert_chart,
      'color': Color.fromARGB(255, 27, 31, 66),
    },
    {
      'id': 'final',
      'nombre': 'EVALUACION FINAL',
      'icono': Icons.assignment_turned_in,
      'color': Color.fromARGB(255, 2, 33, 58),
    },
  ];

  bool _evaluacionFinalizada = false;

  @override
  void initState() {
    super.initState();
    _verificarEstadoEvaluacion();
  }

  Future<void> _verificarEstadoEvaluacion() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _evaluacionFinalizada = prefs.getBool('evaluacion_finalizada_${widget.evaluacionId}') ?? false;
    });
  }

  Future<void> _guardarProgreso() async {
    await SupabaseService().guardarEvaluacionDraft(widget.evaluacionId);
    await EvaluacionCacheService().guardarPendiente(widget.evaluacionId);
    await EvaluacionCacheService().guardarTablas(TablasDimensionScreen.tablaDatos);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Progreso guardado localmente')),
    );
  }

  Future<void> _finalizarEvaluacion() async {
    try {
      final cache = EvaluacionCacheService();
      final prefs = await SharedPreferences.getInstance();

      // NO tocar Supabase: sólo limpiar estado local/UI para iniciar de 0.
      // marcar localmente la evaluación como finalizada
      await prefs.setBool('evaluacion_finalizada_${widget.evaluacionId}', true);

      // guardar en historial local si no está
      final historial = prefs.getStringList('empresas_historial') ?? [];
      if (!historial.contains(widget.empresa.id)) {
        historial.add(widget.empresa.id);
        await prefs.setStringList('empresas_historial', historial);
      }

      // limpieza local completa (SharedPreferences + tablas cache)
      await cache.limpiarEvaluacionCompleta();

      // Reiniciar tablas en memoria y persistir estado vacío
      TablasDimensionScreen.tablaDatos = {
        'Dimensión 1': {},
        'Dimensión 2': {},
        'Dimensión 3': {},
      };
      await cache.guardarTablas(TablasDimensionScreen.tablaDatos);
      TablasDimensionScreen.dataChanged.value = !TablasDimensionScreen.dataChanged.value;

      // Limpiar observaciones/hojas Shingo almacenadas localmente (no tocar DB remota)
      try {
        await cache.limpiarObservaciones();
      } catch (_) {}

      // Reset en memoria de las hojas Shingo y persistir vacío
      try {
        shingo_screen.ShingoCategorias.tablaShingo = {
          for (var cat in [
            'seguridad/medio/ambiente/moral',
            'satisfacción del cliente',
            'calidad',
            'costo/productividad',
            'entregas',
          ])
            cat: shingo_screen.ShingoResultData()
        };
        await shingo_screen.ShingoCategorias.guardarTablaShingo();
      } catch (_) {}

      // Detener suscripciones locales (si existieran) y resetear notifiers en memoria
      try {
        EvaluacionAutoSyncService().detenerEscucha();
      } catch (_) {}

      try {
        DimensionesSyncService.dimensionesNotifier.value = {
          'Dimensión 1': {},
          'Dimensión 2': {},
          'Dimensión 3': {},
        };
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Evaluación finalizada y UI reiniciada (solo localmente)')),
        );
        await Future.delayed(const Duration(milliseconds: 600));
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const EmpresasScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al finalizar evaluación: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey<ScaffoldState>();
    const double cardHeight = 150;

    return Scaffold(
      key: scaffoldKey,
      drawer: SizedBox(width: 300, child: const ChatWidgetDrawer()),
      appBar: AppBar(
        backgroundColor: const Color(0xFF003056),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const EmpresasScreen()),
            );
          },
        ),
        title: Text(
          'Dimensiones - ${widget.empresa.nombre}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 20,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
      ),
      endDrawer: const DrawerLensys(),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: dimensiones.length,
              itemBuilder: (context, index) {
                final dimension = dimensiones[index];
                return SizedBox(
                  height: cardHeight,
                  child: _buildCard(
                    icon: dimension['icono'],
                    color: dimension['color'],
                    title: dimension['nombre'],
                    child: index < 3
                        ? FutureBuilder<double>(
                            future: SupabaseService().obtenerProgresoDimension(
                              widget.empresa.id,
                              dimension['id'],
                            ),
                            builder: (context, snapshot) {
                              final progreso = (snapshot.data ?? 0.0).clamp(0.0, 1.0);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  LinearProgressIndicator(
                                    value: progreso,
                                    minHeight: 8,
                                    backgroundColor: const Color.fromARGB(255, 156, 156, 156),
                                    color: dimension['color'],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${(progreso * 100).toStringAsFixed(1)}% completado',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              );
                            },
                          )
                        : null,
                    onTap: _evaluacionFinalizada
                        ? null
                        : () async {
                            if (index < 3) {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AsociadoScreen(
                                    nombreDimension: dimension['nombre'],
                                    empresa: widget.empresa,
                                    dimensionId: dimension['id'],
                                    evaluacionId: widget.evaluacionId,
                                  ),
                                ),
                              );
                              if (mounted) setState(() {});
                            } else if (index == 3) {
                              await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => shingo_screen.ShingoCategorias(
                                      empresa: widget.empresa,
                                      evaluacionId: widget.evaluacionId,
                                    ),
                                  ),
                                );
                              if (mounted) setState(() {});
                            } else if (index == 4) {
                              final promediosPorDimension = AuxTablaService.obtenerPromediosPorDimensionYCargo();
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TablaResumenGlobal(
                                    promediosPorDimension: promediosPorDimension,
                                  ),
                                ),
                              );
                            }
                          },
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.save),
                  label: const Text('Guardar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF003056),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                  onPressed: _evaluacionFinalizada ? null : _guardarProgreso,
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Finalizar evaluación'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  ),
                  onPressed: _evaluacionFinalizada ? null : _finalizarEvaluacion,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required IconData icon,
    required Color color,
    required String title,
    Widget? child,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                if (child != null) ...[
                  const SizedBox(height: 10),
                  child,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}