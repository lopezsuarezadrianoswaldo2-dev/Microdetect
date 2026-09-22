import 'package:bioconteo_colonias_bacterinas/services/plan_service.dart';
import 'package:bioconteo_colonias_bacterinas/planes_page.dart';
import 'dart:io';
import 'nuevo_reporte_page.dart';
import 'package:bioconteo_colonias_bacterinas/historial_page.dart';
import 'package:bioconteo_colonias_bacterinas/perfil.dart';
import 'package:bioconteo_colonias_bacterinas/services/graficaspage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'login.dart'; // ← IMPORTANTE para regresar al login


class HomePanel extends StatefulWidget {
  @override
  _HomePanelState createState() => _HomePanelState();
}

class _HomePanelState extends State<HomePanel> {
  int currentIndex = 0;

  AppPlan _planActual = AppPlan.basico;

  void _mostrarBloqueado(String funcion) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1B263B),
        title: Row(children: const [
          Icon(Icons.lock, color: Colors.white70),
          SizedBox(width: 10),
          Text('Función bloqueada', style: TextStyle(color: Colors.white)),
        ]),
        content: Text(
          '$funcion no está disponible en tu paquete actual '
          '(${_planActual.nombre}). Cambia de paquete para desbloquearla.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:
                const Text('Cerrar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PlanesPage()));
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF415A77)),
            child: const Text('Ver paquetes',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> seleccionarImagen(ImageSource source) async {
    final ImagePicker picker = ImagePicker();
    final XFile? imagen = await picker.pickImage(source: source);

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
                      color: Colors.black87,
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
                        color: Color(0xFF0D1B2A),
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
                        color: Color(0xFF415A77),
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
                      style: TextStyle(fontSize: 16, color: Colors.black54),
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

  // ============================================================
  // build() ahora escucha el plan del usuario en tiempo real y le
  // pasa a _buildScaffold si Historial/Gráficas están disponibles.
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppPlan>(
      stream: PlanService.planActualStream(),
      builder: (context, snapshot) {
        _planActual = snapshot.data ?? AppPlan.basico;
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
      backgroundColor: Color(0xFF0D1B2A),

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "Contador de Bacterias",
          style: TextStyle(fontSize: 22, color: Colors.white),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.workspace_premium, color: Colors.white),
            tooltip: 'Mis paquetes',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PlanesPage()),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.logout, color: Colors.white),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => Login()),
              );
            },
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
                  style: TextStyle(color: Colors.white70, fontSize: 18),
                ),
              ),
            ],
          ),

          // Botón mover / subir imagen en esquina inferior derecha
          Positioned(
            bottom: 25,
            right: 25,
            child: GestureDetector(
              onTap: mostrarOpcionesImagen,
              child: Container(
                padding: EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white10,
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
        backgroundColor: Color(0xFF1B263B),

        // Misma apariencia siempre
        selectedItemColor: Colors.white,
        unselectedItemColor: Colors.white,

        // Para que no use animación de shifting
        type: BottomNavigationBarType.fixed,

        currentIndex: currentIndex,
        onTap: (index) {
          // Índice 0: Inicio — siempre disponible
          if (index == 0) {
            setState(() => currentIndex = index);
            print("Inicio");
            return;
          }

          // Índice 1: Historial — requiere paquete Intermedio o Premium
          if (index == 1) {
            if (!historialDisponible) {
              _mostrarBloqueado('El historial');
              return;
            }
            setState(() => currentIndex = index);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => HistorialPage()),
            );
            return;
          }

          // Índice 2: Perfil — siempre disponible
          if (index == 2) {
            setState(() => currentIndex = index);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => Perfil()),
            );
            return;
          }

          // Índice 3: Gráficas — requiere paquete Premium
          if (index == 3) {
            if (!graficasDisponibles) {
              _mostrarBloqueado('Las gráficas');
              return;
            }
            setState(() => currentIndex = index);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => GraficaPageBonita()),
            );
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