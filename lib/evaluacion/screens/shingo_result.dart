// ignore_for_file: use_build_context_synchronously

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:applensys/evaluacion/models/empresa.dart';
import 'package:applensys/evaluacion/services/evaluacion_cache_service.dart';
import 'package:applensys/evaluacion/widgets/shingo_hojas.dart';
import 'package:applensys/evaluacion/services/shingoservice.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class ShingoCategorias extends StatefulWidget {
  final Empresa? empresa;
  final String? evaluacionId;

  const ShingoCategorias({super.key, this.empresa, this.evaluacionId});

  static Map<String, ShingoResultData> tablaShingo = {
    for (var cat in [
      'seguridad/medio/ambiente/moral',
      'satisfacción del cliente',
      'calidad',
      'costo/productividad',
      'entregas',
    ])
      cat: ShingoResultData(),
  };

  static Future<void> guardarTablaShingo() async {
    final Map<String, String> data = {};
    for (final e in tablaShingo.entries) {
      data[e.key] = jsonEncode(e.value.toJson());
    }
    await EvaluacionCacheService().guardarObservacionesshingo(data);
  }

  static Future<void> cargarTablaShingo() async {
    final data = await EvaluacionCacheService().cargarObservacionesshingo();
    final Map<String, ShingoResultData> loaded = {};
    for (final e in data.entries) {
      try {
        final decoded = jsonDecode(e.value) as Map<String, dynamic>;
        loaded[e.key] = ShingoResultData.fromJson(decoded);
      } catch (_) {}
    }
    for (var cat in [
      'seguridad/medio/ambiente/moral',
      'satisfacción del cliente',
      'calidad',
      'costo/productividad',
      'entregas',
    ]) {
      loaded.putIfAbsent(cat, () => ShingoResultData());
    }
    tablaShingo = loaded;
  }

  /// Sincroniza (reemplaza) la tabla Shingo en Supabase y sube imágenes al bucket `evidencias_shingo`.
  static Future<void> syncTablaShingoToSupabase({
    required String empresaId,
    required String evaluacionId,
  }) async {
    final client = Supabase.instance.client;
    final uuid = const Uuid();

    // Eliminar registros anteriores
    try {
      await client
          .from('shingo_hojas')
          .delete()
          .eq('empresa_id', empresaId)
          .eq('evaluacion_id', evaluacionId);
    } catch (e) {
      ('Error eliminando registros anteriores: $e');
    }

    final List<Map<String, dynamic>> inserts = [];

    // Función para subir imágenes de forma segura
    Future<String?> uploadImage(File? img, String prefix) async {
      if (img == null || !img.existsSync()) return null;
      try {
        final fileName = img.uri.pathSegments.last;
        final safe = Uri.encodeComponent(fileName);
        final path = '$empresaId/$evaluacionId/shingo/$prefix/${uuid.v4()}_$safe';
        
        await client.storage
            .from('evidencias_shingo')
            .uploadBinary(path, await img.readAsBytes(), fileOptions: const FileOptions(upsert: true));
        
        try {
          // Intentar obtener URL pública
          return client.storage.from('evidencias_shingo').getPublicUrl(path);
        } catch (_) {
          // Si no es pública, intentar URL firmada
          try {
            return await client.storage
                .from('evidencias_shingo')
                .createSignedUrl(path, 60 * 60 * 24); // 24 horas
          } catch (_) {
            return path; // Retornar al menos el path
          }
        }
      } catch (e) {
        ('Error subiendo imagen: $e');
        return null;
      }
    }

    // Serializar campos de forma segura
    String serializarCampos(Map<String, String> campos) {
      try {
        return jsonEncode(campos);
      } catch (_) {
        return jsonEncode({});
      }
    }

    // Guardar categorías principales y sus subcategorías
    for (final entry in tablaShingo.entries) {
      final categoria = entry.key;
      final hoja = entry.value;

      // Subir imagen de la categoría principal
      final mainImageUrl = await uploadImage(hoja.imagen, 'categoria');

      inserts.add({
        'id': const Uuid().v4(),
        'empresa_id': empresaId,
        'evaluacion_id': evaluacionId,
        'categoria': categoria,
        'subcategoria': null,
        'calificacion': hoja.calificacion,
        'campos': serializarCampos(hoja.campos),
        'imagen_url': mainImageUrl,
        'created_at': DateTime.now().toIso8601String(),
      });

      // Guardar subcategorías
      for (final sub in hoja.subcategorias.entries) {
        final subName = sub.key;
        final subData = sub.value;
        
        // Subir imagen de la subcategoría
        final subImageUrl = await uploadImage(subData.imagen, 'subcategoria');
        
        inserts.add({
          'id': const Uuid().v4(),
          'empresa_id': empresaId,
          'evaluacion_id': evaluacionId,
          'categoria': categoria,
          'subcategoria': subName,
          'calificacion': subData.calificacion,
          'campos': serializarCampos(subData.campos),
          'imagen_url': subImageUrl,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    }

    // Insertar todos los registros de una vez
    if (inserts.isNotEmpty) {
      try {
        await client.from('shingo_hojas').insert(inserts);
      } catch (e) {
        ('Error insertando datos en Shingo: $e');
        rethrow;
      }
    }
  }

  /// Carga las hojas Shingo desde Supabase y las guarda en cache local.
  static Future<void> loadTablaShingoFromSupabase({
    required String empresaId,
    required String evaluacionId,
  }) async {
    final client = Supabase.instance.client;
    try {
      final resp = await client
          .from('shingo_hojas')
          .select()
          .eq('empresa_id', empresaId)
          .eq('evaluacion_id', evaluacionId);
      final rows = List<Map<String, dynamic>>.from(resp as List);
      final Map<String, ShingoResultData> newTabla = {};
      
      for (final row in rows) {
        final categoria = (row['categoria'] ?? 'Sin categoría').toString();
        final subcategoria = row['subcategoria'] as String?;
        final calif = (row['calificacion'] ?? 0) as int;
        final camposRaw = row['campos'];
        
        // Parsear campos correctamente
        Map<String, String> campos = {
          'Cómo se calcula': '',
          'Cómo se mide': '',
          '¿Por qué es importante?': '',
          'Sistemas usados para mejorar': '',
          'Explicación de desviaciones': '',
          'Cambios en 3 años': '',
          'Cómo se definen metas': '',
        };

        if (camposRaw is Map) {
          camposRaw.forEach((k, v) {
            campos[k.toString()] = (v ?? '').toString();
          });
        } else if (camposRaw is String && camposRaw.isNotEmpty) {
          try {
            final decoded = jsonDecode(camposRaw) as Map<String, dynamic>;
            decoded.forEach((k, v) {
              campos[k.toString()] = (v ?? '').toString();
            });
          } catch (_) {}
        }

        // Obtener o crear la categoría padre
        final parent = newTabla.putIfAbsent(
          categoria,
          () => ShingoResultData(campos: {}, calificacion: 0),
        );

        if (subcategoria != null && subcategoria.isNotEmpty) {
          // Es una subcategoría: crearla dentro del padre
          parent.subcategorias[subcategoria] = ShingoResultData(
            campos: campos,
            calificacion: calif,
          );
        } else {
          // Es una categoría principal: actualizar el padre
          parent.campos = campos;
          parent.calificacion = calif;
        }
      }
      
      tablaShingo = newTabla;
      await guardarTablaShingo();
    } catch (e) {
      ('Error cargando Shingo desde Supabase: $e');
    }
  }

  @override
  State<ShingoCategorias> createState() => _ShingoCategoriasState();
}

class _ShingoCategoriasState extends State<ShingoCategorias> {
  List<String> categorias = [
    'seguridad/medio/ambiente/moral',
    'satisfacción del cliente',
    'calidad',
    'costo/productividad',
    'entregas',
  ];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await ShingoCategorias.cargarTablaShingo();
    if (mounted) setState(() {});
  }

  void abrirHoja(String categoria, {String? subcategoria}) async {
    final parent = ShingoCategorias.tablaShingo.putIfAbsent(
      categoria,
      () => ShingoResultData(),
    );
    final data =
        subcategoria == null
            ? parent
            : parent.subcategorias.putIfAbsent(
              subcategoria,
              () => ShingoResultData(),
            );

    // Abrimos la pantalla de edición y esperamos un posible resultado devuelto
    // (idealmente HojaShingoWidget hace `Navigator.pop(context, updatedData)` al guardar).
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => HojaShingoWidget(
              titulo: subcategoria ?? categoria,
              data: data,
              empresaNombre: widget.empresa?.nombre,
              evaluacionId: widget.evaluacionId,
            ),
      ),
    );

    // Si la pantalla de edición devolvió una instancia actualizada, úsala.
    if (result is ShingoResultData) {
      if (subcategoria == null) {
        ShingoCategorias.tablaShingo[categoria] = result;
      } else {
        ShingoCategorias.tablaShingo[categoria]!.subcategorias[subcategoria] =
            result;
      }
    }

    // Guardar en cache (persistencia local) y recargar desde cache para asegurar consistencia
    await ShingoCategorias.guardarTablaShingo();
    await ShingoCategorias.cargarTablaShingo();

    if (!mounted) return;
    setState(() {});
  }

  void agregarCategoria() async {
    final controller = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Nueva categoría'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Nombre de la categoría',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('Agregar'),
              ),
            ],
          ),
    );
    if (nombre != null && nombre.trim().isNotEmpty) {
      setState(() {
        categorias.add(nombre.trim());
        ShingoCategorias.tablaShingo.putIfAbsent(
          nombre.trim(),
          () => ShingoResultData(),
        );
      });
      await ShingoCategorias.guardarTablaShingo();
    }
  }

  void eliminarCategoria(String categoria) async {
    setState(() {
      categorias.remove(categoria);
      ShingoCategorias.tablaShingo.remove(categoria);
    });
    await ShingoCategorias.guardarTablaShingo();
  }

  void agregarSubcategoria(String categoria) async {
    final controller = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Nueva subcategoría'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Nombre de la subcategoría',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('Agregar'),
              ),
            ],
          ),
    );
    if (nombre != null && nombre.trim().isNotEmpty) {
      setState(() {
        final hoja = ShingoCategorias.tablaShingo.putIfAbsent(
          categoria,
          () => ShingoResultData(),
        );
        hoja.subcategorias.putIfAbsent(nombre.trim(), () => ShingoResultData());
      });
      await ShingoCategorias.guardarTablaShingo();
    }
  }

  void eliminarSubcategoria(String categoria, String subcategoria) async {
    setState(() {
      ShingoCategorias.tablaShingo[categoria]?.subcategorias.remove(
        subcategoria,
      );
    });
    await ShingoCategorias.guardarTablaShingo();
  }

  @override
  Widget build(BuildContext context) {
    final empresaNombre = widget.empresa?.nombre ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('EVALUACION DE RESULTADOS'),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Generar reporte Shingo',
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Generando reporte Shingo...')),
              );
              try {
                final eid = widget.empresa?.id;
                final evalId = widget.evaluacionId;
                if (eid == null || eid.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'No se puede generar el reporte: falta el ID de la empresa.',
                      ),
                    ),
                  );
                  return;
                }

                await ReporteShingoService.generarYRegistrarShingoPdf(
                  tabla: ShingoCategorias.tablaShingo,
                  evaluacionId: evalId ?? 'unknown',
                  empresaId: eid,
                  empresaNombre:
                      empresaNombre.isNotEmpty ? empresaNombre : 'Empresa',
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Reporte Shingo generado y subido correctamente.',
                    ),
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error al generar el reporte: $e')),
                );
              }
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: agregarCategoria,
        tooltip: 'Agregar categoría',
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                itemCount: categorias.length,
                itemBuilder: (context, index) {
                  final cat = categorias[index];
                  final hoja = ShingoCategorias.tablaShingo.putIfAbsent(
                    cat,
                    () => ShingoResultData(),
                  );
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  cat.toUpperCase(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              Text(
                                'Calificación: ${hoja.calificacion}',
                                style: const TextStyle(fontSize: 14),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.blue,
                                ),
                                tooltip: 'Editar categoría',
                                onPressed: () => abrirHoja(cat),
                              ),
                            ],
                          ),
                          if (hoja.subcategorias.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            ...hoja.subcategorias.entries.map(
                              (entry) => Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const SizedBox(width: 24),
                                      Expanded(
                                        child: Text(
                                          entry.key,
                                          style: const TextStyle(fontSize: 15),
                                        ),
                                      ),
                                      Text(
                                        'Calificación: ${entry.value.calificacion}',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.edit,
                                          color: Colors.blue,
                                        ),
                                        tooltip: 'Editar subcategoría',
                                        onPressed:
                                            () => abrirHoja(
                                              cat,
                                              subcategoria: entry.key,
                                            ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete,
                                          color: Colors.red,
                                        ),
                                        tooltip: 'Eliminar subcategoría',
                                        onPressed:
                                            () => eliminarSubcategoria(
                                              cat,
                                              entry.key,
                                            ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                ],
                              ),
                            ),
                          ],
                          Row(
                            children: [
                              const Icon(Icons.add, color: Colors.green),
                              TextButton(
                                onPressed: () => agregarSubcategoria(cat),
                                child: const Text('Agregar subcategoría'),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                ),
                                tooltip: 'Eliminar categoría',
                                onPressed: () => eliminarCategoria(cat),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ShingoResultData {
  Map<String, String> campos;
  File? imagen;
  int calificacion;
  Map<String, ShingoResultData> subcategorias;

  ShingoResultData({
    Map<String, String>? campos,
    this.imagen,
    int? calificacion,
    Map<String, ShingoResultData>? subcategorias,
  }) : campos =
           campos ??
           {
             'Cómo se calcula': '',
             'Cómo se mide': '',
             '¿Por qué es importante?': '',
             'Sistemas usados para mejorar': '',
             'Explicación de desviaciones': '',
             'Cambios en 3 años': '',
             'Cómo se definen metas': '',
           },
       calificacion = calificacion ?? 0,
       subcategorias = subcategorias ?? {};

  Map<String, dynamic> toJson() => {
    'campos': campos,
    'imagen': imagen?.path,
    'calificacion': calificacion,
    'subcategorias': subcategorias.map((k, v) => MapEntry(k, v.toJson())),
  };

  factory ShingoResultData.fromJson(Map<String, dynamic> json) =>
      ShingoResultData(
        campos: Map<String, String>.from(json['campos'] ?? {}),
        imagen: json['imagen'] != null ? File(json['imagen']) : null,
        calificacion: json['calificacion'] ?? 0,
        subcategorias:
            (json['subcategorias'] != null)
                ? Map<String, ShingoResultData>.from(
                  (json['subcategorias'] as Map).map(
                    (k, v) => MapEntry(
                      k,
                      ShingoResultData.fromJson(
                        Map<String, dynamic>.from(v as Map),
                      ),
                    ),
                  ),
                )
                : {},
      );
}
