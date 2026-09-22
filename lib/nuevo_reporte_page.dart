import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'services/colonia_counter.dart';
import 'services/plan_service.dart';
import 'planes_page.dart';

class NuevoReportePage extends StatefulWidget {
  final File imagen;
  const NuevoReportePage({Key? key, required this.imagen}) : super(key: key);

  @override
  State<NuevoReportePage> createState() => _NuevoReportePageState();
}

class _NuevoReportePageState extends State<NuevoReportePage> {
  bool _procesando = true;
  bool _guardando = false;
  int _conteo = 0;
  File? _imagenMarcadaTemp;
  final TextEditingController _descripcionController = TextEditingController();

  AppPlan _planActual = AppPlan.basico;

  @override
  void initState() {
    super.initState();
    _procesarImagen();
    _cargarPlan();
  }

  Future<void> _cargarPlan() async {
    final plan = await PlanService.obtenerPlanActual();
    if (mounted) setState(() => _planActual = plan);
  }

  // ============================================================
  // ANÁLISIS CON IA — función exclusiva del paquete Premium.
  //
  // Aquí es donde, más adelante, se debe llamar al modelo de IA real
  // (por ejemplo enviando la imagen a un backend propio o a la API de
  // un proveedor de visión por computadora) para dar un análisis más
  // detallado que el conteo automático actual: por ejemplo, distinguir
  // tipos de colonias, estimar contaminación, sugerir diluciones, etc.
  // Por ahora solo queda gateado detrás del plan Premium.
  // ============================================================
  void _analizarConIA() {
    if (!PlanService.tieneIA(_planActual)) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF1B263B),
          title: Row(
            children: const [
              Icon(Icons.auto_awesome, color: Colors.amber),
              SizedBox(width: 10),
              Text('Función Premium', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: const Text(
            'El análisis con Inteligencia Artificial solo está disponible '
            'en el paquete Premium.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar',
                  style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PlanesPage()),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF415A77),
              ),
              child: const Text('Ver paquetes',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      return;
    }

    // TODO: aquí se conecta el análisis con IA real para usuarios Premium.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Análisis con IA: función en desarrollo 🚧'),
      ),
    );
  }

  Future<void> _procesarImagen() async {
    try {
      final resultado = await ColoniaCounter.contar(widget.imagen);

      // Guardamos la imagen marcada en un archivo temporal para poder
      // mostrarla y luego guardarla de forma permanente en el celular.
      final tempPath = '${widget.imagen.path}_marcada.jpg';
      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(resultado.imagenProcesada);

      setState(() {
        _conteo = resultado.conteo;
        _imagenMarcadaTemp = tempFile;
        _procesando = false;
      });
    } catch (e) {
      setState(() => _procesando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al analizar la imagen: $e')),
        );
      }
    }
  }

  Future<void> _guardarReporte() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _guardando = true);

    try {
      final now = DateTime.now();
      final fecha =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final hora =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final numeroReporte = 'R-${now.millisecondsSinceEpoch}';

      // ============================================================
      // 1) GUARDAR LA IMAGEN EN UNA CARPETA PERMANENTE DEL CELULAR
      //    (no en Firebase Storage, para no depender de un plan
      //    de pago). La app siempre puede acceder a esta carpeta.
      // ============================================================
      debugPrint('[REPORTE] 1) Guardando imagen localmente...');

      final Directory carpetaApp = await getApplicationDocumentsDirectory();

      final Directory carpetaReportes =
          Directory('${carpetaApp.path}/reportes_fotos');

      if (!await carpetaReportes.exists()) {
        await carpetaReportes.create(recursive: true);
      }

      final File imagenOriginal = _imagenMarcadaTemp ?? widget.imagen;

      final String rutaFinal =
          '${carpetaReportes.path}/$numeroReporte.jpg';

      final File imagenGuardada = await imagenOriginal.copy(rutaFinal);

      debugPrint('[REPORTE] 2) Imagen guardada en: ${imagenGuardada.path}');

      // ============================================================
      // 2) GUARDAR EL REPORTE EN FIRESTORE
      //    El campo "imageUrl" ahora guarda la RUTA LOCAL del
      //    archivo en este celular (no una URL de internet).
      // ============================================================
      debugPrint('[REPORTE] 3) Guardando documento en Firestore...');

      await FirebaseFirestore.instance.collection('reportes').add({
        'uid': user.uid,
        'numeroReporte': numeroReporte,
        'conteo': _conteo,
        'descripcion': _descripcionController.text.trim(),
        'fecha': fecha,
        'hora': hora,
        'imageUrl': imagenGuardada.path, // ruta local, no URL de internet
        'creado': FieldValue.serverTimestamp(),
      }).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception(
            'Tiempo agotado guardando en Firestore (15s). Revisa las reglas de seguridad de Firestore.'),
      );

      debugPrint('[REPORTE] 4) ¡Guardado con éxito!');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reporte $numeroReporte guardado ✅')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('[REPORTE] ❌ ERROR AL GUARDAR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar el reporte: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title:
            const Text('Nuevo reporte', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _procesando
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 20),
                  Text('Analizando la imagen y contando colonias...',
                      style: TextStyle(color: Colors.white70)),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(
                      _imagenMarcadaTemp ?? widget.imagen,
                      width: double.infinity,
                      height: 280,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B263B),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.biotech,
                            color: Colors.white, size: 32),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Conteo automático',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 14)),
                            Text('$_conteo colonias detectadas',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ---- BOTÓN ANÁLISIS CON IA (Premium) ----
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _analizarConIA,
                      icon: Icon(
                        PlanService.tieneIA(_planActual)
                            ? Icons.auto_awesome
                            : Icons.lock,
                        color: Colors.amber,
                        size: 20,
                      ),
                      label: const Text(
                        'Análisis con IA (Premium)',
                        style: TextStyle(color: Colors.white),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.amber),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  const Text('Descripción (opcional)',
                      style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descripcionController,
                    maxLines: 3,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Ej. Muestra tomada a las 24h de incubación...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF1B263B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _guardando ? null : _guardarReporte,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF415A77),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _guardando
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : const Text('Guardar reporte',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}