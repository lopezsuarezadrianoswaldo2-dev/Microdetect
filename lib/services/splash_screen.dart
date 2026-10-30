import 'package:bioconteo_colonias_bacterinas/app_colors.dart';
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
      backgroundColor: AppColors.fondo,
      body: Column(
        children: [
          const Spacer(flex: 3),

          // 🧫 LOGO MICRODETECT
          Image.asset(
            'assets/images/micro.png',
            height: 260,
            // Funde el fondo del logo con el fondo de la app (quítalo si tu logo ya es PNG transparente)
            color: AppColors.fondo,
            colorBlendMode: BlendMode.darken,
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
                          backgroundColor: AppColors.primario,
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
          ),

          const SizedBox(height: 8),
          const Text(
            'Iniciando...',
            style: TextStyle(color: AppColors.primario, fontSize: 13),
          ),

          const Spacer(flex: 1),
        ],
      ),
    );
  }
}