import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Días que dura la prueba gratuita del paquete Premium.
const int kDiasPruebaPremium = 15;

/// false = el límite de imágenes es TOTAL por cuenta.
/// true  = el contador de imágenes se reinicia cada mes.
/// (Si quieres que el límite sea mensual, solo cambia esto a true.)
const bool kLimiteImagenesPorMes = false;

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

  /// Límite de imágenes del paquete. null = sin límite.
  int? get limiteImagenes {
    switch (this) {
      case AppPlan.basico:
        return 3;
      case AppPlan.intermedio:
        return 6;
      case AppPlan.premium:
        return null;
    }
  }

  String get textoLimiteImagenes {
    final int? limite = limiteImagenes;
    if (limite == null) return 'Imágenes ilimitadas';
    return kLimiteImagenesPorMes
        ? 'Hasta $limite imágenes al mes'
        : 'Hasta $limite imágenes';
  }

  List<String> get caracteristicas {
    switch (this) {
      case AppPlan.basico:
        return [
          'Conteo automático de colonias',
          'Análisis con IA (Claude)',
          textoLimiteImagenes,
        ];
      case AppPlan.intermedio:
        return [
          'Todo lo del plan Básico',
          textoLimiteImagenes,
          'Historial de reportes guardados',
          'Exportar a PDF o imagen (con marca de agua)',
        ];
      case AppPlan.premium:
        return [
          'Todo lo del plan Intermedio',
          textoLimiteImagenes,
          'Exportar a PDF o imagen sin marca de agua',
          'Gráficas y estadísticas',
        ];
    }
  }
}

/// Foto completa del estado del usuario: paquete contratado, prueba
/// Premium e imágenes usadas. Todas las pantallas leen de aquí.
class EstadoPlan {
  /// Paquete que el usuario realmente tiene contratado.
  final AppPlan planBase;

  /// null = este usuario todavía no ha recibido la prueba.
  /// 'activa' | 'terminada' (ya venció y se le avisó) | 'rechazada' (versión vieja)
  final String? pruebaEstado;
  final DateTime? pruebaFin;
  final int imagenesUsadas;

  const EstadoPlan({
    required this.planBase,
    this.pruebaEstado,
    this.pruebaFin,
    this.imagenesUsadas = 0,
  });

  static const EstadoPlan porDefecto = EstadoPlan(planBase: AppPlan.basico);

  factory EstadoPlan.desdeMapa(Map<String, dynamic>? data) {
    final dynamic ts = data?['pruebaPremiumFin'];
    final DateTime? fin = ts is Timestamp ? ts.toDate() : null;

    int usadas = (data?['imagenesUsadas'] as num?)?.toInt() ?? 0;
    if (kLimiteImagenesPorMes && data?['imagenesMes'] != _mesActual()) {
      usadas = 0;
    }

    return EstadoPlan(
      planBase: PlanService.fromId(data?['plan'] as String?),
      pruebaEstado: data?['pruebaPremiumEstado'] as String?,
      pruebaFin: fin,
      imagenesUsadas: usadas,
    );
  }

  bool get pruebaActiva =>
      pruebaEstado == 'activa' &&
      pruebaFin != null &&
      pruebaFin!.isAfter(DateTime.now());

  /// La prueba ya venció pero al usuario todavía no se le ha avisado.
  bool get pruebaVencidaSinAviso =>
      pruebaEstado == 'activa' &&
      pruebaFin != null &&
      !pruebaFin!.isAfter(DateTime.now());

  int get diasPruebaRestantes {
    if (!pruebaActiva) return 0;
    final int horas = pruebaFin!.difference(DateTime.now()).inHours;
    final int dias = (horas / 24).ceil();
    return math.max(1, math.min(dias, kDiasPruebaPremium));
  }

  /// Paquete que se usa para decidir qué puede hacer el usuario ahora:
  /// durante la prueba activa, cuenta como Premium.
  AppPlan get planEfectivo =>
      (planBase != AppPlan.premium && pruebaActiva)
          ? AppPlan.premium
          : planBase;

  int? get limiteImagenes => planEfectivo.limiteImagenes;

  bool get puedeSubirImagen =>
      limiteImagenes == null || imagenesUsadas < limiteImagenes!;
}

