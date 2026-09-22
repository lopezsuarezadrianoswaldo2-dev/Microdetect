import 'dart:async';
import 'package:flutter/material.dart';
import 'auth_wrapper.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {

  late AnimationController _controller;

  @override
  void initState() {
    super.initState();

    // 🎬 Animación continua (no se traba)
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    // ⏱️ 3 segundos exactos
    Timer(const Duration(seconds: 3), () {
      _controller.stop();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AuthWrapper()),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      body: Column(
        children: [
          const Spacer(flex: 3),

          // 🧫 LOGO
          Image.asset(
            'assets/images/logo.png',
            height: 170,
          ),

          const SizedBox(height: 25),

          // 🧪 TEXTO
          const Text(
            'BioConteo de Colonias\nBacterianas',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 2,
            ),
          ),

          const Spacer(flex: 2),

          // 🔵 LOADER MÁS ABAJO
          SizedBox(
            height: 40,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(3, (index) {
                    final double delay = index * 0.3;
                    final double value =
                        (_controller.value + delay) % 1.0;

                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      child: Transform.scale(
                        scale: 0.6 + (value < 0.5 ? value : 1 - value),
                        child: const CircleAvatar(
                          radius: 6,
                          backgroundColor: Colors.blueAccent,
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),

          const Spacer(flex: 1),
        ],
      ),
    );
  }
}
