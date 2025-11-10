class PrincipioJson {
  final String nombre;
  final String benchmarkComportamiento;
  final String benchmarkPorNivel;
  final String nivel;
  final String preguntas;
  final Map<String, String> calificaciones;
  final List<String> comportamientos;

  PrincipioJson({
    required this.nombre,
    required this.benchmarkComportamiento,
    required this.benchmarkPorNivel,
    required this.nivel,
    required this.preguntas,
    required this.calificaciones,
    required this.comportamientos,
  });

  factory PrincipioJson.fromJson(Map<String, dynamic> json) {
    List<String> comportamientosList = [];
    if (json['comportamientos'] is List) {
      comportamientosList = List<String>.from(
        json['comportamientos'].whereType<String>(),
      );
    } else if (json['comportamientos'] is String) {
      comportamientosList = [json['comportamientos'] as String];
    }
    return PrincipioJson(
      nombre: json['PRINCIPIOS'] ?? '',
      benchmarkComportamiento: json['BENCHMARK DE COMPORTAMIENTOS'] ?? '',
      benchmarkPorNivel: json['BENCHMARK POR NIVEL'] ?? '',
      nivel: (json['NIVEL'] ?? '').toString().toUpperCase(),
      preguntas: json['GUÍA DE PREGUNTAS'] ?? '',
      calificaciones: {
        'C1': json['C1'] ?? '',
        'C2': json['C2'] ?? '',
        'C3': json['C3'] ?? '',
        'C4': json['C4'] ?? '',
        'C5': json['C5'] ?? '',
      },
      comportamientos: comportamientosList,
    );
  }
}