String _mesActual() {
  final DateTime now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}';
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

  static DocumentReference<Map<String, dynamic>>? _docUsuario() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance.collection(_coleccion).doc(user.uid);
  }

  // ------------------------------------------------------------
  // ESTADO COMPLETO (plan + prueba + imágenes usadas)
  // ------------------------------------------------------------
  static Stream<EstadoPlan> estadoPlanStream() {
    final ref = _docUsuario();
    if (ref == null) return Stream.value(EstadoPlan.porDefecto);

    return ref.snapshots().map((doc) => EstadoPlan.desdeMapa(doc.data()));
  }

  static Future<EstadoPlan> obtenerEstado() async {
    final ref = _docUsuario();
    if (ref == null) return EstadoPlan.porDefecto;

    final doc = await ref.get();
    return EstadoPlan.desdeMapa(doc.data());
  }

  // ------------------------------------------------------------
  // PLAN EFECTIVO (ya considera la prueba Premium)
  // ------------------------------------------------------------
  static Stream<AppPlan> planActualStream() =>
      estadoPlanStream().map((e) => e.planEfectivo);

  static Future<AppPlan> obtenerPlanActual() async =>
      (await obtenerEstado()).planEfectivo;

  static Future<void> cambiarPlan(AppPlan nuevoPlan) async {
    final ref = _docUsuario();
    if (ref == null) return;

    await ref.set(
      {
        'plan': nuevoPlan.id,
        'planActualizadoEn': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  // ------------------------------------------------------------
  // PRUEBA PREMIUM
  // ------------------------------------------------------------

  /// Activa la prueba gratis. Devuelve false si ya se había ofrecido antes.
  static Future<bool> aceptarPruebaPremium() async {
    final ref = _docUsuario();
    if (ref == null) return false;

    final DateTime fin =
        DateTime.now().add(const Duration(days: kDiasPruebaPremium));

    return FirebaseFirestore.instance.runTransaction<bool>((tx) async {
      final snap = await tx.get(ref);
      if (snap.data()?['pruebaPremiumEstado'] != null) return false;

      tx.set(
        ref,
        {
          'pruebaPremiumEstado': 'activa',
          'pruebaPremiumInicio': FieldValue.serverTimestamp(),
          'pruebaPremiumFin': Timestamp.fromDate(fin),
        },
        SetOptions(merge: true),
      );
      return true;
    });
  }

  /// Se llama cuando ya se le avisó al usuario que su prueba terminó.
  /// Desde aquí en adelante solo cuenta su paquete contratado.
  static Future<void> marcarPruebaTerminada() async {
    final ref = _docUsuario();
    if (ref == null) return;

    await ref.set(
      {'pruebaPremiumEstado': 'terminada'},
      SetOptions(merge: true),
    );
  }

  /// (Versión vieja) El usuario dijo "ahora no": se guarda para no volver a preguntarle.
  static Future<void> rechazarPruebaPremium() async {
    final ref = _docUsuario();
    if (ref == null) return;

    await ref.set(
      {'pruebaPremiumEstado': 'rechazada'},
      SetOptions(merge: true),
    );
  }

  // ------------------------------------------------------------
  // LÍMITE DE IMÁGENES
  // ------------------------------------------------------------

  /// Suma 1 al contador de imágenes usadas.
  /// Devuelve false si el usuario ya alcanzó el límite de su paquete.
  /// Se hace en una transacción para que no se pueda pasar del límite.
  static Future<bool> registrarImagenUsada() async {
    final ref = _docUsuario();
    if (ref == null) return false;

    return FirebaseFirestore.instance.runTransaction<bool>((tx) async {
      final snap = await tx.get(ref);
      final estado = EstadoPlan.desdeMapa(snap.data());

      if (!estado.puedeSubirImagen) return false;

      // Con paquete sin límite (Premium o prueba) no se cuentan las
      // imágenes: así, al terminar la prueba, el usuario no queda bloqueado
      // por las fotos que subió gratis.
      if (estado.limiteImagenes == null) return true;

      tx.set(
        ref,
        {
          'imagenesUsadas': estado.imagenesUsadas + 1,
          'imagenesMes': _mesActual(),
        },
        SetOptions(merge: true),
      );
      return true;
    });
  }

  // ------------------------------------------------------------
  // PERMISOS POR PAQUETE
  // ------------------------------------------------------------
  static bool tieneHistorial(AppPlan plan) =>
      plan == AppPlan.intermedio || plan == AppPlan.premium;

  static bool tieneGraficas(AppPlan plan) => plan == AppPlan.premium;

  /// La IA (Claude) ahora está en TODOS los paquetes.
  static bool tieneIA(AppPlan plan) => true;

  /// Solo el Premium exporta sin marca de agua.
  static bool tieneMarcaDeAgua(AppPlan plan) => plan != AppPlan.premium;
}