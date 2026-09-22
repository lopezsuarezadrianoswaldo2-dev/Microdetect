import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:bioconteo_colonias_bacterinas/services/conexion.dart';
import 'login.dart';

class Registro extends StatefulWidget {
  @override
  _RegistroState createState() => _RegistroState();
}

class _RegistroState extends State<Registro>
  with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  final TextEditingController nombreController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();

  File? imagen;

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  // Para resaltar campos vacíos
  bool nombreVacio = false;
  bool emailVacio = false;
  bool passwordVacio = false;
  bool confirmPasswordVacio = false;

  @override
  void initState() {
    super.initState();
    _controller =
    AnimationController(vsync: this, duration: Duration(milliseconds: 900));
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _controller.forward();
  }


Future<void> seleccionarImagen() async {
  final ImagePicker picker = ImagePicker();
  final XFile? pickedFile = await picker.pickImage(source: ImageSource.gallery);
  
  if (pickedFile != null) {
    // Abrir cropper
    CroppedFile? croppedFile = await ImageCropper().cropImage(
      sourcePath: pickedFile.path,
      aspectRatio: CropAspectRatio(ratioX: 1, ratioY: 1), // cuadrado
      compressQuality: 90,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Recortar imagen',
          toolbarColor: Colors.blueAccent,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
        ),
        IOSUiSettings(
          title: 'Recortar imagen',
          aspectRatioLockEnabled: true,
        ),
      ],
    );

    if (croppedFile != null) {
      setState(() => imagen = File(croppedFile.path));
    }
  }
}

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // SnackBar centrado y visible
  void _mostrarSnackBar(String mensaje, [bool error = false]) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Center(child: Text(mensaje)),
        backgroundColor: error ? Colors.red : Colors.green,
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.symmetric(horizontal: 50, vertical: 150),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF0D1B2A),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 25),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height,
              ),
              child: IntrinsicHeight(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ScaleTransition(
                      scale: _animation,
                      child: Text(
                        'Registro',
                        style: GoogleFonts.orbitron(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 2,
                          shadows: [
                            Shadow(
                                blurRadius: 4,
                                color: Colors.black54,
                                offset: Offset(3, 3))
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 20),

                    /// FOTO DE PERFIL
                    GestureDetector(
                      onTap: seleccionarImagen,
                      child: CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.white12,
                        backgroundImage:
                            imagen != null ? FileImage(imagen!) : null,
                        child: imagen == null
                            ? Icon(Icons.camera_alt,
                                color: Colors.white70, size: 40)
                            : null,
                      ),
                    ),
                    SizedBox(height: 30),

                    /// NOMBRE COMPLETO
                    TextFormField(
                      controller: nombreController,
                      style: TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Nombre completo',
                        labelStyle: TextStyle(color: Colors.white70),
                        prefixIcon: Icon(Icons.person, color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        errorText: nombreVacio ? 'Campo obligatorio' : null,
                      ),
                    ),
                    SizedBox(height: 20),

                    /// CORREO ELECTRÓNICO
                    TextFormField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Correo electrónico',
                        labelStyle: TextStyle(color: Colors.white70),
                        prefixIcon: Icon(Icons.email, color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        errorText: emailVacio ? 'Campo obligatorio' : null,
                      ),
                    ),
                    SizedBox(height: 20),

                    /// CONTRASEÑA
                    TextFormField(
                      controller: passwordController,
                      obscureText: _obscurePassword,
                      style: TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        labelStyle: TextStyle(color: Colors.white70),
                        prefixIcon: Icon(Icons.lock, color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        errorText: passwordVacio ? 'Campo obligatorio' : null,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: Colors.white70,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                    ),
                    SizedBox(height: 20),

                    /// CONFIRMAR CONTRASEÑA
                    TextFormField(
                      controller: confirmPasswordController,
                      obscureText: _obscureConfirmPassword,
                      style: TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Confirmar contraseña',
                        labelStyle: TextStyle(color: Colors.white70),
                        prefixIcon: Icon(Icons.lock, color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white10,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        errorText:
                            confirmPasswordVacio ? 'Campo obligatorio' : null,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirmPassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: Colors.white70,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscureConfirmPassword =
                                  !_obscureConfirmPassword;
                            });
                          },
                        ),
                      ),
                    ),
                    SizedBox(height: 30),

                    /// BOTÓN DE REGISTRO
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          padding: EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          setState(() {
                            nombreVacio = nombreController.text.trim().isEmpty;
                            emailVacio = emailController.text.trim().isEmpty;
                            passwordVacio = passwordController.text.trim().isEmpty;
                            confirmPasswordVacio =
                                confirmPasswordController.text.trim().isEmpty;
                          });

                          // Campos vacíos
                          if (nombreVacio ||
                              emailVacio ||
                              passwordVacio ||
                              confirmPasswordVacio) {
                            _mostrarSnackBar(
                                "Por favor, completa todos los campos", true);
                            return;
                          }

                          // Contraseñas no coinciden
                          if (passwordController.text !=
                              confirmPasswordController.text) {
                            _mostrarSnackBar(
                                "Las contraseñas no coinciden", true);
                            return;
                          }

                          // Longitud mínima contraseña
                          if (passwordController.text.length < 6) {
                            _mostrarSnackBar(
                                "La contraseña debe tener al menos 6 caracteres",
                                true);
                            return;
                          }

                          // Crear cuenta
                          final resultado = await createAccount(
                            fullName: nombreController.text.trim(),
                            email: emailController.text.trim(),
                            password: passwordController.text.trim(),
                            profileImage: imagen,
                          );

                          if (!context.mounted) return;

                          if (resultado == "ok") {
                            _mostrarSnackBar("Cuenta creada correctamente");
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (_) => Login()),
                              (route) => false,
                            );
                          } else if (resultado == "correo_existente") {
                            _mostrarSnackBar("El correo ya está registrado", true);
                          } else if (resultado == "password_invalida") {
                            _mostrarSnackBar("Contraseña inválida", true);
                          } else {
                            _mostrarSnackBar("Error al crear la cuenta", true);
                          }
                        },
                        child:
                            Text('Registrarse', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                    SizedBox(height: 20),

                    /// VOLVER A LOGIN
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Text(
                        'Volver al inicio de sesión',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
