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
  final String imagePath;

  DetallesPage({
    required this.fecha,
    required this.hora,
    required this.conteo,
    required this.descripcion,
    required this.imagePath,
  });

  @override
  _DetallesPageState createState() => _DetallesPageState();
}

class _DetallesPageState extends State<DetallesPage> {
  late String nombreMuestra = "Bacterias";
  late String conteo;
  late String descripcion;

  ScreenshotController screenshotController = ScreenshotController();

  @override
  void initState() {
    super.initState();
    conteo = widget.conteo;
    descripcion = widget.descripcion;
  }

  // ===============================
  // GENERAR PDF
  // ===============================
  Future<void> generarPDF() async {
    final pdf = pw.Document();

    final File imgFile = File(widget.imagePath);
    final Uint8List imgBytes = await imgFile.readAsBytes();

    pdf.addPage(
      pw.Page(
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text("Reporte de Muestra",
                  style: pw.TextStyle(
                      fontSize: 24, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 20),
              pw.Image(pw.MemoryImage(imgBytes), height: 250),
              pw.SizedBox(height: 20),
              pw.Text("Nombre de muestra: $nombreMuestra"),
              pw.Text("Fecha: ${widget.fecha}"),
              pw.Text("Hora: ${widget.hora}"),
              pw.Text("Conteo: $conteo"),
              pw.SizedBox(height: 15),
              pw.Text("Descripción:"),
              pw.Text(descripcion),
            ],
          );
        },
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File("${output.path}/reporte.pdf");
    await file.writeAsBytes(await pdf.save());

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("PDF generado: ${file.path}")),
    );
  }

  // ===============================
  // GUARDAR IMAGEN PNG
  // ===============================
  Future<void> guardarComoImagen() async {
    final Uint8List? captura = await screenshotController.capture();
    if (captura == null) return;

    final dir = await getTemporaryDirectory();
    final file = File("${dir.path}/reporte.png");
    await file.writeAsBytes(captura);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Imagen guardada: ${file.path}")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0D1B2A), // MISMO DISEÑO

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "Detalles",
          style: TextStyle(color: Colors.white, fontSize: 22),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.logout, color: Colors.white),
            onPressed: () {},
          )
        ],
      ),

      body: Screenshot(
        controller: screenshotController,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(20),
          child: Column(
            children: [
              // IMAGEN
              Container(
                height: 230,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  image: DecorationImage(
                    image: FileImage(File(widget.imagePath)),
                    fit: BoxFit.cover,
                  ),
                ),
              ),

              SizedBox(height: 20),

              // TABLA DE CAMPOS
              buildEditableRow("Nombre de muestra", nombreMuestra,
                  (nuevo) => setState(() => nombreMuestra = nuevo)),

              buildEditableRow("Fecha", widget.fecha, null),
              buildEditableRow("Hora", widget.hora, null),

              buildEditableRow(
                  "Conteo", conteo, (nuevo) => setState(() => conteo = nuevo)),

              SizedBox(height: 25),

              // DESCRIPCIÓN
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Descripción",
                    style: TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: Icon(Icons.edit, color: Colors.white),
                    onPressed: () async {
                      final nuevoValor = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => EditarCampoPage(
                            titulo: "Editar descripción",
                            valorInicial: descripcion,
                          ),
                        ),
                      );
                      if (nuevoValor != null) {
                        setState(() => descripcion = nuevoValor);
                      }
                    },
                  )
                ],
              ),

              Container(
                padding: EdgeInsets.all(12),
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Color(0xFF1B263B),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  descripcion,
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),

              SizedBox(height: 30),

              // BOTONES DE EXPORTAR
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF1B263B)),
                    icon: Icon(Icons.picture_as_pdf),
                    label: Text("PDF"),
                    onPressed: generarPDF,
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFF1B263B)),
                    icon: Icon(Icons.image),
                    label: Text("Imagen"),
                    onPressed: guardarComoImagen,
                  ),
                ],
              )
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
      String campo, String valor, Function(String)? onEdit) {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: Color(0xFF1B263B),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  "$campo: $valor",
                  style: TextStyle(color: Colors.white, fontSize: 17),
                ),
              ),
              if (onEdit != null)
                IconButton(
                  icon: Icon(Icons.edit, color: Colors.white),
                  onPressed: () async {
                    final nuevoValor = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditarCampoPage(
                          titulo: "Editar $campo",
                          valorInicial: valor,
                        ),
                      ),
                    );
                    if (nuevoValor != null) onEdit(nuevoValor);
                  },
                ),
            ],
          ),
        ),
        SizedBox(height: 12),
      ],
    );
  }
}
