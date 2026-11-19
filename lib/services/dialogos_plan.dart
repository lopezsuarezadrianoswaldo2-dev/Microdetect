import 'package:bioconteo_colonias_bacterinas/app_colors.dart';
import 'package:flutter/material.dart';

import 'plan_service.dart';

/// Avisa que se alcanzó el límite de imágenes del paquete.
/// Devuelve true si el usuario pulsó "Ver paquetes".
Future<bool> mostrarDialogoLimiteImagenes(
  BuildContext context,
  EstadoPlan estado,
) async {
  final bool? verPaquetes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.tarjeta,
      title: Row(
        children: const [
          Icon(Icons.photo_library, color: Colors.amber),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Límite de imágenes',
              style: TextStyle(color: AppColors.texto),
            ),
          ),
        ],
      ),
      content: Text(
        'Ya usaste las ${estado.limiteImagenes} imágenes de tu paquete '
        '${estado.planEfectivo.nombre}. Cambia de paquete para seguir '
        'analizando muestras.',
        style: const TextStyle(color: AppColors.textoSecundario),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text(
            'Cerrar',
            style: TextStyle(color: AppColors.textoSecundario),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text(
            'Ver paquetes',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    ),
  );

  return verPaquetes == true;
}

/// Bienvenida: la prueba Premium se activa sola al entrar por primera vez.
/// Solo informa; no pide aceptar nada.
Future<void> mostrarDialogoBienvenidaPrueba(BuildContext context) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.tarjeta,
      title: Row(
        children: const [
          Icon(Icons.workspace_premium, color: Colors.amber),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '¡Bienvenido a MicroDetect!',
              style: TextStyle(color: AppColors.texto),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Te regalamos $kDiasPruebaPremium días del paquete Premium '
            'gratis, ya activados:',
            style: const TextStyle(color: AppColors.textoSecundario),
          ),
          const SizedBox(height: 12),
          _beneficio('Imágenes ilimitadas'),
          _beneficio('Historial de reportes'),
          _beneficio('Gráficas y estadísticas'),
          _beneficio('Exportar PDF e imagen sin marca de agua'),
          const SizedBox(height: 12),
          const Text(
            'Al terminar la prueba podrás contratar el paquete que '
            'prefieras o seguir con el Básico (gratis).',
            style: TextStyle(color: AppColors.textoTenue, fontSize: 12),
          ),
        ],
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text(
            '¡Empezar!',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    ),
  );
}

/// Avisa que la prueba terminó e invita a contratar un paquete.
/// Devuelve true si el usuario pulsó "Ver paquetes".
Future<bool> mostrarDialogoFinPrueba(BuildContext context) async {
  final bool? verPaquetes = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.tarjeta,
      title: Row(
        children: const [
          Icon(Icons.timer_off, color: Colors.amber),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tu prueba terminó',
              style: TextStyle(color: AppColors.texto),
            ),
          ),
        ],
      ),
      content: const Text(
        'Se acabaron tus días de Premium gratis. Para conservar el '
        'historial, las gráficas y las exportaciones sin marca de agua, '
        'contrata un paquete. Si no, tu cuenta pasa al paquete Básico '
        '(gratis, hasta 3 imágenes).',
        style: TextStyle(color: AppColors.textoSecundario),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text(
            'Seguir con Básico',
            style: TextStyle(color: AppColors.textoSecundario),
          ),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text(
            'Ver paquetes',
            style: TextStyle(color: Colors.white),
          ),
        ),
      ],
    ),
  );

  return verPaquetes == true;
}

Widget _beneficio(String texto) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texto,
            style: const TextStyle(color: AppColors.texto, fontSize: 14),
          ),
        ),
      ],
    ),
  );
}