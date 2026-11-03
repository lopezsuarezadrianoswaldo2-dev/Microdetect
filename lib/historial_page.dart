import 'package:bioconteo_colonias_bacterinas/app_colors.dart';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'detalles_page.dart';
import 'services/auth_wrapper.dart';

class HistorialPage extends StatefulWidget {
  const HistorialPage({super.key});

  @override
  State<HistorialPage> createState() => _HistorialPageState();
}

class _HistorialPageState extends State<HistorialPage> {
  // ============================================================
  // RENDIMIENTO: traza personalizada "consulta_historial".
  // Arranca al abrir la pantalla y se detiene cuando Firestore
  // entrega los reportes (o cuando ocurre un error).
  // ============================================================
  Trace? _trazaConsulta;
  bool _trazaTerminada = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _trazaConsulta =
          FirebasePerformance.instance.newTrace('consulta_historial');
      _trazaConsulta!.start();
    }
  }

  @override
  void dispose() {
    // Si el usuario sale antes de que lleguen los datos, se cierra la traza.
    _terminarTraza('cancelado');
    super.dispose();
  }

  void _terminarTraza(String resultado, {int? reportes}) {
    if (_trazaTerminada || _trazaConsulta == null) return;
    _trazaTerminada = true;
    _trazaConsulta!.putAttribute('resultado', resultado);
    if (reportes != null) {
      _trazaConsulta!.setMetric('reportes_cargados', reportes);
    }
    _trazaConsulta!.stop();
  }

  // Cierra la sesión de Firebase de verdad y regresa al AuthWrapper,
  // que decide solo si mostrar Login o Home.
  Future<void> _cerrarSesion(BuildContext context) async {
    final navigator = Navigator.of(context);
    await FirebaseAuth.instance.signOut();
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthWrapper()),
      (route) => false,
    );
  }

  // Convierte el texto base64 de Firestore en bytes de imagen.
  // Devuelve null si está vacío o dañado.
  Uint8List? _decodificar(String texto) {
    if (texto.isEmpty) return null;
    try {
      return base64Decode(texto);
    } catch (_) {
      return null;
    }
  }

  // Fecha de creación en milisegundos. Si Firestore todavía no la
  // confirmó (null), se trata como "ahora" para que salga primero.
  int _creadoMs(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final valor = data['creado'];
    if (valor is Timestamp) return valor.millisecondsSinceEpoch;
    return DateTime.now().millisecondsSinceEpoch;
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppColors.fondo,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.texto),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Historial',
          style: TextStyle(fontSize: 22, color: AppColors.texto),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.texto),
            onPressed: () => _cerrarSesion(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Historial de conteo',
              style: TextStyle(color: AppColors.textoSecundario, fontSize: 18),
            ),
            const SizedBox(height: 25),

            // Lista conectada a Firestore, solo del usuario con sesión.
            // Se ordena aquí en la app (no en la consulta) para no
            // necesitar crear un índice compuesto en Firebase.
            Expanded(
              child: user == null
                  ? const Center(
                      child: Text(
                        'No hay sesión iniciada.',
                        style: TextStyle(color: AppColors.textoSecundario),
                      ),
                    )
                  : StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('reportes')
                          .where('uid', isEqualTo: user.uid)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          // Rendimiento: se cierra la traza marcándola con error.
                          _terminarTraza('error');
                          // Estabilidad: se registra con la funcionalidad afectada.
                          if (!kIsWeb) {
                            FirebaseCrashlytics.instance.setCustomKey(
                                'funcionalidad', 'consulta_historial');
                            FirebaseCrashlytics.instance.recordError(
                              snapshot.error!,
                              StackTrace.current,
                              reason: 'Error al cargar el historial',
                            );
                          }
                          return Center(
                            child: Text(
                              'Error al cargar el historial:\n${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                          );
                        }

                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.texto,
                            ),
                          );
                        }

                        final docs = [...(snapshot.data?.docs ?? [])];
                        docs.sort((a, b) => _creadoMs(b).compareTo(_creadoMs(a)));

                        // Rendimiento: ya llegaron los reportes, se cierra la traza.
                        _terminarTraza('exito', reportes: docs.length);

                        if (docs.isEmpty) {
                          return const Center(
                            child: Text(
                              'Todavía no tienes reportes guardados.',
                              style: TextStyle(color: AppColors.textoSecundario),
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
                            final String hora = (data['hora'] ?? '').toString();
                            final String conteo =
                                (data['conteo'] ?? '').toString();
                            final String descripcion =
                                (data['descripcion'] ?? '').toString();

                            // La foto viene dentro del reporte (imagenBase64).
                            // Los reportes viejos solo tienen una ruta local
                            // del celular (imageUrl); se usa como respaldo.
                            final String imagenBase64 =
                                (data['imagenBase64'] ?? '').toString();
                            final Uint8List? imagenBytes =
                                _decodificar(imagenBase64);

                            final String rutaImagen =
                                (data['imageUrl'] ?? '').toString();
                            final File archivoImagen = File(rutaImagen);
                            final bool imagenExiste = rutaImagen.isNotEmpty &&
                                archivoImagen.existsSync();

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
                                      imagenBase64: imagenBase64,
                                      // Respaldo para reportes viejos.
                                      imagePath: imagenExiste ? rutaImagen : '',
                                    ),
                                  ),
                                );
                              },
                              child: historialItem(
                                fecha: fecha,
                                hora: hora,
                                descripcion: descripcion,
                                imagenBytes: imagenBytes,
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
    required Uint8List? imagenBytes,
    required bool imagenExiste,
    required File archivoImagen,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.tarjeta,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Miniatura de la foto real (o un ícono si no existe)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: imagenBytes != null
                ? Image.memory(
                    imagenBytes,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    cacheWidth: 120,
                  )
                : imagenExiste
                    ? Image.file(
                        archivoImagen,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                      )
                    : Container(
                    width: 60,
                    height: 60,
                    color: Colors.white,
                    child: const Icon(
                      Icons.image_not_supported,
                      color: AppColors.textoTenue,
                    ),
                  ),
          ),
          const SizedBox(width: 15),

          // Texto del registro
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fecha: $fecha',
                  style: const TextStyle(color: AppColors.texto, fontSize: 16),
                ),
                Text(
                  'Hora: $hora',
                  style: const TextStyle(color: AppColors.textoSecundario, fontSize: 15),
                ),
                const SizedBox(height: 5),
                Text(
                  descripcion,
                  style: const TextStyle(color: AppColors.textoSecundario),
                ),
              ],
            ),
          ),

          const Icon(Icons.info_outline, color: AppColors.textoSecundario, size: 30),
        ],
      ),
    );
  }
}