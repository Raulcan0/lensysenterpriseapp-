import 'dart:convert';

class Calificacion {
  final String id;
  final String idAsociado;
  final String idEmpresa;
  final int idDimension;
  final String principioNombre;
  final String comportamiento;
  final int puntaje;
  final DateTime fechaEvaluacion;
  final String? observaciones;
  final List<String> sistemas;
  final String? evidenciaUrl; // Agregado campo de URL de evidencia
  final String cargo;

  Calificacion({
    required this.id,
    required this.idAsociado,
    required this.idEmpresa,
    required this.idDimension,
    required this.comportamiento,
    required this.principioNombre,
    required this.puntaje,
    required this.fechaEvaluacion,
    this.observaciones,
    required this.sistemas,
    this.evidenciaUrl,
    required this.cargo,
    required String principio,
  });

  factory Calificacion.fromMap(Map<String, dynamic> map) {
    List<String> sistemasDesdeMapa = [];
    if (map['sistemas'] is List) {
      sistemasDesdeMapa = List<String>.from(map['sistemas']);
    } else if (map['sistemas'] is String &&
        (map['sistemas'] as String).isNotEmpty) {
      try {
        sistemasDesdeMapa = List<String>.from(jsonDecode(map['sistemas']));
      } catch (_) {
        sistemasDesdeMapa = [];
      }
    }

    return Calificacion(
      id: map['id']?.toString() ?? '',
      idAsociado: map['id_asociado']?.toString() ?? '',
      idEmpresa: map['id_empresa']?.toString() ?? '',
      idDimension: int.tryParse(map['id_dimension']?.toString() ?? '') ?? 0,
      comportamiento: map['comportamiento']?.toString() ?? '',
      principioNombre: map['principio']?.toString() ?? '',
      puntaje:
          map['puntaje'] is int
              ? map['puntaje'] as int
              : int.tryParse(map['puntaje']?.toString() ?? '') ?? 0,
      fechaEvaluacion: () {
        try {
          final s = map['fecha_evaluacion']?.toString();
          return s != null && s.isNotEmpty ? DateTime.parse(s) : DateTime.now();
        } catch (_) {
          return DateTime.now();
        }
      }(),
      observaciones: map['observaciones']?.toString(),
      sistemas: sistemasDesdeMapa,
      evidenciaUrl: map['evidencia_url']?.toString(),
      // Preserve casing provided by the client/DB so we can store normalized Title Case
      cargo: (map['cargo'] ?? '').toString(),
      // legacy constructor param kept for compatibility
      principio: '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'id_asociado': idAsociado,
      'id_empresa': idEmpresa,
      'id_dimension': idDimension,
      'comportamiento': comportamiento,
      'principio': principioNombre,
      'puntaje': puntaje,
      'fecha_evaluacion': fechaEvaluacion.toIso8601String(),
      'observaciones': observaciones,
      'sistemas': sistemas,
      'evidencia_url': evidenciaUrl,
      // store cargo as provided (avoid forcing upper-case)
      'cargo': cargo,
    };
  }
}
