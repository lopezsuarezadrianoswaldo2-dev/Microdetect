import 'package:bioconteo_colonias_bacterinas/app_colors.dart';
import 'package:flutter/material.dart';
import 'services/plan_service.dart';
import 'pago_simulado_page.dart';

class PlanesPage extends StatelessWidget {
  const PlanesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fondo,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.texto),
        title: const Text(
          'Paquetes disponibles',
          style: TextStyle(color: AppColors.texto),
        ),
        centerTitle: true,
      ),
      body: StreamBuilder<AppPlan>(
        stream: PlanService.planActualStream(),
        builder: (context, snapshot) {
          final planActual = snapshot.data ?? AppPlan.basico;

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Elige el paquete que mejor se ajuste a lo que necesitas. '
                'Puedes cambiar de paquete cuando quieras.',
                style: TextStyle(color: AppColors.textoSecundario, fontSize: 14),
              ),
              const SizedBox(height: 20),
              _tarjetaPlan(
                context: context,
                plan: AppPlan.basico,
                esActual: planActual == AppPlan.basico,
              ),
              const SizedBox(height: 16),
              _tarjetaPlan(
                context: context,
                plan: AppPlan.intermedio,
                esActual: planActual == AppPlan.intermedio,
              ),
              const SizedBox(height: 16),
              _tarjetaPlan(
                context: context,
                plan: AppPlan.premium,
                esActual: planActual == AppPlan.premium,
                destacado: true,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _tarjetaPlan({
    required BuildContext context,
    required AppPlan plan,
    required bool esActual,
    bool destacado = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.tarjeta,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: destacado ? const Color(0xFFE0A106) : Colors.transparent,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                plan.nombre,
                style: const TextStyle(
                  color: AppColors.texto,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (esActual) ...[
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Plan actual',
                    style: TextStyle(color: Colors.green, fontSize: 12),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            plan.precioReferencia,
            style: const TextStyle(color: AppColors.textoSecundario, fontSize: 14),
          ),
          const SizedBox(height: 14),
          ...plan.caracteristicas.map(
            (c) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle,
                      color: AppColors.textoSecundario, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      c,
                      style: const TextStyle(
                          color: AppColors.textoSecundario, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: esActual
                  ? null
                  : () async {
                      // El plan Básico es gratis, así que se cambia directo,
                      // sin pasar por la pantalla de pago.
                      if (plan == AppPlan.basico) {
                        String mensaje;
                        try {
                          await PlanService.cambiarPlan(plan);
                          mensaje = 'Ahora tienes el plan ${plan.nombre} ✅';
                        } catch (e) {
                          mensaje = 'No se pudo cambiar de plan: $e';
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(mensaje)),
                          );
                        }
                        return;
                      }

                      // Planes de pago (Intermedio/Premium): pasan primero
                      // por la pantalla de pago simulado. Ahí, si el "pago"
                      // se completa, se llama a PlanService.cambiarPlan().
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PagoSimuladoPage(plan: plan),
                        ),
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    esActual ? Colors.grey.shade400 : null,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                esActual ? 'Ya lo tienes' : 'Cambiar a este plan',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}