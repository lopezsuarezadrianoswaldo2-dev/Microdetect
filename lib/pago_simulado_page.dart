import 'package:flutter/material.dart';
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

  const PagoSimuladoPage({Key? key, required this.plan}) : super(key: key);

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

    // Simulamos el "tiempo de procesamiento" de una pasarela real.
    await Future.delayed(const Duration(seconds: 2));

    // Aquí, en un cobro real, se validaría la respuesta del banco.
    // Como es ficticio, simplemente lo damos por exitoso.
    await PlanService.cambiarPlan(widget.plan);

    if (!mounted) return;
    setState(() => _procesando = false);

    // Diálogo de éxito
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1B263B),
        title: Row(
          children: const [
            Icon(Icons.check_circle, color: Colors.greenAccent),
            SizedBox(width: 10),
            Text('Pago exitoso', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: Text(
          'Tu plan ahora es ${widget.plan.nombre} ✅\n\n'
          '(Este es un pago simulado, no se realizó ningún cargo real.)',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // cierra el diálogo
              Navigator.pop(context); // regresa a la pantalla de Planes
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF415A77),
            ),
            child: const Text('Listo', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Pago', style: TextStyle(color: Colors.white)),
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
                  color: const Color(0xFF1B263B),
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
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            widget.plan.precioReferencia,
                            style: const TextStyle(color: Colors.white54),
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
                    color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
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
                validator: (v) {
                  if (v == null || v.trim().length < 4) {
                    return 'Ingresa un número de tarjeta';
                  }
                  return null;
                },
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
                      validator: (v) => _validarCampo(v, 'la fecha'),
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
                      validator: (v) => _validarCampo(v, 'el CVV'),
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
                    backgroundColor: const Color(0xFF415A77),
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
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLength: maxLength,
      obscureText: obscureText,
      validator: validator,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: Colors.white54),
        counterStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: const Color(0xFF1B263B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}