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
      backgroundColor: Color(0xFF0D1B2A),

      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.titulo, style: TextStyle(color: Colors.white)),
        iconTheme: IconThemeData(color: Colors.white),
      ),

      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: controller,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "Nuevo valor",
                labelStyle: TextStyle(color: Colors.white70),
                filled: true,
                fillColor: Color(0xFF1B263B),
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
