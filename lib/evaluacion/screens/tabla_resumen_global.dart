import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:applensys/evaluacion/screens/shingo_result.dart';
import 'package:flutter/rendering.dart';
import 'package:applensys/evaluacion/widgets/tabla_puntuacion_global.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../widgets/tabla_shingo.dart';
import '../widgets/termometro.dart';
import 'package:applensys/evaluacion/screens/tablas_screen.dart';

class TablaResumenGlobal extends ConsumerStatefulWidget {
  final Map<String, Map<String, double>> promediosPorDimension;

  const TablaResumenGlobal({
    super.key,
    required this.promediosPorDimension,
  });

  @override
  ConsumerState<TablaResumenGlobal> createState() => _TablaResumenGlobalState();
}

class _TablaResumenGlobalState extends ConsumerState<TablaResumenGlobal> {
  // Keys para capturar cada widget
  final GlobalKey _keyPuntuacion = GlobalKey();
  final GlobalKey _keyShingo = GlobalKey();
  final GlobalKey _keyTermometro = GlobalKey();
  bool _captured = false;

  @override
  void initState() {
    super.initState();
    // Capturar automáticamente una vez que el primer frame esté listo
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Pequeña espera para asegurar que todo esté pintado
      await Future.delayed(const Duration(milliseconds: 200));
      if (mounted && !_captured) {
        _captured = true;
        await _captureAll();
      }
    });
  }

  Future<Uint8List?> _capturePng(GlobalKey boundaryKey, {double pixelRatio = 1.0}) async {
    try {
      final context = boundaryKey.currentContext;
      if (context == null) return null;
      final boundary = context.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;

      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      // Ignorar o loguear
      return null;
    }
  }

  Future<String?> _savePng(Uint8List bytes, String filename) async {
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (e) {
      return null;
    }
  }

  Future<void> _captureAndSave(GlobalKey key, String name, {double pixelRatio = 1.0}) async {
    final bytes = await _capturePng(key, pixelRatio: pixelRatio);
    if (bytes == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al capturar widget')));
      return;
    }
    final path = await _savePng(bytes, '$name.png');
    if (mounted) {
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Guardado: $path')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al guardar imagen')));
      }
    }
  }

  Future<void> _captureAll() async {
    await _captureAndSave(_keyPuntuacion, 'puntuacion', pixelRatio: 2.0);
    await _captureAndSave(_keyShingo, 'shingo', pixelRatio: 2.0);
    await _captureAndSave(_keyTermometro, 'termometro', pixelRatio: 2.0);
  }

  @override
  Widget build(BuildContext context) {
    // Calcular puntos globales (máx 800)
    final puntosGlobales = AuxTablaService.obtenerTotalPuntosGlobal();

    // Obtener resumen Shingo actual
    final resumenShingo = ShingoResumenService.generarResumen(ShingoCategorias.tablaShingo);
    final puntosShingo = resumenShingo.isNotEmpty ? resumenShingo.last.puntos : 0.0;

    // Suma total global (máx 1000)
    final puntosTotales = puntosGlobales + puntosShingo;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Score Global',
          style: TextStyle(color: Colors.white),
          textAlign: TextAlign.center,
        ),
        centerTitle: true,
        backgroundColor: Theme.of(context).primaryColor,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Las capturas ahora se realizan automáticamente al cargar la pantalla.

              // ======================================================
              // TABLA DE PUNTUACIÓN GLOBAL POR DIMENSIONES
              // ======================================================
              RepaintBoundary(
                key: _keyPuntuacion,
                child: TablaPuntuacionGlobal(
                  promediosPorDimension: widget.promediosPorDimension,
                  puntuacionGlobal: const {
                    'Dimensión 1': 250.0,
                    'Dimensión 2': 350.0,
                    'Dimensión 3': 200.0,
                  },
                ),
              ),
              const SizedBox(height: 32),

              // ======================================================
              // TABLA DE RESULTADOS SHINGO (NORMAL)
              // ======================================================
              RepaintBoundary(
                key: _keyShingo,
                 child: TablaResultadosShingo(
                   resultados: ShingoCategorias.tablaShingo,
                 ),
              ),
              const SizedBox(height: 40),

              // ======================================================
              // TERMÓMETRO GLOBAL CENTRADO Y PROPORCIONAL
              // ======================================================
              Center(
                child: RepaintBoundary(
                  key: _keyTermometro,
                  child: TermometroGlobal(
                    valorObtenido: puntosTotales,
                  ),
                ),
              ),

              const SizedBox(height: 40),

              // Capturas automáticas realizadas al iniciar la pantalla.
            ],
          ),
        ),
      ),
    );
  }
}
