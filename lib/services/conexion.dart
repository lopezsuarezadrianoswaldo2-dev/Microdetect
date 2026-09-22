import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

Future<String> createAccount({
  required String fullName,
  required String email,
  required String password,
  File? profileImage,
}) async {
  try {
    // 1️⃣ Crear usuario en Auth
    UserCredential cred = await FirebaseAuth.instance
        .createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    User user = cred.user!;
    String fotoUrl = '';

    // 2️⃣ Subir imagen a Storage (SI existe)
    if (profileImage != null) {
      Reference ref = FirebaseStorage.instance
          .ref('usuarios/${user.uid}/perfil.jpg');

      await ref.putFile(profileImage);
      fotoUrl = await ref.getDownloadURL();
    }

    // 3️⃣ Guardar datos en Firestore
    await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(user.uid)
        .set({
      'nombre': fullName,
      'email': email,
      'fotoUrl': fotoUrl,
      'creado': FieldValue.serverTimestamp(),
      'actualizado': FieldValue.serverTimestamp(),
    });

    return "ok"; // Todo salió bien
  } on FirebaseAuthException catch (e) {
    if (e.code == 'email-already-in-use') {
      return "correo_existente";
    } else if (e.code == 'weak-password') {
      return "password_invalida";
    } else {
      return "error";
    }
  } catch (e) {
    print('Error al crear cuenta: $e');
    return "error";
  }
}
