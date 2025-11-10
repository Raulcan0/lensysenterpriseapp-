import 'package:applensys/evaluacion/services/release_service.dart';
import 'package:flutter/material.dart';

class ActualizacionDialog extends StatelessWidget {
  final ReleaseInfo info;
  const ActualizacionDialog({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Actualización disponible'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Versión ${info.version} (build ${info.build})'),
          const SizedBox(height: 8),
          if ((info.notas ?? '').isNotEmpty)
            Text(info.notas!, style: const TextStyle(fontSize: 13)),
          if ((info.notas ?? '').isEmpty)
            const Text('Hay una nueva actualización lista para descargar.'),
        ],
      ),
      actions: [
        if (!info.obligatoria)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Luego'),
          ),
        TextButton(
          onPressed: () async {
            // Cerramos el diálogo principal y mostramos un diálogo de progreso
            Navigator.of(context).pop();
            final svc = ReleasesService();
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => const AlertDialog(
                content: SizedBox(
                  height: 80,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
            );
            final success = await svc.downloadAndLaunchRelease(info);
            Navigator.of(context).pop(); // cerrar progreso
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(success ? 'Descarga iniciada. Ejecutando instalador.' : 'Error al descargar o ejecutar el instalador.')),
            );
          },
          child: const Text('Actualizar'),
        ),
      ],
    );
  }
}
