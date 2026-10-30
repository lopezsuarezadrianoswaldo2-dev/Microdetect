import 'package:bioconteo_colonias_bacterinas/app_colors.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:screenshot/screenshot.dart';
import 'editar_campo_page.dart';

class DetallesPage extends StatefulWidget {
  final String fecha;
  final String hora;
  final String conteo;
  final String descripcion;

  /// Foto guardada dentro del reporte en Firestore (texto base64).
  final String imagenBase64;

  /// Ruta local de la foto (solo reportes viejos). Puede venir vacía.
  final String imagePath;

  const DetallesPage({
    super.key,
    required this.fecha,
    required this.hora,
    required this.conteo,
    required this.descripcion,
    required this.imagePath,
    this.imagenBase64 = '',
  });

  @override
  State<DetallesPage> createState() => _DetallesPageState();
}

class _DetallesPageState extends State<DetallesPage> {
  String nombreMuestra = 'Bacterias';
  late String conteo;
  late String descripcion;

  final ScreenshotController screenshotController = ScreenshotController();

  Uint8List? _bytes;

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
    conteo = widget.conteo;
    descripcion = widget.descripcion;

    if (widget.imagenBase64.isNotEmpty) {
      try {
        _bytes = base64Decode(widget.imagenBase64);
      } catch (_) {
        _bytes = null;
      }
    }
  }

  void _mensaje(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto)),
    );
  }

  // ===============================
  // GENERAR PDF
  // ===============================
  Future<void> generarPDF() async {
    try {
      final pdf = pw.Document();

      Uint8List? bytesImagen = _bytes;
      if (bytesImagen == null && _hayLocal) {
        bytesImagen = await File(widget.imagePath).readAsBytes();
      }
      final Uint8List? imgBytes = bytesImagen;

      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Reporte de Muestra',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 20),
                if (imgBytes != null) ...[
                  pw.Image(pw.MemoryImage(imgBytes), height: 250),
                  pw.SizedBox(height: 20),
                ],
                pw.Text('Nombre de muestra: $nombreMuestra'),
                pw.Text('Fecha: ${widget.fecha}'),
                pw.Text('Hora: ${widget.hora}'),
                pw.Text('Conteo: $conteo'),
                pw.SizedBox(height: 15),
                pw.Text('Descripción:'),
                pw.Text(descripcion),
              ],
            );
          },
        ),
      );

      final output = await getTemporaryDirectory();
      final file = File('${output.path}/reporte.pdf');
      await file.writeAsBytes(await pdf.save());

      _mensaje('PDF generado: ${file.path}');
    } catch (e) {
      _mensaje('No se pudo generar el PDF: $e');
    }
  }

  // ===============================
  // GUARDAR IMAGEN PNG
  // ===============================
  Future<void> guardarComoImagen() async {
    try {
      final Uint8List? captura = await screenshotController.capture();
      if (captura == null) return;

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/reporte.png');
      await file.writeAsBytes(captura);

      _mensaje('Imagen guardada: ${file.path}');
    } catch (e) {
      _mensaje('No se pudo guardar la imagen: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
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
      body: Screenshot(
        controller: screenshotController,
        child: Container(
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
                  (nuevo) => setState(() => nombreMuestra = nuevo),
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
                          setState(() => descripcion = nuevoValor);
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

                const SizedBox(height: 30),

                // BOTONES DE EXPORTAR
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('PDF'),
                      onPressed: generarPDF,
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.image),
                      label: const Text('Imagen'),
                      onPressed: guardarComoImagen,
                    ),
                  ],
                ),
              ],
            ),
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
    void Function(String)? onEdit,
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
                    if (nuevoValor != null && mounted) onEdit(nuevoValor);
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