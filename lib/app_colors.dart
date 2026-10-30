import 'package:flutter/material.dart';

/// Paleta central de la app (prototipo MicroDetect).
/// Si quieres cambiar un color en TODA la app, solo cámbialo aquí.
class AppColors {
  AppColors._();

  static const Color fondo = Color(0xFFEAF4FF); // fondo de pantallas
  static const Color primario = Color(0xFF4A90E2); // color principal
  static const Color hover = Color(0xFF357ABD); // hover / botón presionado
  static const Color tarjeta = Colors.white; // tarjetas, cuadros y diálogos
  static const Color texto = Color(0xFF0D1B2A); // texto principal (azul oscuro)
  static const Color textoSecundario = Color(0xFF415A77); // texto secundario
  static const Color textoTenue = Color(0xFF8DA2B8); // hints / iconos apagados
}

/// Tema global: botones, appbar, diálogos, etc.
class AppTheme {
  AppTheme._();

  static ThemeData get tema {
    return ThemeData(
      useMaterial3: false,
      scaffoldBackgroundColor: AppColors.fondo,
      primaryColor: AppColors.primario,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primario,
        primary: AppColors.primario,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.texto,
        iconTheme: IconThemeData(color: AppColors.texto),
        titleTextStyle: TextStyle(
          color: AppColors.texto,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      dialogBackgroundColor: AppColors.tarjeta,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: MaterialStateProperty.all(Colors.white),
          backgroundColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.disabled)) {
              return AppColors.primario.withOpacity(0.4);
            }
            if (states.contains(MaterialState.hovered) ||
                states.contains(MaterialState.pressed)) {
              return AppColors.hover;
            }
            return AppColors.primario;
          }),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.primario),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.primario),
    );
  }
}