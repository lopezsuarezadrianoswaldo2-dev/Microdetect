import 'package:bioconteo_colonias_bacterinas/app_colors.dart';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'services/colonia_counter.dart';
import 'services/plan_service.dart';
import 'planes_page.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

/// Reduce la foto para que quepa en un documento de Firestore (límite de
/// 1 MB por documento). Se ejecuta en otro hilo para no congelar la pantalla.
Uint8List _comprimirParaFirestore(Uint8List bytes) {
  final img.Image? original = img.decodeImage(bytes);
  if (original == null) {
    throw Exception('No se pudo leer la imagen.');
  }

  const List<int> anchos = [900, 700, 500, 350];
  Uint8List resultado = bytes;

  for (final int ancho in anchos) {
    final img.Image reducida = original.width > ancho
        ? img.copyResize(original, width: ancho)
        : original;
    resultado = Uint8List.fromList(img.encodeJpg(reducida, quality: 70));

    // 600 KB en bytes ≈ 800 KB en texto base64: queda margen bajo el límite.
    if (resultado.length <= 600000) break;
  }

  return resultado;
}

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

  @override
  void dispose() {
    _descripcionController.dispose();
    super.dispose();
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
          backgroundColor: AppColors.tarjeta,
          title: Row(
            children: const [
              Icon(Icons.auto_awesome, color: Colors.amber),
              SizedBox(width: 10),
              Text('Función Premium', style: TextStyle(color: AppColors.texto)),
            ],
          ),
          content: const Text(
            'El análisis con Inteligencia Artificial solo está disponible '
            'en el paquete Premium.',
            style: TextStyle(color: AppColors.textoSecundario),
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
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PlanesPage()),
                );
              },
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

  // ============================================================
  // ANÁLISIS DE IMAGEN (conteo de colonias)
  //  - Rendimiento: traza personalizada "analisis_imagen".
  //  - Estabilidad: si falla, se registra en Crashlytics con la
  //    etiqueta funcionalidad = analisis_imagen.
  // ============================================================
  Future<void> _procesarImagen() async {
    final trace = FirebasePerformance.instance.newTrace('analisis_imagen');
    await trace.start();

    try {
      final resultado = await ColoniaCounter.contar(widget.imagen);

      // Guardamos la imagen marcada en un archivo temporal para poder
      // mostrarla y luego guardarla de forma permanente en el celular.
      final tempPath = '${widget.imagen.path}_marcada.jpg';
      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(resultado.imagenProcesada);

      trace.putAttribute('resultado', 'exito');
      trace.setMetric('colonias_detectadas', resultado.conteo);

      if (!mounted) return;
      setState(() {
        _conteo = resultado.conteo;
        _imagenMarcadaTemp = tempFile;
        _procesando = false;
      });
    } catch (e, st) {
      trace.putAttribute('resultado', 'error');
      if (!kIsWeb) {
        FirebaseCrashlytics.instance
            .setCustomKey('funcionalidad', 'analisis_imagen');
        FirebaseCrashlytics.instance.recordError(
          e,
          st,
          reason: 'Error al analizar imagen',
        );
      }
      if (mounted) setState(() => _procesando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al analizar la imagen: $e')),
        );
      }
    } finally {
      await trace.stop();
    }
  }

  Future<void> _guardarReporte() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _guardando = true);

    final trace = FirebasePerformance.instance.newTrace('guardar_reporte');
    await trace.start();

    try {
      final now = DateTime.now();
      final fecha =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final hora =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final numeroReporte = 'R-${now.millisecondsSinceEpoch}';

      // ============================================================
      // 1) PREPARAR LA IMAGEN
      //    Se reduce y se convierte a texto (base64) para guardarla
      //    dentro del mismo documento del reporte en Firestore, sin
      //    usar Firebase Storage (que es de pago).
      // ============================================================
      debugPrint('[REPORTE] 1) Preparando imagen...');

      final File imagenOriginal = _imagenMarcadaTemp ?? widget.imagen;
      final Uint8List bytesOriginales = await imagenOriginal.readAsBytes();
      final Uint8List bytesComprimidos =
          await compute(_comprimirParaFirestore, bytesOriginales);
      final String imagenBase64 = base64Encode(bytesComprimidos);

      debugPrint(
          '[REPORTE] 2) Imagen lista: ${(bytesComprimidos.length / 1024).round()} KB');

      // ============================================================
      // 2) GUARDAR EL REPORTE COMPLETO EN FIRESTORE
      //    El campo "imagenBase64" contiene la foto marcada.
      // ============================================================
      debugPrint('[REPORTE] 3) Guardando documento en Firestore...');

      await FirebaseFirestore.instance.collection('reportes').add({
        'uid': user.uid,
        'numeroReporte': numeroReporte,
        'conteo': _conteo,
        'descripcion': _descripcionController.text.trim(),
        'fecha': fecha,
        'hora': hora,
        'imagenBase64': imagenBase64,
        'creado': FieldValue.serverTimestamp(),
      }).timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception(
            'Tiempo agotado guardando en Firestore (30s). Revisa tu internet y las reglas de seguridad de Firestore.'),
      );

      debugPrint('[REPORTE] 4) ¡Guardado con éxito!');
      trace.putAttribute('resultado', 'exito');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reporte $numeroReporte guardado ✅')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      debugPrint('[REPORTE] ❌ ERROR AL GUARDAR: $e');
      trace.putAttribute('resultado', 'error');
      if (!kIsWeb) {
        FirebaseCrashlytics.instance
            .setCustomKey('funcionalidad', 'guardado_reporte');
        FirebaseCrashlytics.instance.recordError(
          e,
          StackTrace.current,
          reason: 'Error al guardar reporte',
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al guardar el reporte: $e')),
        );
      }
    } finally {
      await trace.stop();
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fondo,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title:
            const Text('Nuevo reporte', style: TextStyle(color: AppColors.texto)),
        iconTheme: const IconThemeData(color: AppColors.texto),
      ),
      body: _procesando
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.texto),
                  SizedBox(height: 20),
                  Text('Analizando la imagen y contando colonias...',
                      style: TextStyle(color: AppColors.textoSecundario)),
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
                      color: AppColors.tarjeta,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.biotech,
                            color: AppColors.texto, size: 32),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Conteo automático',
                                style: TextStyle(
                                    color: AppColors.textoSecundario, fontSize: 14)),
                            Text('$_conteo colonias detectadas',
                                style: const TextStyle(
                                    color: AppColors.texto,
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
                        style: TextStyle(color: AppColors.texto),
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
                      style: TextStyle(color: AppColors.textoSecundario, fontSize: 14)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descripcionController,
                    maxLines: 3,
                    style: const TextStyle(color: AppColors.texto),
                    decoration: InputDecoration(
                      hintText: 'Ej. Muestra tomada a las 24h de incubación...',
                      hintStyle: const TextStyle(color: AppColors.textoTenue),
                      filled: true,
                      fillColor: AppColors.tarjeta,
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