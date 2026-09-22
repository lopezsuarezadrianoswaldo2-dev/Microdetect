import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login.dart';
import 'detalles_page.dart'; // 👈 IMPORTANTE

class HistorialPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Color(0xFF0D1B2A),

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,

        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),

        title: Text(
          "Historial",
          style: TextStyle(fontSize: 22, color: Colors.white),
        ),

        actions: [
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

      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            Text(
              "Historial de conteo",
              style: TextStyle(
                color: Colors.white70,
                fontSize: 18,
              ),
            ),

            SizedBox(height: 25),

            // ============================================================
            // Lista conectada a Firestore, filtrada solo por el usuario
            // que inició sesión (campo "uid" guardado en cada reporte).
            // ============================================================
            Expanded(
              child: user == null
                  ? Center(
                      child: Text(
                        "No hay sesión iniciada.",
                        style: TextStyle(color: Colors.white70),
                      ),
                    )
                  : StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('reportes')
                          .where('uid', isEqualTo: user.uid)
                          .orderBy('creado', descending: true)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              "Error al cargar el historial:\n${snapshot.error}",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.redAccent),
                            ),
                          );
                        }

                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          );
                        }

                        final docs = snapshot.data?.docs ?? [];

                        if (docs.isEmpty) {
                          return Center(
                            child: Text(
                              "Todavía no tienes reportes guardados.",
                              style: TextStyle(color: Colors.white70),
                            ),
                          );
                        }

                        return ListView.builder(
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final data =
                                docs[index].data() as Map<String, dynamic>;

                            final String fecha =
                                (data['fecha'] ?? '').toString();
                            final String hora =
                                (data['hora'] ?? '').toString();
                            final String conteo =
                                (data['conteo'] ?? '').toString();
                            final String descripcion =
                                (data['descripcion'] ?? '').toString();

                            // ------------------------------------------------
                            // La imagen se guarda como RUTA LOCAL en el
                            // celular (no una URL de internet). Hay que
                            // verificar que el archivo todavía exista antes
                            // de intentar mostrarlo.
                            // ------------------------------------------------
                            final String rutaImagen =
                                (data['imageUrl'] ?? '').toString();

                            final File archivoImagen = File(rutaImagen);

                            final bool imagenExiste = rutaImagen.isNotEmpty &&
                                archivoImagen.existsSync();

                            // ---- DIAGNÓSTICO TEMPORAL ----
                            debugPrint('[HISTORIAL] Ruta: "$rutaImagen"');
                            debugPrint(
                                '[HISTORIAL] Longitud de la ruta: ${rutaImagen.length}');
                            debugPrint(
                                '[HISTORIAL] ¿Existe el archivo?: $imagenExiste');
                            // -------------------------------

                            return GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => DetallesPage(
                                      fecha: fecha,
                                      hora: hora,
                                      conteo: conteo,
                                      descripcion: descripcion,
                                      // DetallesPage espera una ruta local
                                      // (File), así que si no existe la
                                      // imagen real, usamos un marcador.
                                      imagePath: imagenExiste
                                          ? rutaImagen
                                          : 'assets/muestra1.png',
                                    ),
                                  ),
                                );
                              },
                              child: historialItem(
                                fecha: fecha,
                                hora: hora,
                                descripcion: descripcion,
                                imagenExiste: imagenExiste,
                                archivoImagen: archivoImagen,
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- WIDGET PARA CADA REGISTRO ----
  Widget historialItem({
    required String fecha,
    required String hora,
    required String descripcion,
    required bool imagenExiste,
    required File archivoImagen,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: 15),
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Color(0xFF1B263B),
        borderRadius: BorderRadius.circular(15),
      ),

      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // Miniatura de la foto real (o un ícono si no existe)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: imagenExiste
                ? Image.file(
                    archivoImagen,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 60,
                    height: 60,
                    color: Colors.white10,
                    child: Icon(
                      Icons.image_not_supported,
                      color: Colors.white38,
                    ),
                  ),
          ),

          SizedBox(width: 15),

          // Texto del registro
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Fecha: $fecha",
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
                Text(
                  "Hora: $hora",
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
                SizedBox(height: 5),
                Text(
                  descripcion,
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),

          Icon(Icons.info_outline, color: Colors.white54, size: 30),
        ],
      ),
    );
  }
}