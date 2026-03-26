// ignore_for_file: use_build_context_synchronously

import 'package:applensys/auth/loader.dart';
import 'package:applensys/evaluacion/models/empresa.dart';
import 'package:applensys/evaluacion/screens/dashboard_screen.dart';
import 'package:applensys/evaluacion/screens/detalles_evaluacion.dart';
import 'package:applensys/evaluacion/screens/empresas_screen.dart';
import 'package:applensys/evaluacion/screens/historial_screen.dart';
import 'package:applensys/evaluacion/screens/perfil_screen.dart';
import 'package:applensys/evaluacion/screens/tablas_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:applensys/evaluacion/providers/text_size_provider.dart';

class EvaluacionContext {
  static Empresa? empresaActual;
  static String asociadoId = '';
  static String dimension = '';
}

class DrawerLensys extends ConsumerWidget {
  const DrawerLensys({super.key});

  Future<Map<String, dynamic>> _getUserData() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return {'nombre': 'Usuario', 'foto_url': null};

    final data = await Supabase.instance.client
        .from('usuarios')
        .select('nombre, foto_url')
        .eq('id', user.id)
        .maybeSingle();

    return {
      'nombre': data?['nombre'] ?? 'Usuario',
      'foto_url': data?['foto_url'],
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = Supabase.instance.client.auth.currentUser;
    final userEmail = user?.email ?? 'usuario@ejemplo.com';
    final textSize = ref.watch(textSizeProvider);
    final scaleFactor = textSize / 14.0;
    final empresa = EvaluacionContext.empresaActual;

    return Drawer(
      child: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            FutureBuilder<Map<String, dynamic>>(
              future: _getUserData(),
              builder: (context, snapshot) {
                final nombre = snapshot.data?['nombre'] ?? 'Usuario';
                final fotoUrl = snapshot.data?['foto_url'];

                return UserAccountsDrawerHeader(
                  decoration: const BoxDecoration(color: Color(0xFF003056)),
                  accountName: Text(nombre, style: TextStyle(fontSize: 18 * scaleFactor, color: Colors.white)),
                  accountEmail: Text(userEmail, style: TextStyle(fontSize: 14 * scaleFactor, color: Colors.white.withOpacity(0.8))),
                  currentAccountPicture: (fotoUrl != null && fotoUrl.isNotEmpty)
                      ? CircleAvatar(backgroundImage: NetworkImage(fotoUrl), radius: 30 * scaleFactor)
                      : CircleAvatar(
                          backgroundColor: Colors.white,
                          radius: 30 * scaleFactor,
                          child: Icon(Icons.person, size: 40 * scaleFactor, color: Color(0xFF003056)),
                        ),
                );
              },
            ),

            _buildListTile(
              context,
              icon: Icons.home,
              label: "Inicio",
              onTap: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const EmpresasScreen()),
                  (route) => false,
                );
              },
              scaleFactor: scaleFactor,
            ),

            _buildListTile(
              context,
              icon: Icons.table_chart,
              label: "Resultados",
              onTap: () {
                if (empresa == null || empresa.id.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No hay empresa activa.")));
                  return;
                }

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TablasDimensionScreen(
                      empresa: empresa,
                      evaluacionId: empresa.id,
                      empresaId: empresa.id,
                      dimension: EvaluacionContext.dimension,
                      asociadoId: EvaluacionContext.asociadoId,
                    ),
                  ),
                );
              },
              scaleFactor: scaleFactor,
            ),

            _buildListTile(
              context,
              icon: Icons.insert_chart,
              label: "Detalle Evaluación",
              onTap: () {
                if (empresa == null || empresa.id.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No hay empresa activa.")));
                  return;
                }

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DetallesEvaluacionScreen(
                      empresa: empresa,
                      evaluacionId: empresa.id,
                      dimension: EvaluacionContext.dimension,
                      dimensionesPromedios: const {},
                      promedios: const {},
                    ),
                  ),
                );
              },
              scaleFactor: scaleFactor,
            ),

            _buildListTile(
              context,
              icon: Icons.dashboard,
              label: "Dashboard",
              onTap: () {
                if (empresa == null || empresa.id.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No hay empresa activa.")));
                  return;
                }

                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DashboardScreen(
                      empresa: empresa,
                      evaluacionId: empresa.id,
                    ),
                  ),
                );
              },
              scaleFactor: scaleFactor,
            ),

            _buildListTile(
              context,
              icon: Icons.history,
              label: "Historial",
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const HistorialScreen()));
              },
              scaleFactor: scaleFactor,
            ),

            _buildListTile(
              context,
              icon: Icons.manage_accounts,
              label: "Ajustes y Perfil",
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const PerfilScreen()));
              },
              scaleFactor: scaleFactor,
            ),

            const Divider(),

            _buildListTile(
              context,
              icon: Icons.chat,
              label: "Chat",
              onTap: () {
                Navigator.of(context).pop();
                Scaffold.of(context).openDrawer(); // Chat Drawer
              },
              scaleFactor: scaleFactor,
            ),

            const Divider(),

            ListTile(
              leading: Icon(Icons.text_fields, size: 24 * scaleFactor),
              title: Text('Letra', style: TextStyle(fontSize: 14 * scaleFactor)),
              trailing: DropdownButton<double>(
                value: ref.watch(textSizeProvider),
                iconSize: 24 * scaleFactor,
                items: [
                  DropdownMenuItem(value: 12.0, child: Text('CH', style: TextStyle(fontSize: 12 * scaleFactor))),
                  DropdownMenuItem(value: 14.0, child: Text('M', style: TextStyle(fontSize: 14 * scaleFactor))),
                  DropdownMenuItem(value: 16.0, child: Text('G', style: TextStyle(fontSize: 16 * scaleFactor))),
                ],
                onChanged: (size) {
                  if (size != null) {
                    ref.read(textSizeProvider.notifier).state = size;
                  }
                },
              ),
            ),

            const Divider(),

            _buildListTile(
              context,
              icon: Icons.logout,
              label: "Cerrar sesión",
              onTap: () async {
                await Supabase.instance.client.auth.signOut();
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoaderScreen()),
                  (route) => false,
                );
              },
              scaleFactor: scaleFactor,
              iconColor: Colors.red,
            ),
          ],
        ),
      ),
    );
  }

  ListTile _buildListTile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required double scaleFactor,
    Color? iconColor,
  }) {
    return ListTile(
      leading: Icon(icon, size: 24 * scaleFactor, color: iconColor ?? Theme.of(context).iconTheme.color),
      title: Text(label, style: TextStyle(fontSize: 14 * scaleFactor, color: Theme.of(context).textTheme.bodyLarge?.color)),
      onTap: onTap,
    );
  }
}
