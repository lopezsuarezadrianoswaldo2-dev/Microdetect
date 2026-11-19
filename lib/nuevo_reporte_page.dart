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
import 'services/claude_service.dart';
import 'services/dialogos_plan.dart';
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

  // ---- Análisis con Claude ----
  bool _analizandoIA = false;
  AnalisisIA? _analisis;
  String? _errorIA;

  @override
  void initState() {
    super.initState();
    _procesarImagen();
  }

  @override
  void dispose() {
    _descripcionController.dispose();
    super.dispose();
  }

  // ============================================================
  // LÍMITE DE IMÁGENES
  // Muestra el aviso y cierra esta pantalla. Si el usuario elige
  // "Ver paquetes", lo lleva a la pantalla de paquetes.
  // ============================================================
  Future<void> _bloquearPorLimite() async {
    final EstadoPlan estado = await PlanService.obtenerEstado();
    if (!mounted) return;

    final NavigatorState navigator = Navigator.of(context);
    final bool verPaquetes = await mostrarDialogoLimiteImagenes(context, estado);

    navigator.pop();
    if (verPaquetes) {
      navigator.push(MaterialPageRoute(builder: (_) => const PlanesPage()));
    }
  }

  // ============================================================
  // ANÁLISIS DE IMAGEN (conteo de colonias)
  //  - Rendimiento: traza personalizada "analisis_imagen".
  //  - Estabilidad: si falla, se registra en Crashlytics con la
  //    etiqueta funcionalidad = analisis_imagen.
  //  - Límite: cada imagen analizada con éxito cuenta para el
  //    límite del paquete.
  // ============================================================
  Future<void> _procesarImagen() async {
    final trace = FirebasePerformance.instance.newTrace('analisis_imagen');
    await trace.start();

    try {
      // 1) ¿Todavía le quedan imágenes en su paquete?
      final EstadoPlan estado = await PlanService.obtenerEstado();
      if (!estado.puedeSubirImagen) {
        trace.putAttribute('resultado', 'limite');
        await _bloquearPorLimite();
        return;
      }

      // 2) Conteo automático
      final resultado = await ColoniaCounter.contar(widget.imagen);

      // Guardamos la imagen marcada en un archivo temporal para poder
      // mostrarla y luego guardarla de forma permanente.
      final tempPath = '${widget.imagen.path}_marcada.jpg';
      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(resultado.imagenProcesada);

      // 3) Se descuenta la imagen del límite (transacción).
      final bool registrada = await PlanService.registrarImagenUsada();
      if (!registrada) {
        trace.putAttribute('resultado', 'limite');
        await _bloquearPorLimite();
        return;
      }

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

  // ============================================================
  // ANÁLISIS CON CLAUDE (disponible en TODOS los paquetes)
  //  - Rendimiento: traza personalizada "analisis_ia".
  //  - Estabilidad: errores inesperados van a Crashlytics.
  // ============================================================
  Future<void> _analizarConClaude() async {
    if (_analizandoIA) return;

    setState(() {
      _analizandoIA = true;
      _errorIA = null;
    });

    final trace = FirebasePerformance.instance.newTrace('analisis_ia');
    await trace.start();

    try {
      // Se envía la foto ORIGINAL (sin círculos) junto con el conteo
      // automático, para que Claude lo compare con lo que ve.
      final AnalisisIA resultado = await ClaudeService.analizarPlaca(
        widget.imagen,
        conteoLocal: _conteo,
      );

      trace.putAttribute('resultado', 'exito');
      if (!mounted) return;
      setState(() => _analisis = resultado);
    } on ClaudeException catch (e) {
      trace.putAttribute('resultado', 'error');
      if (mounted) setState(() => _errorIA = e.mensaje);
    } catch (e, st) {
      trace.putAttribute('resultado', 'error');
      if (!kIsWeb) {
        FirebaseCrashlytics.instance.setCustomKey('funcionalidad', 'analisis_ia');
        FirebaseCrashlytics.instance.recordError(
          e,
          st,
          reason: 'Error en el análisis con Claude',
        );
      }
      if (mounted) {
        setState(() => _errorIA = 'No se pudo completar el análisis con IA.');
      }
    } finally {
      await trace.stop();
      if (mounted) setState(() => _analizandoIA = false);
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
      //    El campo "imagenBase64" contiene la foto marcada y, si el
      //    usuario pidió el análisis con Claude, "analisisIA" lo guarda.
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
        if (_analisis != null) 'analisisIA': _analisis!.toMap(),
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

  // ============================================================
  // TARJETA CON EL RESULTADO DE CLAUDE
  // ============================================================
  Widget _tarjetaAnalisis(AnalisisIA a) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.tarjeta,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.auto_awesome, color: Colors.amber, size: 20),
              SizedBox(width: 8),
              Text(
                'Análisis de Claude',
                style: TextStyle(
                  color: AppColors.texto,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!a.esPlacaPetri)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Claude no reconoce esta imagen como una caja Petri. '
                'Revisa que la foto sea la correcta.',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ...a.secciones.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.key,
                    style: const TextStyle(
                      color: AppColors.textoSecundario,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.value,
                    style: const TextStyle(
                        color: AppColors.texto, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
          const Text(
            'Referencia orientativa. El conteo oficial del reporte es el '
            'automático y no sustituye el criterio del laboratorista.',
            style: TextStyle(color: AppColors.textoTenue, fontSize: 11),
          ),
        ],
      ),
    );
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

                  // ---- BOTÓN ANÁLISIS CON CLAUDE (todos los paquetes) ----
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _analizandoIA ? null : _analizarConClaude,
                      icon: _analizandoIA
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.amber),
                            )
                          : const Icon(Icons.auto_awesome,
                              color: Colors.amber, size: 20),
                      label: Text(
                        _analizandoIA
                            ? 'Claude está analizando...'
                            : (_analisis == null
                                ? 'Analizar con Claude'
                                : 'Repetir análisis con Claude'),
                        style: const TextStyle(color: AppColors.texto),
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

                  if (_errorIA != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _errorIA!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ],

                  if (_analisis != null) ...[
                    const SizedBox(height: 14),
                    _tarjetaAnalisis(_analisis!),
                  ],

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