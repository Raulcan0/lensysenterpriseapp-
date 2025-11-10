// ignore_for_file: use_build_context_synchronously

import 'dart:typed_data';
import 'package:applensys/evaluacion/models/calificacion.dart';
import 'package:applensys/evaluacion/services/calificacion_service.dart';
import 'package:applensys/evaluacion/services/storage_service.dart';
import 'package:applensys/evaluacion/widgets/lentes_madurez_por_rol_table.dart';
import 'package:applensys/evaluacion/widgets/sistemas_asociados.dart';
import 'package:applensys/evaluacion/screens/tablas_screen.dart';
import 'package:applensys/evaluacion/widgets/drawer_lensys.dart';
import 'package:applensys/evaluacion/providers/text_size_provider.dart';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import 'package:applensys/evaluacion/models/principio_json.dart';
import 'package:applensys/evaluacion/models/asociado.dart';

/// Sistemas sugeridos por comportamiento
const Map<String, String> sistemasRecomendadosPorComportamiento = {
  "Soporte": "Desarrollo de Personal, Medición, Reconocimiento",
  "Reconocer":
      "Medición, Involucramiento, Reconocimiento, Desarrollo de Personal",
  "Comunidad": "Seguridad, Ambiental, EHS, Compromiso, Desarrollo de Personal",
  "Liderazgo de Servidor": "Desarrollo de Personal",
  "Valorar": "Desarrollo de Personal, Involucramiento",
  "Empoderar": "Medición, Reconocimiento, Desarrollo de Personal",
  "Mentalidad": "Sistemas de Mejora",
  "Estructura": "Sistemas de Mejora",
  "Reflexionar": "Solución de Problemas",
  "Análisis": "Solución de Problemas",
  "Colaborar": "Solución de Problemas",
  "Comprender": "Solución de Problemas, Gestión Visual",
  "Diseño": "Sistemas de Mejora, Gestión Visual",
  "Atribución": "Sistemas de Mejora, Solución de Problemas",
  "A Prueba de Errores": "Sistemas de Mejora, Solución de Problemas",
  "Propiedad": "Sistemas de Mejora, Solución de Problemas",
  "Conectar": "Sistemas de Mejora",
  "Ininterrumpido": "Planificación y Programación, Sistemas de Mejora",
  "Demanda": "Planificación y Programación",
  "Eliminar": "Voz de cliente, Sistemas de Mejora",
  "Optimizar": "Sistemas de Mejora, Despliegue de Estrategia",
  "Impacto": "Sistemas de Mejora",
  "Alinear": "Despliegue de Estrategia",
  "Aclarar": "Comunicación, Despliegue de Estrategia",
  "Comunicar": "Comunicación, Despliegue de Estrategia",
  "Relación": "Voz del Cliente",
  "Valor": "Voz del Cliente",
  "Medida":
      "Despliegue de Estrategia, Medición, Voz del Cliente, Recompensas, Reconocimientos",
};

/// Normaliza strings como "d2", "D3", "2" -> 2..3; fallback 1
int _dimensionNumero(String raw) {
  final m = RegExp(r'\d+').firstMatch(raw);
  final n = int.tryParse(m?.group(0) ?? '') ?? 1;
  if (n < 1 || n > 3) return 1;
  return n;
}

/// Retorna la clave que TablasDimensionScreen espera: "Dimensión N"
String obtenerNombreDimensionInterna(String raw) {
  switch (_dimensionNumero(raw)) {
    case 1:
      return 'Dimensión 1';
    case 2:
      return 'Dimensión 2';
    case 3:
      return 'Dimensión 3';
    default:
      return 'Dimensión 1';
  }
}

class ComportamientoEvaluacionScreen extends ConsumerStatefulWidget {
  final PrincipioJson principio;
  final String principioNomre;
  final Asociado asociado;
  final String evaluacionId;
  final String dimensionId; // puede venir "d1" o "1"
  final String empresaId;
  final Calificacion? calificacionExistente;

