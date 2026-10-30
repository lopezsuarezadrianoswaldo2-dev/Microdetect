import 'package:bioconteo_colonias_bacterinas/app_colors.dart';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'services/plan_service.dart';
import 'planes_page.dart';

class Perfil extends StatefulWidget {
  const Perfil({Key? key}) : super(key: key);

  @override
  State<Perfil> createState() => _PerfilState();
}

class _PerfilState extends State<Perfil> {
  File? _imageFile;
  final ImagePicker _picker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('usuarios')
            .doc(uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;

final ImageProvider? profileImage = _imageFile != null
    ? FileImage(_imageFile!) as ImageProvider
    : (data['fotoUrl'] != null &&
            data['fotoUrl'].toString().isNotEmpty)
        ? NetworkImage(data['fotoUrl']) as ImageProvider
        : null;


          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  /// FOTO + ICONO EDITAR
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      GestureDetector(
                        onTap: () =>
                            _verFotoEnGrande(profileImage),
                        child: CircleAvatar(
                          radius: 65,
                          backgroundImage: profileImage,
                          child: profileImage == null
                              ? const Icon(Icons.person, size: 50)
                              : null,
                        ),
                      ),

                      /// ICONO CAMBIAR FOTO
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: GestureDetector(
                          onTap: () =>
                              _confirmarCambioFoto(uid),
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: AppColors.primario,
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 30),

                  /// NOMBRE
                  Text(
                    data['nombre'] ?? '',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 8),

                  /// EMAIL
                  Text(
                    data['email'] ?? '',
                    style: const TextStyle(fontSize: 16),
                  ),

                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 12),

                  /// MI PAQUETE ACTUAL
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.workspace_premium,
                        color: Colors.amber),
                    title: const Text('Mi paquete'),
                    subtitle: Text(
                      PlanService.fromId(data['plan'] as String?).nombre,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const PlanesPage()),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ===========================
  // 👁 VER FOTO EN GRANDE
  // ===========================
  void _verFotoEnGrande(ImageProvider? image) {
    if (image == null) return;

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                child: Image(image: image),
              ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close,
                    color: AppColors.texto, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            )
          ],
        ),
      ),
    );
  }

  // ===========================
  // 🔔 CONFIRMAR CAMBIO FOTO
  // ===========================
  void _confirmarCambioFoto(String uid) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cambiar foto de perfil'),
        content: const Text(
            '¿Deseas cambiar tu foto de perfil?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _seleccionarYRecortarImagen(uid);
            },
            child: const Text('Cambiar'),
          ),
        ],
      ),
    );
  }

  // ===========================
  // 📸 SELECCIONAR + RECORTAR
  // ===========================
  Future<void> _seleccionarYRecortarImagen(String uid) async {
    try {
      final XFile? picked =
          await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      final CroppedFile? cropped =
          await ImageCropper().cropImage(
        sourcePath: picked.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Ajustar imagen',
            toolbarColor: AppColors.primario,
            toolbarWidgetColor: Colors.white,
            lockAspectRatio: false,
          ),
          IOSUiSettings(title: 'Ajustar imagen'),
        ],
      );

      if (cropped == null) return;

      setState(() {
        _imageFile = File(cropped.path);
      });

      await _subirImagenFirebase(uid);
    } catch (e) {
      debugPrint('Error imagen: $e');
    }
  }

  // ===========================
  // ☁️ SUBIR A FIREBASE
  // ===========================
  Future<void> _subirImagenFirebase(String uid) async {
    final ref = FirebaseStorage.instance
        .ref()
        .child('usuarios')
        .child(uid)
        .child('perfil.jpg');

    await ref.putFile(_imageFile!);
    final url = await ref.getDownloadURL();

    await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .update({
      'fotoUrl': url,
      'actualizado': FieldValue.serverTimestamp(),
    });
  }
}