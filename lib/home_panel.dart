import 'dart:io';

import 'package:bioconteo_colonias_bacterinas/app_colors.dart';
import 'package:bioconteo_colonias_bacterinas/historial_page.dart';
import 'package:bioconteo_colonias_bacterinas/perfil.dart';
import 'package:bioconteo_colonias_bacterinas/planes_page.dart';
import 'package:bioconteo_colonias_bacterinas/services/auth_wrapper.dart';
import 'package:bioconteo_colonias_bacterinas/services/dialogos_plan.dart';
import 'package:bioconteo_colonias_bacterinas/services/graficaspage.dart';
import 'package:bioconteo_colonias_bacterinas/services/plan_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'nuevo_reporte_page.dart';

class HomePanel extends StatefulWidget {
  @override
  _HomePanelState createState() => _HomePanelState();
}

class _HomePanelState extends State<HomePanel> {
  int currentIndex = 0;

  // Se crea una sola vez para que el StreamBuilder no se reconecte
  // en cada rebuild.
  late final Stream<EstadoPlan> _estadoStream;
  EstadoPlan _estado = EstadoPlan.porDefecto;
  bool _revisandoPrueba = false;

  AppPlan get _planActual => _estado.planEfectivo;

  @override
  void initState() {
    super.initState();
    _estadoStream = PlanService.estadoPlanStream();

    // Al entrar por primera vez (ya con sesión iniciada) se activa la prueba Premium.
    WidgetsBinding.instance.addPostFrameCallback((_) => _revisarPruebaPremium());
  }

