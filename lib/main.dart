import 'package:bioconteo_colonias_bacterinas/app_colors.dart';
import 'package:bioconteo_colonias_bacterinas/services/splash_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyB8tu3-CpuV4c2LfR2GqcjH9agws00xOYw",
        authDomain: "bioconteo-pruebas.firebaseapp.com",
        projectId: "bioconteo-pruebas",
        storageBucket: "bioconteo-pruebas.firebasestorage.app",
        messagingSenderId: "341450239456",
        appId: "1:341450239456:android:04ef76679b24b3339c4f85",
      ),
    );
    debugPrint("Firebase inicializado correctamente");
  } catch (e) {
    debugPrint("Error al inicializar Firebase: $e");
  }

  // Crashlytics y Performance solo funcionan en Android/iOS (no en web)
  if (!kIsWeb) {
    // Activar la recolección también en modo debug (para poder probar)
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
    await FirebasePerformance.instance.setPerformanceCollectionEnabled(true);

    // Errores de Flutter -> Crashlytics
    FlutterError.onError =
        FirebaseCrashlytics.instance.recordFlutterFatalError;

    // Errores asíncronos fuera de Flutter -> Crashlytics
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.tema,
      home: const SplashScreen(),
    );
  }
}