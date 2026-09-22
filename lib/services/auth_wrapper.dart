import 'package:bioconteo_colonias_bacterinas/home_panel.dart';
import 'package:bioconteo_colonias_bacterinas/login.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),

      builder: (context, snapshot) {

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // ✅ Usuario logueado
        if (snapshot.hasData) {
          return HomePanel();
        }

        // ❌ No logueado
        return Login();
      },
    );
  }
}
