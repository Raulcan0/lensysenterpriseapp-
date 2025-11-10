import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Tus archivos importados
import 'package:applensys/auth/loader.dart';
import 'package:applensys/auth/login.dart';
import 'package:applensys/auth/recovery.dart';
import 'package:applensys/auth/register.dart';
import 'package:applensys/evaluacion/providers/text_size_provider.dart';
import 'package:applensys/evaluacion/providers/theme_provider.dart';
import 'package:applensys/evaluacion/services/evaluacion_cache_service.dart';
import 'package:applensys/evaluacion/utils/release.dart';
import 'package:applensys/evaluacion/widgets/actualizaciones.dart';
import 'package:applensys/home.dart';
import 'package:applensys/custom/configurations.dart';
import 'package:applensys/custom/service_locator.dart';

const String kAppId = 'lensys';
const int kCurrentBuild = 45;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initializeServices();
  runApp(const ProviderScope(child: MyApp()));
}

Future<void> _initializeServices() async {
  await Supabase.initialize(
    url: Configurations.mSupabaseUrl,
    anonKey: Configurations.mSupabaseKey,
  );
  setupLocator();
  await locator<EvaluacionCacheService>().init();
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  bool _updateChecked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (!_updateChecked) {
      _updateChecked = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final updateState = await ref.read(
          updateCheckerProvider((
            appId: kAppId,
            currentBuild: kCurrentBuild,
          )).future,
        );
        if (mounted && updateState.hasUpdate && updateState.info != null) {
          showDialog(
            context: context,
            barrierDismissible: !updateState.info!.obligatoria,
            builder: (_) => ActualizacionDialog(info: updateState.info!),
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final textSize = ref.watch(textSizeProvider);
    final scaleFactor = textSize / 14.0;

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LensysApp',
      themeMode: themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFF003056),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF003056),
          foregroundColor: Colors.white,
        ),
        textTheme: GoogleFonts.robotoTextTheme(ThemeData.light().textTheme),
      ),
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        textTheme: GoogleFonts.robotoTextTheme(ThemeData.dark().textTheme),
      ),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scaleFactor)),
          child: child!,
        );
      },
      routes: {
        '/loader': (_) => const LoaderScreen(),
        '/loaderScreen': (_) => const LoaderScreen(),
        '/home': (_) => const HomeScreen(),
        '/login': (_) => const Login(),
        '/register': (_) => const RegisterScreen(),
        '/recovery': (_) => const Recovery(),
        '/empresas': (_) => const HomeScreen(),
      },
      home: const HomeScreen(),
    );
  }
}
