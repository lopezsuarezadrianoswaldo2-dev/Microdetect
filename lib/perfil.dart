import 'package:bioconteo_colonias_bacterinas/app_colors.dart';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'planes_page.dart';
import 'services/plan_service.dart';

/// Reduce la foto de perfil para guardarla dentro del documento del
/// usuario en Firestore (igual que las fotos de los reportes).
/// Va en otro hilo para no congelar la pantalla.
Uint8List _prepararFotoPerfil(Uint8List bytes) {
  final img.Image? original = img.decodeImage(bytes);
  if (original == null) {
    throw Exception('No se pudo leer la imagen.');
  }

  img.Image imagen = img.bakeOrientation(original);
  if (imagen.width > 400) {
    imagen = img.copyResize(imagen, width: 400);
  }

  Uint8List resultado = Uint8List.fromList(img.encodeJpg(imagen, quality: 80));
  if (resultado.length > 200000) {
    resultado = Uint8List.fromList(img.encodeJpg(imagen, quality: 60));
  }
  return resultado;
}

class Perfil extends StatefulWidget {
  const Perfil({Key? key}) : super(key: key);

  @override
  State<Perfil> createState() => _PerfilState();
}

class _PerfilState extends State<Perfil> {
  final ImagePicker _picker = ImagePicker();
  final String _uid = FirebaseAuth.instance.currentUser!.uid;

  // Campos que se guardan con el botón "Guardar cambios"
  final TextEditingController _nombreCtrl = TextEditingController();
  final TextEditingController _telefonoCtrl = TextEditingController();
  final TextEditingController _fechaCtrl = TextEditingController();
  final TextEditingController _ciudadCtrl = TextEditingController();
  final TextEditingController _institucionCtrl = TextEditingController();

  // Cambio de correo
  final TextEditingController _correoNuevoCtrl = TextEditingController();
  final TextEditingController _correoPassCtrl = TextEditingController();

  // Cambio de contraseña
  final TextEditingController _passActualCtrl = TextEditingController();
  final TextEditingController _passNuevaCtrl = TextEditingController();
  final TextEditingController _passConfirmarCtrl = TextEditingController();

  bool _cargando = true;
  bool _guardando = false;
  bool _subiendoFoto = false;
  bool _cambiandoCorreo = false;
  bool _cambiandoPass = false;
  bool _verPass = false;

  String _correoActual = '';
  Uint8List? _fotoBytes;
  String _fotoUrl = '';

