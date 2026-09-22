import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum AppPlan { basico, intermedio, premium }

extension AppPlanInfo on AppPlan {
  String get id {
    switch (this) {
      case AppPlan.basico:
        return 'basico';
      case AppPlan.intermedio:
        return 'intermedio';
      case AppPlan.premium:
        return 'premium';
    }
  }

  String get nombre {
    switch (this) {
      case AppPlan.basico:
        return 'Básico';
      case AppPlan.intermedio:
        return 'Intermedio';
      case AppPlan.premium:
        return 'Premium';
    }
  }

  String get precioReferencia {
    switch (this) {
      case AppPlan.basico:
        return 'Gratis';
      case AppPlan.intermedio:
        return '\$49 MXN/mes';
      case AppPlan.premium:
        return '\$99 MXN/mes';
    }
  }

  List<String> get caracteristicas {
    switch (this) {
      case AppPlan.basico:
        return ['Conteo automático de colonias', 'Crear reportes nuevos'];
      case AppPlan.intermedio:
        return ['Todo lo del plan Básico', 'Historial de reportes guardados'];
      case AppPlan.premium:
        return [
          'Todo lo del plan Intermedio',
          'Gráficas y estadísticas',
          'Análisis con Inteligencia Artificial',
        ];
    }
  }
}

class PlanService {
  PlanService._();

  static const String _coleccion = 'usuarios';

  static AppPlan fromId(String? id) {
    switch (id) {
      case 'intermedio':
        return AppPlan.intermedio;
      case 'premium':
        return AppPlan.premium;
      case 'basico':
      default:
        return AppPlan.basico;
    }
  }

  static Stream<AppPlan> planActualStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(AppPlan.basico);

    return FirebaseFirestore.instance
        .collection(_coleccion)
        .doc(user.uid)
        .snapshots()
        .map((doc) => fromId(doc.data()?['plan'] as String?));
  }

  static Future<AppPlan> obtenerPlanActual() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return AppPlan.basico;

    final doc = await FirebaseFirestore.instance
        .collection(_coleccion)
        .doc(user.uid)
        .get();

    return fromId(doc.data()?['plan'] as String?);
  }

  static Future<void> cambiarPlan(AppPlan nuevoPlan) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection(_coleccion).doc(user.uid).set(
      {
        'plan': nuevoPlan.id,
        'planActualizadoEn': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  static bool tieneHistorial(AppPlan plan) =>
      plan == AppPlan.intermedio || plan == AppPlan.premium;

  static bool tieneGraficas(AppPlan plan) => plan == AppPlan.premium;

  static bool tieneIA(AppPlan plan) => plan == AppPlan.premium;
}