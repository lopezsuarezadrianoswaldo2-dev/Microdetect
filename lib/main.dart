import 'package:bioconteo_colonias_bacterinas/services/splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

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

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,

      // 🔥 PRIMERA PANTALLA
      home: SplashScreen(),
    );
  }
}
