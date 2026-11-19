import 'package:bioconteo_colonias_bacterinas/app_colors.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'editar_campo_page.dart';
import 'planes_page.dart';
import 'services/claude_service.dart';
import 'services/plan_service.dart';

class DetallesPage extends StatefulWidget {
  /// ID del documento del reporte en Firestore (colección "reportes").
  /// Se usa para guardar los cambios que el usuario edite.
  final String docId;

  /// Nombre de muestra guardado en el reporte (si ya se había editado).
  final String nombreMuestra;

  final String fecha;
  final String hora;
  final String conteo;
  final String descripcion;

  /// Foto guardada dentro del reporte en Firestore (texto base64).
  final String imagenBase64;

  /// Ruta local de la foto (solo reportes viejos). Puede venir vacía.
  final String imagePath;

  /// Análisis de Claude guardado en el reporte (puede ser null).
  final Map<String, dynamic>? analisisIA;

  const DetallesPage({
    super.key,
    required this.docId,
    this.nombreMuestra = 'Bacterias',
    required this.fecha,
    required this.hora,
    required this.conteo,
    required this.descripcion,
    required this.imagePath,
    this.imagenBase64 = '',
    this.analisisIA,
  });

  @override
  State<DetallesPage> createState() => _DetallesPageState();
}

class _DetallesPageState extends State<DetallesPage> {
  late String nombreMuestra;
  late String conteo;
  late String descripcion;

  Uint8List? _bytes;
  AnalisisIA? _analisisIA;

  // Plan del usuario (solo para mostrar el aviso en pantalla; al exportar
  // se vuelve a consultar para no depender de este valor).
  AppPlan _plan = AppPlan.basico;
  bool _exportando = false;

  bool get _hayLocal =>
      widget.imagePath.isNotEmpty && File(widget.imagePath).existsSync();

  bool get _hayImagen => _bytes != null || _hayLocal;

  ImageProvider? get _proveedorImagen {
    if (_bytes != null) return MemoryImage(_bytes!);
    if (_hayLocal) return FileImage(File(widget.imagePath));
    return null;
  }

  @override
  void initState() {
    super.initState();
    nombreMuestra = widget.nombreMuestra.trim().isEmpty
        ? 'Bacterias'
        : widget.nombreMuestra;
    conteo = widget.conteo;
    descripcion = widget.descripcion;

    if (widget.imagenBase64.isNotEmpty) {
      try {
        _bytes = base64Decode(widget.imagenBase64);
      } catch (_) {
        _bytes = null;
      }
    }

    if (widget.analisisIA != null) {
      _analisisIA = AnalisisIA.fromMap(widget.analisisIA!);
    }

    _cargarPlan();
  }

  Future<void> _cargarPlan() async {
    final AppPlan plan = await PlanService.obtenerPlanActual();
    if (mounted) setState(() => _plan = plan);
  }