  // Qué secciones están abiertas
  final Map<String, bool> _abierto = {
    'correo': false,
    'password': false,
    'datos': false,
  };

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _telefonoCtrl.dispose();
    _fechaCtrl.dispose();
    _ciudadCtrl.dispose();
    _institucionCtrl.dispose();
    _correoNuevoCtrl.dispose();
    _correoPassCtrl.dispose();
    _passActualCtrl.dispose();
    _passNuevaCtrl.dispose();
    _passConfirmarCtrl.dispose();
    super.dispose();
  }

  void _mensaje(String texto, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: error ? Colors.red : null,
      ),
    );
  }

  // ============================================================
  // CARGAR DATOS DEL USUARIO
  // ============================================================
  Future<void> _cargar() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(_uid)
          .get();
      final Map<String, dynamic> data = doc.data() ?? <String, dynamic>{};

      _nombreCtrl.text = (data['nombre'] ?? '').toString();
      _telefonoCtrl.text = (data['telefono'] ?? '').toString();
      _fechaCtrl.text = (data['fechaNacimiento'] ?? '').toString();
      _ciudadCtrl.text = (data['ciudad'] ?? '').toString();
      _institucionCtrl.text = (data['institucion'] ?? '').toString();

      final String b64 = (data['fotoBase64'] ?? '').toString();
      if (b64.isNotEmpty) {
        try {
          _fotoBytes = base64Decode(b64);
        } catch (_) {
          _fotoBytes = null;
        }
      }
      _fotoUrl = (data['fotoUrl'] ?? '').toString();

      _correoActual = FirebaseAuth.instance.currentUser?.email ??
          (data['email'] ?? '').toString();
    } catch (e) {
      _mensaje('No se pudo cargar tu perfil: $e', error: true);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  ImageProvider? get _fotoProvider {
    if (_fotoBytes != null) return MemoryImage(_fotoBytes!);
    if (_fotoUrl.isNotEmpty) return NetworkImage(_fotoUrl);
    return null;
  }

  // ============================================================
  // GUARDAR CAMBIOS (nombre, teléfono y datos personales)
  // ============================================================
  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();

    final String nombre = _nombreCtrl.text.trim();
    if (nombre.isEmpty) {
      _mensaje('Escribe tu nombre de usuario.', error: true);
      return;
    }

    final String telefono = _telefonoCtrl.text.trim();
    final String digitos = telefono.replaceAll(RegExp(r'[^0-9]'), '');
    if (telefono.isNotEmpty && (digitos.length < 10 || digitos.length > 15)) {
      _mensaje('El teléfono debe tener entre 10 y 15 dígitos.', error: true);
      return;
    }

    setState(() => _guardando = true);

    try {
      await FirebaseFirestore.instance.collection('usuarios').doc(_uid).set(
        {
          'nombre': nombre,
          'telefono': telefono,
          'fechaNacimiento': _fechaCtrl.text.trim(),
          'ciudad': _ciudadCtrl.text.trim(),
          'institucion': _institucionCtrl.text.trim(),
          'actualizado': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception(
            'Tiempo agotado. Revisa tu conexión a internet.'),
      );

      _mensaje('Cambios guardados ✅');
    } catch (e) {
      _mensaje('No se pudieron guardar los cambios: $e', error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  // ============================================================
  // CORREO Y CONTRASEÑA (requieren confirmar con la contraseña actual)
  // ============================================================
  Future<void> _reautenticar(String password) async {
    final User user = FirebaseAuth.instance.currentUser!;
    final String? email = user.email;
    if (email == null) {
      throw FirebaseAuthException(code: 'no-email');
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: email, password: password),
    );
  }

  String _errorAuth(FirebaseAuthException e) {
    switch (e.code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'La contraseña actual es incorrecta.';
      case 'weak-password':
        return 'La contraseña nueva es muy débil.';
      case 'email-already-in-use':
        return 'Ese correo ya está registrado.';
      case 'invalid-email':
        return 'El correo no es válido.';
      case 'too-many-requests':
        return 'Demasiados intentos. Espera unos minutos.';
      case 'requires-recent-login':
        return 'Vuelve a iniciar sesión e inténtalo de nuevo.';
      case 'network-request-failed':
        return 'Sin conexión a internet.';
      default:
        return 'Error: ${e.message ?? e.code}';
    }
  }

  Future<void> _cambiarCorreo() async {
    FocusScope.of(context).unfocus();

    final String nuevo = _correoNuevoCtrl.text.trim();
    final String pass = _correoPassCtrl.text;

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(nuevo)) {
      _mensaje('Escribe un correo válido.', error: true);
      return;
    }
    if (nuevo.toLowerCase() == _correoActual.toLowerCase()) {
      _mensaje('Ese ya es tu correo actual.', error: true);
      return;
    }
    if (pass.isEmpty) {
      _mensaje('Escribe tu contraseña actual para confirmar.', error: true);
      return;
    }

    setState(() => _cambiandoCorreo = true);

    try {
      await _reautenticar(pass);
      await FirebaseAuth.instance.currentUser!.verifyBeforeUpdateEmail(nuevo);

      _correoNuevoCtrl.clear();
      _correoPassCtrl.clear();
      _mensaje('Te enviamos un enlace de verificación a $nuevo. '
          'Tu correo cambiará cuando lo confirmes.');
    } on FirebaseAuthException catch (e) {
      _mensaje(_errorAuth(e), error: true);
    } catch (e) {
      _mensaje('No se pudo cambiar el correo: $e', error: true);
    } finally {
      if (mounted) setState(() => _cambiandoCorreo = false);
    }
  }

  Future<void> _cambiarPassword() async {
    FocusScope.of(context).unfocus();

    final String actual = _passActualCtrl.text;
    final String nueva = _passNuevaCtrl.text;
    final String confirmar = _passConfirmarCtrl.text;

    if (actual.isEmpty || nueva.isEmpty || confirmar.isEmpty) {
      _mensaje('Completa los tres campos de contraseña.', error: true);
      return;
    }
    if (nueva.length < 6) {
      _mensaje('La contraseña nueva debe tener al menos 6 caracteres.',
          error: true);
      return;
    }
    if (nueva != confirmar) {
      _mensaje('Las contraseñas nuevas no coinciden.', error: true);
      return;
    }
    if (nueva == actual) {
      _mensaje('La contraseña nueva debe ser distinta a la actual.',
          error: true);
      return;
    }

    setState(() => _cambiandoPass = true);

    try {
      await _reautenticar(actual);
      await FirebaseAuth.instance.currentUser!.updatePassword(nueva);

      _passActualCtrl.clear();
      _passNuevaCtrl.clear();
      _passConfirmarCtrl.clear();
      if (mounted) setState(() => _abierto['password'] = false);
      _mensaje('Contraseña actualizada ✅');
    } on FirebaseAuthException catch (e) {
      _mensaje(_errorAuth(e), error: true);
    } catch (e) {
      _mensaje('No se pudo cambiar la contraseña: $e', error: true);
    } finally {
      if (mounted) setState(() => _cambiandoPass = false);
    }
  }

  // ============================================================
  // FECHA DE NACIMIENTO
  // ============================================================
  Future<void> _seleccionarFecha() async {
    final DateTime hoy = DateTime.now();
    final DateTime? f = await showDatePicker(
      context: context,
      initialDate: DateTime(hoy.year - 20, hoy.month, hoy.day),
      firstDate: DateTime(1900),
      lastDate: hoy,
      helpText: 'Fecha de nacimiento',
    );
    if (f == null) return;

    _fechaCtrl.text = '${f.day.toString().padLeft(2, '0')}/'
        '${f.month.toString().padLeft(2, '0')}/${f.year}';
  }

  // ============================================================
  // FOTO DE PERFIL
  // ============================================================
  void _opcionesFoto() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.tarjeta,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: AppColors.primario),
              title: const Text('Tomar fotografía',
                  style: TextStyle(color: AppColors.texto)),
              onTap: () {
                Navigator.pop(ctx);
                _elegirFoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: AppColors.primario),
              title: const Text('Elegir de la galería',
                  style: TextStyle(color: AppColors.texto)),
              onTap: () {
                Navigator.pop(ctx);
                _elegirFoto(ImageSource.gallery);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _elegirFoto(ImageSource fuente) async {
    try {
      final XFile? elegida = await _picker.pickImage(source: fuente);
      if (elegida == null) return;

      final CroppedFile? recortada = await ImageCropper().cropImage(
        sourcePath: elegida.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressQuality: 90,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Ajustar imagen',
            toolbarColor: AppColors.primario,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
          ),
          IOSUiSettings(
            title: 'Ajustar imagen',
            aspectRatioLockEnabled: true,
          ),
        ],
      );
      if (recortada == null) return;

      setState(() => _subiendoFoto = true);

      final Uint8List original = await File(recortada.path).readAsBytes();
      final Uint8List comprimida =
          await compute(_prepararFotoPerfil, original);

      await FirebaseFirestore.instance.collection('usuarios').doc(_uid).set(
        {
          'fotoBase64': base64Encode(comprimida),
          'actualizado': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      ).timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw Exception(
            'Tiempo agotado. Revisa tu conexión a internet.'),
      );

      if (mounted) setState(() => _fotoBytes = comprimida);
      _mensaje('Foto de perfil actualizada ✅');
    } catch (e) {
      _mensaje('No se pudo cambiar la foto: $e', error: true);
    } finally {
      if (mounted) setState(() => _subiendoFoto = false);
    }
  }

  void _verFotoEnGrande() {
    final ImageProvider? image = _fotoProvider;
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
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // WIDGETS DE DISEÑO
  // ============================================================
  BoxDecoration _decoPill() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(28),
      boxShadow: [
        BoxShadow(
          color: AppColors.primario.withOpacity(0.15),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  Widget _avatar() {
    final ImageProvider? foto = _fotoProvider;

    return SizedBox(
      width: 150,
      height: 150,
      child: Stack(
        children: [
          GestureDetector(
            onTap: _verFotoEnGrande,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primario.withOpacity(0.2),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
                image: foto != null
                    ? DecorationImage(image: foto, fit: BoxFit.cover)
                    : null,
              ),
              child: foto == null
                  ? Icon(Icons.person,
                      size: 80, color: AppColors.primario.withOpacity(0.6))
                  : null,
            ),
          ),
          Positioned(
            bottom: 6,
            right: 6,
            child: GestureDetector(
              onTap: _subiendoFoto ? null : _opcionesFoto,
              child: CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primario,
                child: _subiendoFoto
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.camera_alt,
                        color: Colors.white, size: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Fila tipo "píldora" con el texto a la izquierda y el campo a la derecha.
  Widget _pillCampo({
    required String label,
    required TextEditingController controller,
    String hint = '',
    TextInputType tipo = TextInputType.text,
    List<TextInputFormatter>? formatters,
    int? maxLength,
  }) {
    return Container(
      decoration: _decoPill(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(color: AppColors.texto, fontSize: 16)),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: tipo,
              inputFormatters: formatters,
              maxLength: maxLength,
              textAlign: TextAlign.end,
              style: const TextStyle(
                  color: AppColors.textoSecundario, fontSize: 16),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: hint,
                hintStyle: const TextStyle(color: AppColors.textoTenue),
                counterText: '',
                contentPadding: const EdgeInsets.symmetric(vertical: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Fila tipo "píldora" que se despliega al tocarla.
  Widget _pillExpandible({
    required String id,
    required String titulo,
    String? subtitulo,
    String? valor,
    required List<Widget> hijos,
  }) {
    final bool abierto = _abierto[id] ?? false;

    return Container(
      decoration: _decoPill(),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: () => setState(() => _abierto[id] = !abierto),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titulo,
                            style: const TextStyle(
                                color: AppColors.texto, fontSize: 16)),
                        if (subtitulo != null && subtitulo.isNotEmpty)
                          Text(
                            subtitulo,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: AppColors.textoSecundario,
                                fontSize: 13),
                          ),
                      ],
                    ),
                  ),
                  if (valor != null)
                    Text(valor,
                        style: const TextStyle(
                            color: AppColors.textoSecundario, fontSize: 16)),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: abierto ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down,
                        color: AppColors.textoSecundario),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: abierto
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                    child: Column(children: hijos),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  // Campo de texto que va DENTRO de una sección desplegada.
  Widget _campoInterno({
    required String label,
    required TextEditingController controller,
    bool oculto = false,
    TextInputType tipo = TextInputType.text,
    bool soloLectura = false,
    VoidCallback? onTap,
    Widget? sufijo,
    List<TextInputFormatter>? formatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: oculto,
        keyboardType: tipo,
        readOnly: soloLectura,
        onTap: onTap,
        inputFormatters: formatters,
        style: const TextStyle(color: AppColors.texto),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppColors.textoSecundario),
          filled: true,
          fillColor: AppColors.fondo,
          suffixIcon: sufijo,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _botonSeccion({
    required String texto,
    required bool cargando,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: cargando ? null : onPressed,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        child: cargando
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(texto, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  Widget _iconoVerPass() {
    return IconButton(
      icon: Icon(
        _verPass ? Icons.visibility_off : Icons.visibility,
        color: AppColors.textoSecundario,
      ),
      onPressed: () => setState(() => _verPass = !_verPass),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fondo,
      appBar: AppBar(
        centerTitle: true,
        title: const Text(
          'Perfil',
          style: TextStyle(
            color: AppColors.hover,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _cargando
          ? const Center(child: CircularProgressIndicator())
          : GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                child: Column(
                  children: [
                    _avatar(),
                    const SizedBox(height: 26),

                    // NOMBRE DE USUARIO
                    _pillCampo(
                      label: 'Nombre de usuario',
                      controller: _nombreCtrl,
                      hint: 'Tu nombre',
                      maxLength: 40,
                    ),
                    const SizedBox(height: 14),

                    // CORREO ELECTRÓNICO
                    _pillExpandible(
                      id: 'correo',
                      titulo: 'Correo electrónico',
                      subtitulo: _correoActual,
                      hijos: [
                        _campoInterno(
                          label: 'Nuevo correo',
                          controller: _correoNuevoCtrl,
                          tipo: TextInputType.emailAddress,
                        ),
                        _campoInterno(
                          label: 'Contraseña actual',
                          controller: _correoPassCtrl,
                          oculto: !_verPass,
                          sufijo: _iconoVerPass(),
                        ),
                        _botonSeccion(
                          texto: 'Cambiar correo',
                          cargando: _cambiandoCorreo,
                          onPressed: _cambiarCorreo,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Te enviaremos un enlace de verificación al correo '
                          'nuevo. El cambio se aplica cuando lo confirmes.',
                          style: TextStyle(
                              color: AppColors.textoTenue, fontSize: 12),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // CONTRASEÑA
                    _pillExpandible(
                      id: 'password',
                      titulo: 'Contraseña',
                      valor: '••••••••••',
                      hijos: [
                        _campoInterno(
                          label: 'Contraseña actual',
                          controller: _passActualCtrl,
                          oculto: !_verPass,
                          sufijo: _iconoVerPass(),
                        ),
                        _campoInterno(
                          label: 'Contraseña nueva',
                          controller: _passNuevaCtrl,
                          oculto: !_verPass,
                        ),
                        _campoInterno(
                          label: 'Confirmar contraseña nueva',
                          controller: _passConfirmarCtrl,
                          oculto: !_verPass,
                        ),
                        _botonSeccion(
                          texto: 'Cambiar contraseña',
                          cargando: _cambiandoPass,
                          onPressed: _cambiarPassword,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // TELÉFONO
                    _pillCampo(
                      label: 'Teléfono',
                      controller: _telefonoCtrl,
                      hint: '10 dígitos',
                      tipo: TextInputType.phone,
                      maxLength: 18,
                      formatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]')),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // DATOS PERSONALES
                    _pillExpandible(
                      id: 'datos',
                      titulo: 'Datos personales',
                      hijos: [
                        _campoInterno(
                          label: 'Fecha de nacimiento',
                          controller: _fechaCtrl,
                          soloLectura: true,
                          onTap: _seleccionarFecha,
                          sufijo: const Icon(Icons.calendar_today,
                              size: 20, color: AppColors.textoSecundario),
                        ),
                        _campoInterno(
                          label: 'Ciudad',
                          controller: _ciudadCtrl,
                        ),
                        _campoInterno(
                          label: 'Institución o laboratorio',
                          controller: _institucionCtrl,
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () =>
                            setState(() => _abierto['datos'] = true),
                        child: const Text('Editar información personal'),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // GUARDAR CAMBIOS
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _guardando ? null : _guardar,
                        style: ElevatedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: _guardando
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5, color: Colors.white),
                              )
                            : const Text(
                                'Guardar cambios',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // MI PAQUETE
                    StreamBuilder<EstadoPlan>(
                      stream: PlanService.estadoPlanStream(),
                      builder: (context, snapshot) {
                        final EstadoPlan e =
                            snapshot.data ?? EstadoPlan.porDefecto;
                        final String nombrePaquete = e.pruebaActiva
                            ? 'Premium (prueba gratis)'
                            : e.planBase.nombre;

                        return InkWell(
                          borderRadius: BorderRadius.circular(28),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const PlanesPage()),
                          ),
                          child: Container(
                            decoration: _decoPill(),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 16),
                            child: Row(
                              children: [
                                const Icon(Icons.workspace_premium,
                                    color: Colors.amber),
                                const SizedBox(width: 12),
                                const Expanded(
                                  child: Text('Mi paquete',
                                      style: TextStyle(
                                          color: AppColors.texto,
                                          fontSize: 16)),
                                ),
                                Text(nombrePaquete,
                                    style: const TextStyle(
                                        color: AppColors.textoSecundario,
                                        fontSize: 15)),
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right,
                                    color: AppColors.textoSecundario),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}