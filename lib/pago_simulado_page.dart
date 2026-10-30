import 'package:bioconteo_colonias_bacterinas/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/plan_service.dart';

/// ============================================================
/// PANTALLA DE PAGO SIMULADO (ficticio)
/// ============================================================
/// ¡IMPORTANTE! Esta pantalla NO procesa pagos reales. Los campos
/// de tarjeta no se validan contra ningún banco ni pasarela de
/// pago; solo sirven para que la demo se vea/sienta como un
/// checkout real. Cuando llegue el momento de cobrar de verdad,
/// esta pantalla se reemplaza (o se conecta) con:
///   - in_app_purchase (Google Play / App Store), o
///   - un backend con Stripe / Mercado Pago.
/// ============================================================

class PagoSimuladoPage extends StatefulWidget {
  final AppPlan plan;

  const PagoSimuladoPage({super.key, required this.plan});

  @override
  State<PagoSimuladoPage> createState() => _PagoSimuladoPageState();
}

class _PagoSimuladoPageState extends State<PagoSimuladoPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nombreController = TextEditingController();
  final TextEditingController _numeroController = TextEditingController();
  final TextEditingController _fechaController = TextEditingController();
  final TextEditingController _cvvController = TextEditingController();

  bool _procesando = false;

  @override
  void dispose() {
    _nombreController.dispose();
    _numeroController.dispose();
    _fechaController.dispose();
    _cvvController.dispose();
    super.dispose();
  }

  Future<void> _procesarPagoFicticio() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _procesando = true);

    try {
      // Simulamos el "tiempo de procesamiento" de una pasarela real.
      await Future.delayed(const Duration(seconds: 2));

      // Como el pago es ficticio, se da por aprobado y se guarda el
      // nuevo plan en Firestore (usuarios/{uid}.plan). Al cambiar ese
      // campo, la pantalla principal desbloquea las funciones sola.
      await PlanService.cambiarPlan(widget.plan).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception(
            'Tiempo agotado. Revisa tu internet y las reglas de Firestore.'),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _procesando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo completar el pago: $e')),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _procesando = false);

    // Diálogo de éxito
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.tarjeta,
        title: Row(
          children: const [
            Icon(Icons.check_circle, color: Colors.green),
            SizedBox(width: 10),
            Text('Pago exitoso', style: TextStyle(color: AppColors.texto)),
          ],
        ),
        content: Text(
          'Tu plan ahora es ${widget.plan.nombre} ✅\n\n'
          '(Este es un pago simulado, no se realizó ningún cargo real.)',
          style: const TextStyle(color: AppColors.textoSecundario),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // cierra el diálogo
              Navigator.pop(context); // regresa a la pantalla de Planes
            },
            child: const Text('Listo'),
          ),
        ],
      ),
    );
  }

  String? _validarNumeroTarjeta(String? v) {
    if (v == null || v.length != 16) {
      return 'El número debe tener 16 dígitos';
    }
    return null;
  }

  String? _validarFecha(String? v) {
    if (v == null || !RegExp(r'^(0[1-9]|1[0-2])/\d{2}$').hasMatch(v)) {
      return 'Usa el formato MM/AA';
    }
    final mes = int.parse(v.substring(0, 2));
    final anio = 2000 + int.parse(v.substring(3, 5));
    final ahora = DateTime.now();
    if (anio < ahora.year || (anio == ahora.year && mes < ahora.month)) {
      return 'La tarjeta está vencida';
    }
    return null;
  }

  String? _validarCvv(String? v) {
    if (v == null || v.length != 3) return 'El CVV tiene 3 dígitos';
    return null;
  }

  String? _validarCampo(String? valor, String nombreCampo) {
    if (valor == null || valor.trim().isEmpty) {
      return 'Ingresa $nombreCampo';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fondo,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.texto),
        title: const Text('Pago', style: TextStyle(color: AppColors.texto)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Aviso de que es un pago simulado
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Esto es un pago de PRUEBA. No se hará ningún cargo real '
                        'a ninguna tarjeta.',
                        style: TextStyle(color: Colors.amber, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Resumen del plan a comprar
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.tarjeta,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.workspace_premium, color: Colors.amber),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Plan ${widget.plan.nombre}',
                            style: const TextStyle(
                              color: AppColors.texto,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            widget.plan.precioReferencia,
                            style: const TextStyle(color: AppColors.textoSecundario),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              const Text(
                'Datos de la tarjeta (simulados)',
                style: TextStyle(
                    color: AppColors.texto, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),

              _campoTexto(
                controller: _nombreController,
                label: 'Nombre en la tarjeta',
                icon: Icons.person,
                validator: (v) => _validarCampo(v, 'el nombre'),
              ),
              const SizedBox(height: 14),
              _campoTexto(
                controller: _numeroController,
                label: 'Número de tarjeta',
                icon: Icons.credit_card,
                keyboardType: TextInputType.number,
                maxLength: 16,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: _validarNumeroTarjeta,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _campoTexto(
                      controller: _fechaController,
                      label: 'MM/AA',
                      icon: Icons.calendar_today,
                      keyboardType: TextInputType.datetime,
                      maxLength: 5,
                      inputFormatters: [_FechaTarjetaFormatter()],
                      validator: _validarFecha,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: _campoTexto(
                      controller: _cvvController,
                      label: 'CVV',
                      icon: Icons.lock,
                      keyboardType: TextInputType.number,
                      maxLength: 3,
                      obscureText: true,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: _validarCvv,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _procesando ? null : _procesarPagoFicticio,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _procesando
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          'Pagar ${widget.plan.precioReferencia}',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _campoTexto({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int? maxLength,
    bool obscureText = false,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLength: maxLength,
      obscureText: obscureText,
      inputFormatters: inputFormatters,
      validator: validator,
      style: const TextStyle(color: AppColors.texto),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textoSecundario),
        prefixIcon: Icon(icon, color: AppColors.textoSecundario),
        counterStyle: const TextStyle(color: AppColors.textoTenue),
        filled: true,
        fillColor: AppColors.tarjeta,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// Escribe solo números y agrega la "/" sola: 1228 -> 12/28
class _FechaTarjetaFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final soloDigitos = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final limitado =
        soloDigitos.length > 4 ? soloDigitos.substring(0, 4) : soloDigitos;

    final texto = limitado.length > 2
        ? '${limitado.substring(0, 2)}/${limitado.substring(2)}'
        : limitado;

    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}