import 'package:bioconteo_colonias_bacterinas/app_colors.dart';
import 'package:bioconteo_colonias_bacterinas/home_panel.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'registro.dart';

class Login extends StatefulWidget {
  @override
  _LoginState createState() => _LoginState();
}

class _LoginState extends State<Login> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool isLoading = false;
   bool _obscurePassword = true;


  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 900),
    );

    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // 🔵 LOGIN CON FIREBASE
  Future<User?> logIn(String email, String password) async {
    FirebaseAuth auth = FirebaseAuth.instance;

    try {
      UserCredential userCredential = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return userCredential.user;
    } catch (e) {
      print("Error: $e");
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fondo,
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
              child: Column(
                children: [
                  Image.asset(
                    'assets/images/micro.png',
                    width: 200,
                    height: 200,
                    // Funde el fondo del logo con el fondo de la app (quítalo si tu logo ya es PNG transparente)
                    color: AppColors.fondo,
                    colorBlendMode: BlendMode.darken,
                  ),
                  SizedBox(height: 8),
                  Text(
                    '¡Bienvenidos!',
                    style: TextStyle(fontSize: 20, color: AppColors.textoSecundario),
                  ),
                ],
              ),
            ),

            SizedBox(height: 40),

            // 🔵 CAMPO CORREO
            TextFormField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(color: AppColors.texto),
              decoration: InputDecoration(
                labelText: 'Correo electrónico',
                labelStyle: TextStyle(color: AppColors.textoSecundario),
                prefixIcon: Icon(Icons.email, color: AppColors.textoSecundario),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),

            SizedBox(height: 20),

       TextFormField(
                      controller: passwordController,
                      obscureText: _obscurePassword,
                      style: TextStyle(color: AppColors.texto),
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        labelStyle: TextStyle(color: AppColors.textoSecundario),
                        prefixIcon:
                            Icon(Icons.lock, color: AppColors.textoSecundario),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),

                        // ✅ ICONO OJO
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility
                                : Icons.visibility_off,
                            color: AppColors.textoSecundario,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                    ),

                    SizedBox(height: 30),

            // 🔵 BOTÓN ACCEDER
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 15),
                ),
                onPressed: () async {
                  setState(() => isLoading = true);

                  final user = await logIn(
                    emailController.text.trim(),
                    passwordController.text.trim(),
                  );

                  setState(() => isLoading = false);

                  if (user != null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Sesión iniciada correctamente")),
                    );

                    // 🔵 CORRECCIÓN IMPORTANTE AQUÍ
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => HomePanel()),
                      );
                    });
                    

                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Error al iniciar sesión")),
                    );
                  }
                },
                child: isLoading
                    ? CircularProgressIndicator(color: Colors.white)
                    : Text('Acceder', style: TextStyle(fontSize: 18)),
              ),
            ),

            SizedBox(height: 20),

            // 🔵 IR A REGISTRO
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => Registro()),
                );
              },
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    color: AppColors.textoSecundario,
                    fontSize: 16,
                  ),
                  children: [
                    TextSpan(text: '¿Aún no tienes cuenta? '),
                    TextSpan(
                      text: 'Regístrate aquí',
                      style: TextStyle(
                        color: AppColors.primario,
                        fontWeight: FontWeight.bold,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
                    ),
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