  const ComportamientoEvaluacionScreen({
    super.key,
    required this.principio,
    required this.asociado,
    required this.evaluacionId,
    required this.principioNomre,
    required this.dimensionId,
    required this.empresaId,
    this.calificacionExistente,
    required String dimension,
    required String cargo,
    required String asociadoId,
  });

  @override
  ConsumerState<ComportamientoEvaluacionScreen> createState() =>
      _ComportamientoEvaluacionScreenState();
}

class _ComportamientoEvaluacionScreenState
    extends ConsumerState<ComportamientoEvaluacionScreen> {
  final storageService = StorageService();
  final calificacionService = CalificacionService();
  final _picker = ImagePicker();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  late int calificacion;
  final observacionController = TextEditingController();
  List<String> sistemasSeleccionados = [];
  bool isSaving = false;
  String? evidenciaUrl;

  @override
  void initState() {
    super.initState();
    if (widget.calificacionExistente != null) {
      final c = widget.calificacionExistente!;
      calificacion = c.puntaje;
      observacionController.text = c.observaciones ?? '';
      sistemasSeleccionados = List<String>.from(c.sistemas);
      evidenciaUrl = c.evidenciaUrl;
    } else {
      calificacion = 0;
    }
  }

  String _normalizeTitle(String raw) {
    final s = raw.toString().trim();
    if (s.isEmpty) return '';
    return s
        .split(RegExp(r"\s+"))
        .map(
          (w) =>
              w.isEmpty
                  ? w
                  : (w[0].toUpperCase() + w.substring(1).toLowerCase()),
        )
        .join(' ');
  }

  Future<void> _saveSelectedSystems(List<String> selected) async {
    setState(() => sistemasSeleccionados = List.from(selected));
    // Sincroniza la dimensión actual para todos los dispositivos de la empresa
  }

  void _showAlert(String title, String message) {
    showDialog<void>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          ),
    );
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.gallery);
      if (photo == null) return;
      final Uint8List bytes = await photo.readAsBytes();
      final String fileName = const Uuid().v4();

      await storageService.uploadFile(
        bucket: 'evidencias',
        path: fileName,
        bytes: bytes,
        contentType: 'image/jpeg',
      );
      evidenciaUrl = storageService.getPublicUrl(
        bucket: 'evidencias',
        path: fileName,
      );
      setState(() {});
      _showAlert('Evidencia', 'Imagen subida correctamente.');
    } catch (e) {
      _showAlert('Error', 'No se pudo obtener la imagen: $e');
    }
  }

  Future<void> _guardarEvaluacion() async {
    final obs = observacionController.text.trim();
    if (obs.isEmpty) {
      _showAlert('Validación', 'Debes escribir una observación.');
      return;
    }
    if (sistemasSeleccionados.isEmpty) {
      _showAlert('Validación', 'Selecciona al menos un sistema.');
      return;
    }

    setState(() => isSaving = true);
    try {
      final nombreComp =
          widget.principio.benchmarkComportamiento.split(':').first.trim();
      // Normalizar principio y cargo para guardado (mantener texto legible)
      final principioNorm = _normalizeTitle(widget.principio.nombre);
      final cargoNorm = _normalizeTitle(widget.asociado.cargo);
      final dimIdNum = _dimensionNumero(widget.dimensionId);

      // Buscar calificación existente si no vino por parámetro
      final existente =
          widget.calificacionExistente ??
          await calificacionService.getCalificacionExistente(
            idAsociado: widget.asociado.id,
            idEmpresa: widget.empresaId,
            idDimension: dimIdNum,
            comportamiento: nombreComp,
          );

      // Si existe y no se venía desde "editar", pedir confirmación
      bool editar = existente != null;
      if (existente != null && widget.calificacionExistente == null) {
        final resp = await showDialog<bool>(
          context: context,
          builder:
              (_) => AlertDialog(
                title: const Text('Modificar calificación'),
                content: const Text(
                  'Ya existe una calificación para este comportamiento. ¿Deseas modificarla?',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('No'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Sí'),
                  ),
                ],
              ),
        );
        editar = resp ?? false;
      }

      final calObj = Calificacion(
        id: existente?.id ?? const Uuid().v4(),
        idAsociado: widget.asociado.id,
        idEmpresa: widget.empresaId,
        idDimension: dimIdNum,
        comportamiento: nombreComp,
        puntaje: calificacion,
        cargo: cargoNorm,
        fechaEvaluacion: DateTime.now(),
        observaciones: obs,
        sistemas: sistemasSeleccionados,
        evidenciaUrl: evidenciaUrl,
        principio: principioNorm,
        principioNombre: principioNorm,
      );

      if (existente != null) {
        if (!editar) {
          setState(() => isSaving = false);
          return;
        }
        await calificacionService.updateCalificacionFull(calObj);
      } else {
        await calificacionService.addCalificacion(calObj);
      }

      await TablasDimensionScreen.actualizarDato(
        widget.evaluacionId,
        dimension: obtenerNombreDimensionInterna(widget.dimensionId),
        comportamiento: nombreComp,
        cargo: cargoNorm,
        valor: calificacion,
        sistemas: sistemasSeleccionados,
        dimensionId: widget.dimensionId, 
        asociadoId: widget.asociado.id,
        observaciones: obs,
        principio: principioNorm,
      );     

      if (mounted) Navigator.pop(context, nombreComp);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al guardar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  void _mostrarLentesRolDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder:
          (_) => AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 150,
              vertical: 130,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            backgroundColor: Colors.white,
            content: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.90,
                maxHeight: MediaQuery.of(context).size.height * 0.85,
              ),
              child: ScrollConfiguration(
                behavior: MaterialScrollBehavior().copyWith(
                  dragDevices: {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.mouse,
                    PointerDeviceKind.trackpad,
                  },
                ),
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: LentesMadurezPorRolTable(),
                  ),
                ),
              ),
            ),
            actionsAlignment: MainAxisAlignment.end,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textSize = ref.watch(textSizeProvider);
    final double scaleFactor = textSize / 14.0;

    final desc =
        widget.principio.calificaciones['C$calificacion'] ??
        'Desliza para agregar una calificación';

    return Scaffold(
      key: _scaffoldKey,
      endDrawer: const DrawerLensys(),
      appBar: AppBar(
        backgroundColor: const Color(0xFF003056),
        centerTitle: true,
        title: Column(
          children: [
            Text(
              widget.principio.nombre,
              style: TextStyle(color: Colors.white, fontSize: 20 * scaleFactor),
            ),
            Text(
              widget.principio.benchmarkComportamiento.split(':').first.trim(),
              style: TextStyle(color: Colors.white, fontSize: 14 * scaleFactor),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Benchmark text
            Text(
              'Benchmark: ${widget.principio.benchmarkPorNivel}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14 * scaleFactor,
              ),
            ),
            const SizedBox(height: 8),
            // Guía y Sistemas asociados
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.help_outline),
                    label: Text(
                      'Guía',
                      style: TextStyle(fontSize: 14 * scaleFactor),
                    ),
                    onPressed:
                        () => _showAlert('Guía', widget.principio.preguntas),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF003056),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      padding: EdgeInsets.symmetric(
                        vertical: 12 * scaleFactor,
                        horizontal: 16 * scaleFactor,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.settings),
                    label: Text(
                      'Sistemas asociados',
                      style: TextStyle(fontSize: 14 * scaleFactor),
                    ),
                    onPressed:
                        isSaving
                            ? null
                            : () async {
                              final seleccion = await showModalBottomSheet<
                                List<String>
                              >(
                                context: context,
                                isScrollControlled: true,
                                builder:
                                    (_) => SistemasScreen(
                                      onSeleccionar:
                                          (s) => Navigator.pop(
                                            context,
                                            s
                                                .map(
                                                  (e) => e['nombre'].toString(),
                                                )
                                                .toList(),
                                          ),
                                    ),
                              );
                              if (seleccion != null) {
                                await _saveSelectedSystems(seleccion);
                              }
                            },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF003056),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                      padding: EdgeInsets.symmetric(
                        vertical: 12 * scaleFactor,
                        horizontal: 16 * scaleFactor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (evidenciaUrl != null) ...[
              Image.network(evidenciaUrl!, height: 200 * scaleFactor),
              const SizedBox(height: 16),
            ],

            Text(
              'Calificación:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14 * scaleFactor,
              ),
            ),
            Slider(
              value: calificacion.toDouble(),
              min: 0,
              max: 5,
              divisions: 5,
              label: calificacion.toString(),
              activeColor: const Color(0xFF003056),
              inactiveColor: const Color(0xFF003056).withAlpha(77),
              onChanged:
                  isSaving
                      ? null
                      : (v) => setState(() => calificacion = v.round()),
            ),
            Text(desc, style: TextStyle(fontSize: 14 * scaleFactor)),
            const SizedBox(height: 16),

            ElevatedButton.icon(
              icon: const Icon(Icons.remove_red_eye),
              label: Text(
                'Ver lentes de madurez',
                style: TextStyle(fontSize: 14 * scaleFactor),
              ),
              onPressed: _mostrarLentesRolDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF003056),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
                padding: EdgeInsets.symmetric(
                  vertical: 12 * scaleFactor,
                  horizontal: 16 * scaleFactor,
                ),
              ),
            ),

            // Sugeridos por comportamiento
            if (sistemasRecomendadosPorComportamiento.containsKey(
              widget.principio.benchmarkComportamiento.split(':').first.trim(),
            )) ...[
              const SizedBox(height: 8),
              Text(
                sistemasRecomendadosPorComportamiento[widget
                        .principio
                        .benchmarkComportamiento
                        .split(':')
                        .first
                        .trim()]!
                    .replaceAll('\\n', ', '),
                style: TextStyle(
                  color: const Color(0xFF003056),
                  fontSize: 13 * scaleFactor,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: observacionController,
                    maxLines: 2,
                    enabled: !isSaving,
                    decoration: const InputDecoration(
                      hintText: 'Observaciones...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.camera_alt, size: 28),
                  onPressed: isSaving ? null : _takePhoto,
                ),
              ],
            ),

            if (sistemasSeleccionados.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Sistemas Asociados:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14 * scaleFactor,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8.0,
                runSpacing: 4.0,
                children:
                    sistemasSeleccionados
                        .map(
                          (s) => Chip(
                            label: Text(
                              s,
                              style: TextStyle(fontSize: 12 * scaleFactor),
                            ),
                            onDeleted:
                                () => _saveSelectedSystems(
                                  List<String>.from(sistemasSeleccionados)
                                    ..remove(s),
                                ),
                          ),
                        )
                        .toList(),
              ),
            ],

            const SizedBox(height: 24),
            Center(
              child: ElevatedButton.icon(
                icon:
                    isSaving
                        ? SizedBox(
                          width: 20 * scaleFactor,
                          height: 20 * scaleFactor,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Icon(Icons.save, color: Colors.white),
                label: Text(
                  isSaving ? 'Guardando...' : 'Guardar Evaluación',
                  style: TextStyle(fontSize: 14 * scaleFactor),
                ),
                onPressed: isSaving ? null : _guardarEvaluacion,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF003056),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                    horizontal: 30 * scaleFactor,
                    vertical: 15 * scaleFactor,
                  ),
                  side: const BorderSide(color: Color(0xFF003056), width: 2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
