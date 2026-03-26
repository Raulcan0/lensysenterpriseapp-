import 'dart:async';
import 'package:applensys/custom/appcolors.dart';
import 'package:flutter/material.dart';
import '../screens/shingo_result.dart';

class TablaResultadosShingo extends StatefulWidget {
  final Map<String, ShingoResultData> resultados;
  final String? empresaNombre;
  final String? evaluacionId;

  const TablaResultadosShingo({
    super.key,
    required this.resultados,
    this.empresaNombre,
    this.evaluacionId,
  });

  @override
  State<TablaResultadosShingo> createState() => _TablaResultadosShingoState();
}

class _TablaResultadosShingoState extends State<TablaResultadosShingo> {
  @override
  Widget build(BuildContext context) {
    final resumen = ShingoResumenService.generarResumen(widget.resultados);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(Colors.grey[200]),
        columns: const [
          DataColumn(label: Text('Categoría')),
          DataColumn(label: Text('Pts obtenidos')),
          DataColumn(label: Text('% obtenido')),
        ],
        rows: resumen.map((r) {
          return DataRow(
            color: r.esTotal ? WidgetStateProperty.all(AppColors.primary) : null,
            cells: [
              DataCell(
                Text(
                  r.categoria,
                  style: r.esTotal ? const TextStyle(color: Colors.white) : null,
                ),
              ),
              DataCell(
                Container(
                  width: 90,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        r.puntos.toStringAsFixed(0),
                        style: r.esTotal ? const TextStyle(color: Colors.white) : null,
                      ),
                      if (!r.esTotal)
                        IconButton(
                          icon: const Icon(Icons.edit, size: 18),
                          tooltip: 'Editar calificación',
                          onPressed: () async {
                            await _editarCalificacion(context, r.categoria);
                          },
                        ),
                    ],
                  ),
                ),
              ),
              DataCell(
                Text(
                  '${r.porcentaje.toStringAsFixed(1)}%',
                  style: r.esTotal ? const TextStyle(color: Colors.white) : null,
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Future<void> _editarCalificacion(BuildContext context, String categoria) async {
    String cat;
    String? subcat;
    if (categoria.contains('>')) {
      final partes = categoria.split('>');
      cat = partes[0].trim();
      subcat = partes.length > 1 ? partes[1].trim() : null;
    } else {
      cat = categoria;
      subcat = null;
    }

    final tabla = widget.resultados;
    final data = subcat == null ? tabla[cat]! : tabla[cat]!.subcategorias[subcat]!;
    int nuevaCalif = data.calificacion;

    final result = await showDialog<int>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: const Text('Editar calificación'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Selecciona la calificación (0–5)'),
              Slider(
                value: nuevaCalif.toDouble(),
                min: 0,
                max: 5,
                divisions: 5,
                label: nuevaCalif.toString(),
                onChanged: (v) {
                  setStateDialog(() {
                    nuevaCalif = v.toInt();
                  });
                },
              ),
              Text('Calificación actual: $nuevaCalif / 5'),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(context, nuevaCalif), child: const Text('Guardar')),
          ],
        ),
      ),
    );

    if (result != null) {
      setState(() {
        data.calificacion = result;
      });
      
      // Guardar a caché local
      await ShingoCategorias.guardarTablaShingo();
      
      // Sincronizar a Supabase si se tiene contexto
      if (widget.empresaNombre != null && widget.evaluacionId != null) {
        try {
          await ShingoCategorias.syncTablaShingoToSupabase(
            empresaId: widget.empresaNombre!,
            evaluacionId: widget.evaluacionId!,
          );
        } catch (e) {
          ('Error sincronizando a Supabase: $e');
        }
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Calificación actualizada a $result')),
        );
      }
    }
  }
}

class ShingoResumenService {
  static List<ResumenCategoria> generarResumen(Map<String, ShingoResultData> hojas) {
    final List<ResumenCategoria> resumen = [];
    double totalPts = 0;
    const puntosPorCategoria = 40.0; // Cada categoría tiene máximo 40 puntos

    if (hojas.isEmpty) {
      resumen.add(ResumenCategoria(categoria: 'TOTAL', puntos: 0, porcentaje: 0, esTotal: true));
      return resumen;
    }

    hojas.forEach((nombre, cat) {
      if (cat.subcategorias.isEmpty) {
        // Sin subcategorías: la categoría tiene 40 puntos máximo
        final puntos = cat.calificacion.toDouble() * puntosPorCategoria / 5;
        totalPts += puntos;
        resumen.add(ResumenCategoria(
          categoria: nombre,
          puntos: puntos,
          porcentaje: (puntos / puntosPorCategoria * 100).toDouble(),
          esTotal: false,
        ));
      } else {
        // Con subcategorías: dividir 40 puntos entre el número de subcategorías
        final numSubcategorias = cat.subcategorias.length;
        final puntosPorSubcategoria = puntosPorCategoria / numSubcategorias;
        
        cat.subcategorias.forEach((subnombre, subcat) {
          final puntos = subcat.calificacion.toDouble() * puntosPorSubcategoria / 5;
          totalPts += puntos;
          resumen.add(ResumenCategoria(
            categoria: '$nombre > $subnombre',
            puntos: puntos,
            porcentaje: (puntos / puntosPorSubcategoria * 100).toDouble(),
            esTotal: false,
          ));
        });
      }
    });

    resumen.add(ResumenCategoria(
      categoria: 'TOTAL',
      puntos: totalPts,
      porcentaje: totalPts / 200 * 100, // Máximo total es 200 (5 categorías × 40)
      esTotal: true,
    ));

    return resumen;
  }
}

class ResumenCategoria {
  final String categoria;
  final double puntos;
  final double porcentaje;
  final bool esTotal;

  ResumenCategoria({
    required this.categoria,
    required this.puntos,
    required this.porcentaje,
    this.esTotal = false,
  });
}
