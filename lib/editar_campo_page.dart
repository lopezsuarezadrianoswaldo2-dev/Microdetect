import 'package:bioconteo_colonias_bacterinas/app_colors.dart';
import 'package:flutter/material.dart';

class EditarCampoPage extends StatefulWidget {
  final String titulo;
  final String valorInicial;

  EditarCampoPage({required this.titulo, required this.valorInicial});

  @override
  _EditarCampoPageState createState() => _EditarCampoPageState();
}

class _EditarCampoPageState extends State<EditarCampoPage> {
  late TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.valorInicial);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fondo,

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.titulo, style: TextStyle(color: AppColors.texto)),
        iconTheme: IconThemeData(color: AppColors.texto),
      ),

      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: controller,
              style: TextStyle(color: AppColors.texto),
              decoration: InputDecoration(
                labelText: "Nuevo valor",
                labelStyle: TextStyle(color: AppColors.textoSecundario),
                filled: true,
                fillColor: AppColors.tarjeta,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),

            SizedBox(height: 20),

            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, controller.text);
              },
              child: Text("Guardar"),
            )
          ],
        ),
      ),
    );
  }
}