  void _mensaje(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto)),
    );
  }

  /// Guarda un campo editado en el reporte de Firestore.
  /// Devuelve true si se guardó. Si falla, avisa al usuario.
  Future<bool> _guardarCampo(String campo, String valor) async {
    if (widget.docId.isEmpty) {
      _mensaje('No se pudo guardar: el reporte no tiene identificador.');
      return false;
    }
    try {
      await FirebaseFirestore.instance
          .collection('reportes')
          .doc(widget.docId)
          .update({
        campo: valor,
        'editado': FieldValue.serverTimestamp(),
      }).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception(
            'Tiempo agotado. Revisa tu internet y las reglas de Firestore.'),
      );
      _mensaje('Cambios guardados ✅');
      return true;
    } catch (e) {
      _mensaje('No se pudieron guardar los cambios: $e');
      return false;
    }
  }

  Future<Uint8List?> _bytesImagen() async {
    if (_bytes != null) return _bytes;
    if (_hayLocal) return File(widget.imagePath).readAsBytes();
    return null;
  }

  String _nombreArchivo() {
    final String base = 'reporte_${widget.fecha}_${widget.hora}';
    return base.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '-');
  }

  /// El PDF usa fuentes estándar que solo soportan caracteres Latin-1
  /// (acentos y ñ sí). Se limpian símbolos raros y emojis para que el PDF
  /// no salga con huecos.
  String _limpiarPdf(String texto) {
    return texto
        .replaceAll(RegExp(r'[\u2013\u2014]'), '-')
        .replaceAll(RegExp(r'[\u2018\u2019]'), "'")
        .replaceAll(RegExp(r'[\u201C\u201D]'), '"')
        .replaceAll('\u2248', '~')
        .replaceAll('\u2026', '...')
        .replaceAll(RegExp(r'[^\u0000-\u00FF]'), '');
  }

  // ============================================================
  // CONSTRUCCIÓN DEL REPORTE (PDF)
  //
  // Es la MISMA hoja para el PDF y para la imagen: la imagen se
  // obtiene convirtiendo esta hoja, así que se ven idénticas.
  // El diseño imita la pantalla del celular y ocupa toda la hoja.
  // Si el plan no es Premium, se agrega el logo como marca de agua
  // en la parte inferior de cada hoja.
  // ============================================================
  Future<Uint8List> _construirPdf({required bool conMarca}) async {
    final Uint8List? fotoBytes = await _bytesImagen();
    final AnalisisIA? ia = _analisisIA;

    // Logo del proyecto
    final ByteData logoData = await rootBundle.load('assets/images/micro.png');
    final Uint8List logoBytes = logoData.buffer.asUint8List();

    // El fondo de la hoja toma el color de fondo del propio logo para
    // que la marca de agua se funda con la hoja, sin recuadro.
    PdfColor colorFondo = const PdfColor.fromInt(0xFFEAF4FF);
    try {
      final img.Image? logoImg = img.decodeImage(logoBytes);
      if (logoImg != null) {
        final img.Pixel px = logoImg.getPixel(3, 3);
        colorFondo = PdfColor(px.r / 255.0, px.g / 255.0, px.b / 255.0);
      }
    } catch (_) {
      // Se queda con el color de fondo de la app.
    }

    const PdfColor colorTexto = PdfColor.fromInt(0xFF0D1B2A);
    const PdfColor colorSecundario = PdfColor.fromInt(0xFF415A77);

    // Alto de la foto: más grande cuando no hay marca de agua, para que
    // la hoja siempre quede llena.
    final double altoFoto = conMarca ? 300 : 370;

    pw.Widget fila(String campo, String valor) {
      return pw.Container(
        width: double.infinity,
        margin: const pw.EdgeInsets.only(bottom: 10),
        padding: const pw.EdgeInsets.symmetric(vertical: 13, horizontal: 12),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(10),
        ),
        child: pw.Text(
          '$campo: ${_limpiarPdf(valor)}',
          style: const pw.TextStyle(fontSize: 15, color: colorTexto),
        ),
      );
    }

    final pw.Document pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(30),
          buildBackground: (pw.Context context) => pw.FullPage(
            ignoreMargins: true,
            child: pw.Container(color: colorFondo),
          ),
        ),
        build: (pw.Context context) => [
          pw.Center(
            child: pw.Text(
              'Detalles',
              style: pw.TextStyle(
                fontSize: 26,
                fontWeight: pw.FontWeight.bold,
                color: colorTexto,
              ),
            ),
          ),
          pw.SizedBox(height: 16),

          // Foto
          if (fotoBytes != null)
            pw.Container(
              width: double.infinity,
              height: altoFoto,
              decoration: pw.BoxDecoration(
                borderRadius: pw.BorderRadius.circular(14),
                image: pw.DecorationImage(
                  image: pw.MemoryImage(fotoBytes),
                  fit: pw.BoxFit.cover,
                ),
              ),
            )
          else
            pw.Container(
              width: double.infinity,
              height: altoFoto,
              alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: pw.BorderRadius.circular(14),
              ),
              child: pw.Text(
                'La foto ya no esta disponible',
                style: const pw.TextStyle(fontSize: 14, color: colorSecundario),
              ),
            ),
          pw.SizedBox(height: 18),

          // Campos
          fila('Nombre de muestra', nombreMuestra),
          fila('Fecha', widget.fecha),
          fila('Hora', widget.hora),
          fila('Conteo', conteo),
          pw.SizedBox(height: 10),

          // Descripción
          pw.Text(
            'Descripcion',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: colorTexto,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Container(
            width: double.infinity,
            constraints: const pw.BoxConstraints(minHeight: 70),
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Text(
              _limpiarPdf(descripcion),
              style: const pw.TextStyle(fontSize: 14, color: colorTexto),
            ),
          ),

          // Análisis de Claude (si el reporte lo tiene)
          if (ia != null) ...[
            pw.SizedBox(height: 18),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.white,
                borderRadius: pw.BorderRadius.circular(10),
                border: pw.Border.all(color: PdfColors.amber, width: 1),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Analisis de Claude',
                    style: pw.TextStyle(
                      fontSize: 15,
                      fontWeight: pw.FontWeight.bold,
                      color: colorTexto,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  ...ia.secciones.map(
                    (s) => pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 7),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            _limpiarPdf(s.key),
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              color: colorSecundario,
                            ),
                          ),
                          pw.Text(
                            _limpiarPdf(s.value),
                            style: const pw.TextStyle(
                                fontSize: 11, color: colorTexto),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
        // Marca de agua: logo del proyecto al pie de CADA hoja.
        footer: conMarca
            ? (pw.Context context) => pw.Center(
                  child: pw.Opacity(
                    opacity: 0.6,
                    child: pw.Image(pw.MemoryImage(logoBytes), height: 64),
                  ),
                )
            : null,
      ),
    );

    return pdf.save();
  }

  // ===============================
  // DESCARGAR PDF
  // ===============================
  Future<void> generarPDF() async {
    if (_exportando) return;
    setState(() => _exportando = true);

    try {
      // Se consulta el plan en este momento (incluye la prueba Premium).
      final AppPlan plan = await PlanService.obtenerPlanActual();
      final bool conMarca = PlanService.tieneMarcaDeAgua(plan);

      final Uint8List pdfBytes = await _construirPdf(conMarca: conMarca);

      // Abre el menú del teléfono para guardar o compartir el PDF
      // (Drive, Archivos, WhatsApp, etc.).
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: '${_nombreArchivo()}.pdf',
      );
    } catch (e) {
      _mensaje('No se pudo generar el PDF: $e');
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  // ===============================
  // DESCARGAR IMAGEN (se guarda en la galería, álbum MicroDetect)
  // ===============================
  Future<void> guardarComoImagen() async {
    if (_exportando) return;
    setState(() => _exportando = true);

    try {
      final AppPlan plan = await PlanService.obtenerPlanActual();
      final bool conMarca = PlanService.tieneMarcaDeAgua(plan);

      // Permiso para guardar en la galería
      if (!await Gal.hasAccess(toAlbum: true)) {
        final bool concedido = await Gal.requestAccess(toAlbum: true);
        if (!concedido) {
          _mensaje('Se necesita permiso para guardar la imagen en la galería.');
          return;
        }
      }

      // Misma hoja del PDF, convertida a imagen.
      final Uint8List pdfBytes = await _construirPdf(conMarca: conMarca);
      final Directory temporal = await getTemporaryDirectory();

      int guardadas = 0;
      await for (final pagina in Printing.raster(pdfBytes, dpi: 150)) {
        final Uint8List png = await pagina.toPng();

        final File archivo = File(
          '${temporal.path}/${_nombreArchivo()}_${guardadas + 1}.png',
        );
        await archivo.writeAsBytes(png);

        await Gal.putImage(archivo.path, album: 'MicroDetect');
        guardadas++;
      }

      if (guardadas == 0) {
        _mensaje('No se pudo generar la imagen.');
        return;
      }

      _mensaje(guardadas == 1
          ? 'Imagen guardada en la galería ✅'
          : '$guardadas imágenes guardadas en la galería ✅');
    } catch (e) {
      _mensaje('No se pudo guardar la imagen: $e');
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Widget _bloqueAnalisis(AnalisisIA ia) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.tarjeta,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.auto_awesome, color: Colors.amber, size: 18),
              SizedBox(width: 6),
              Text(
                'Análisis de Claude',
                style: TextStyle(
                  color: AppColors.texto,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...ia.secciones.map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
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
                  Text(
                    s.value,
                    style: const TextStyle(
                        color: AppColors.texto, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool mostrarAvisoMarca = PlanService.tieneMarcaDeAgua(_plan);

    return Scaffold(
      backgroundColor: AppColors.fondo,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.texto),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.texto),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Detalles',
          style: TextStyle(color: AppColors.texto, fontSize: 22),
        ),
      ),
      body: Container(
        color: AppColors.fondo,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // IMAGEN (o un marcador si la foto ya no existe)
              if (_hayImagen)
                Container(
                  height: 230,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    image: DecorationImage(
                      image: _proveedorImagen!,
                      fit: BoxFit.cover,
                    ),
                  ),
                )
              else
                Container(
                  height: 230,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.tarjeta,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.image_not_supported,
                          color: AppColors.textoTenue, size: 48),
                      SizedBox(height: 10),
                      Text(
                        'La foto ya no está disponible',
                        style: TextStyle(color: AppColors.textoSecundario),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 20),

              // TABLA DE CAMPOS
              buildEditableRow(
                'Nombre de muestra',
                nombreMuestra,
                (nuevo) async {
                  final String anterior = nombreMuestra;
                  final String limpio = nuevo.trim();
                  if (limpio.isEmpty || limpio == anterior) return;
                  setState(() => nombreMuestra = limpio);
                  final bool ok = await _guardarCampo('nombreMuestra', limpio);
                  if (!ok && mounted) setState(() => nombreMuestra = anterior);
                },
              ),
              buildEditableRow('Fecha', widget.fecha, null),
              buildEditableRow('Hora', widget.hora, null),
              // El conteo lo calcula la app: no se puede editar.
              buildEditableRow('Conteo', conteo, null),

              const SizedBox(height: 25),

              // DESCRIPCIÓN
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Descripción',
                    style: TextStyle(
                      fontSize: 18,
                      color: AppColors.texto,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, color: AppColors.texto),
                    onPressed: () async {
                      final nuevoValor = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditarCampoPage(
                            titulo: 'Editar descripción',
                            valorInicial: descripcion,
                          ),
                        ),
                      );
                      if (nuevoValor != null && mounted) {
                        final String anterior = descripcion;
                        final String limpio = nuevoValor.trim();
                        if (limpio == anterior) return;
                        setState(() => descripcion = limpio);
                        final bool ok =
                            await _guardarCampo('descripcion', limpio);
                        if (!ok && mounted) {
                          setState(() => descripcion = anterior);
                        }
                      }
                    },
                  ),
                ],
              ),

              Container(
                padding: const EdgeInsets.all(12),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.tarjeta,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  descripcion,
                  style: const TextStyle(color: AppColors.texto, fontSize: 16),
                ),
              ),

              if (_analisisIA != null) ...[
                const SizedBox(height: 20),
                _bloqueAnalisis(_analisisIA!),
              ],

              const SizedBox(height: 30),

              // BOTONES DE EXPORTAR
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('PDF'),
                    onPressed: _exportando ? null : generarPDF,
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.image),
                    label: const Text('Imagen'),
                    onPressed: _exportando ? null : guardarComoImagen,
                  ),
                ],
              ),

              if (_exportando) ...[
                const SizedBox(height: 16),
                const CircularProgressIndicator(),
              ],

              // Aviso de marca de agua (solo si el plan no es Premium)
              if (mostrarAvisoMarca) ...[
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.water_drop,
                        size: 16, color: AppColors.textoTenue),
                    const SizedBox(width: 6),
                    const Flexible(
                      child: Text(
                        'Tus exportaciones llevan marca de agua.',
                        style: TextStyle(
                            color: AppColors.textoSecundario, fontSize: 13),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PlanesPage()),
                      ),
                      child: const Text('Quitarla'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ======================================
  // FILA EDITABLE OSCURA (MISMO DISEÑO)
  // ======================================
  Widget buildEditableRow(
    String campo,
    String valor,
    Future<void> Function(String)? onEdit,
  ) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: AppColors.tarjeta,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  '$campo: $valor',
                  style: const TextStyle(color: AppColors.texto, fontSize: 17),
                ),
              ),
              if (onEdit != null)
                IconButton(
                  icon: const Icon(Icons.edit, color: AppColors.texto),
                  onPressed: () async {
                    final nuevoValor = await Navigator.push<String>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditarCampoPage(
                          titulo: 'Editar $campo',
                          valorInicial: valor,
                        ),
                      ),
                    );
                    if (nuevoValor != null && mounted) await onEdit(nuevoValor);
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}