  // ============================================================
  // PRUEBA PREMIUM AUTOMÁTICA (15 días gratis)
  //  - Usuario que nunca tuvo prueba: se activa SOLA y se le da la
  //    bienvenida (como Spotify o YouTube Premium).
  //  - Prueba vencida: se le avisa una sola vez y se le invita a
  //    contratar un paquete; si no, queda en su paquete (Básico).
  // El estado vive en Firestore (usuarios/{uid}.pruebaPremiumEstado),
  // así que cada cuenta recibe la prueba una sola vez.
  // ============================================================
  /// Espera a que el Home sea de verdad la pantalla que ve el usuario
  /// (sesión iniciada y sin otra pantalla encima, como Login o Registro).
  /// Devuelve false si el Home se cierra antes o pasa demasiado tiempo.
  Future<bool> _esperarPantallaVisible() async {
    for (int i = 0; i < 60; i++) {
      if (!mounted) return false;

      final ModalRoute<dynamic>? ruta = ModalRoute.of(context);
      final bool visible = (ruta?.isCurrent ?? false) &&
          FirebaseAuth.instance.currentUser != null;

      if (visible) {
        // Pequeña pausa para que termine la transición de pantalla.
        await Future.delayed(const Duration(milliseconds: 600));
        if (!mounted) return false;
        return (ModalRoute.of(context)?.isCurrent ?? false) &&
            FirebaseAuth.instance.currentUser != null;
      }

      await Future.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  Future<void> _revisarPruebaPremium() async {
    if (_revisandoPrueba) return;
    _revisandoPrueba = true;

    try {
      // El aviso solo sale ya con la sesión iniciada y el Home a la vista,
      // nunca encima del Login, el Registro o el logo.
      if (!await _esperarPantallaVisible()) return;

      final EstadoPlan estado = await PlanService.obtenerEstado();
      if (!mounted) return;

      // Ya es Premium de pago: no necesita prueba.
      if (estado.planBase == AppPlan.premium) return;

      // 1) Prueba vencida: aviso de fin.
      if (estado.pruebaVencidaSinAviso) {
        await PlanService.marcarPruebaTerminada();
        if (!mounted) return;
        final bool verPaquetes = await mostrarDialogoFinPrueba(context);
        if (verPaquetes && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PlanesPage()),
          );
        }
        return;
      }

      // 2) Cuenta que nunca recibió la prueba: se activa automáticamente.
      if (estado.pruebaEstado == null) {
        final bool activada = await PlanService.aceptarPruebaPremium();
        if (activada && mounted) {
          await mostrarDialogoBienvenidaPrueba(context);
        }
      }
    } catch (e) {
      debugPrint('[PRUEBA PREMIUM] Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo revisar la prueba Premium: $e')),
        );
      }
    } finally {
      _revisandoPrueba = false;
    }
  }

  void _mostrarBloqueado(String funcion) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.tarjeta,
        title: Row(children: const [
          Icon(Icons.lock, color: AppColors.textoSecundario),
          SizedBox(width: 10),
          Text('Función bloqueada', style: TextStyle(color: AppColors.texto)),
        ]),
        content: Text(
          '$funcion no está disponible en tu paquete actual '
          '(${_planActual.nombre}). Cambia de paquete para desbloquearla.',
          style: const TextStyle(color: AppColors.textoSecundario),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar',
                style: TextStyle(color: AppColors.textoSecundario)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PlanesPage()));
            },
            child: const Text('Ver paquetes',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // SUBIR IMAGEN: primero se revisa el límite del paquete.
  //   Básico: 3  |  Intermedio: 6  |  Premium (o prueba): sin límite
  // ============================================================
  Future<void> _intentarSubirImagen() async {
    final EstadoPlan estado = await PlanService.obtenerEstado();
    if (!mounted) return;

    if (!estado.puedeSubirImagen) {
      final bool verPaquetes =
          await mostrarDialogoLimiteImagenes(context, estado);
      if (verPaquetes && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const PlanesPage()),
        );
      }
      return;
    }

    mostrarOpcionesImagen();
  }

  Future<void> seleccionarImagen(ImageSource source) async {
    final ImagePicker picker = ImagePicker();
    final XFile? imagen = await picker.pickImage(source: source);

    if (!mounted) return; // evita usar context si la pantalla ya no existe

    if (imagen != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NuevoReportePage(imagen: File(imagen.path)),
        ),
      );
    }
  }

  void mostrarOpcionesImagen() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 280,
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 15,
                    color: Colors.black26,
                    offset: Offset(0, 5),
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Seleccionar imagen",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.texto,
                    ),
                  ),

                  SizedBox(height: 20),

                  // Opción: Cámara
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      seleccionarImagen(ImageSource.camera);
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.primario,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_alt, color: Colors.white, size: 26),
                          SizedBox(width: 10),
                          Text(
                            "Tomar fotografía",
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 12),

                  // Opción: Galería
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      seleccionarImagen(ImageSource.gallery);
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.hover,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.photo_library,
                              color: Colors.white, size: 26),
                          SizedBox(width: 10),
                          Text(
                            "Subir desde galería",
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 15),

                  // Botón cerrar
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      "Cancelar",
                      style: TextStyle(
                          fontSize: 16, color: AppColors.textoSecundario),
                    ),
                  )
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Cierra la sesión de Firebase de verdad y regresa al AuthWrapper,
  // que decide solo si mostrar Login o Home.
  Future<void> _cerrarSesion() async {
    final NavigatorState navigator = Navigator.of(context);
    await FirebaseAuth.instance.signOut();
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthWrapper()),
      (route) => false,
    );
  }

  // ============================================================
  // build() escucha el plan del usuario en tiempo real y le pasa a
  // _buildScaffold si Historial/Gráficas están disponibles.
  // Durante la prueba Premium, el plan efectivo es Premium.
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<EstadoPlan>(
      stream: _estadoStream,
      builder: (context, snapshot) {
        _estado = snapshot.data ?? EstadoPlan.porDefecto;

        final bool historialDisponible =
            PlanService.tieneHistorial(_planActual);
        final bool graficasDisponibles =
            PlanService.tieneGraficas(_planActual);

        return _buildScaffold(
          context: context,
          historialDisponible: historialDisponible,
          graficasDisponibles: graficasDisponibles,
        );
      },
    );
  }

  Widget _buildScaffold({
    required BuildContext context,
    required bool historialDisponible,
    required bool graficasDisponibles,
  }) {
    return Scaffold(
      backgroundColor: AppColors.fondo,

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "Contador de Bacterias",
          style: TextStyle(fontSize: 22, color: AppColors.texto),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.workspace_premium, color: AppColors.texto),
            tooltip: 'Mis paquetes',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlanesPage()),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.logout, color: AppColors.texto),
            onPressed: _cerrarSesion,
          ),
        ],
      ),

      // ★★★★★ CUERPO CON BOTÓN ABAJO DERECHA ★★★★★
      body: Stack(
        children: [
          Column(
            children: [
              SizedBox(height: 20),
              Center(
                child: Text(
                  "Analiza aquí tu imagen",
                  style: TextStyle(color: AppColors.textoSecundario, fontSize: 18),
                ),
              ),
            ],
          ),

          // Botón mover / subir imagen en esquina inferior derecha
          Positioned(
            bottom: 25,
            right: 25,
            child: GestureDetector(
              onTap: _intentarSubirImagen,
              child: Container(
                padding: EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.primario,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.add_a_photo,
                  size: 40,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),

      // ★★★★★ BOTTOM BAR — CON BLOQUEO POR PAQUETE ★★★★★
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: AppColors.tarjeta,

        // Misma apariencia siempre
        selectedItemColor: AppColors.primario,
        unselectedItemColor: AppColors.textoSecundario,

        // Para que no use animación de shifting
        type: BottomNavigationBarType.fixed,

        currentIndex: currentIndex,

        // Al regresar de cada pantalla la barra vuelve a marcar "Inicio".
        onTap: (index) async {
          // Índice 0: Inicio — siempre disponible
          if (index == 0) {
            setState(() => currentIndex = 0);
            return;
          }

          // Índice 1: Historial — requiere paquete Intermedio o Premium
          if (index == 1) {
            if (!historialDisponible) {
              _mostrarBloqueado('El historial');
              return;
            }
            setState(() => currentIndex = 1);
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => HistorialPage()),
            );
            if (mounted) setState(() => currentIndex = 0);
            return;
          }

          // Índice 2: Perfil — siempre disponible
          if (index == 2) {
            setState(() => currentIndex = 2);
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => Perfil()),
            );
            if (mounted) setState(() => currentIndex = 0);
            return;
          }

          // Índice 3: Gráficas — requiere paquete Premium
          if (index == 3) {
            if (!graficasDisponibles) {
              _mostrarBloqueado('Las gráficas');
              return;
            }
            setState(() => currentIndex = 3);
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => GraficaPageBonita()),
            );
            if (mounted) setState(() => currentIndex = 0);
            return;
          }
        },

        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Inicio"),
          BottomNavigationBarItem(
            icon: Icon(historialDisponible ? Icons.history : Icons.lock),
            label: "Historial",
          ),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Perfil"),
          BottomNavigationBarItem(
            icon: Icon(graficasDisponibles ? Icons.bar_chart : Icons.lock),
            label: "Gráficas",
          ),
        ],
      ),
    );
  }
}