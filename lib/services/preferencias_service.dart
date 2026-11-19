import 'package:shared_preferences/shared_preferences.dart';

class PreferenciasService {
  static const String _claveEmail = 'email_guardado';
  static const String _claveRecordar = 'recordar_email';

  static Future<void> guardarEmail(String email, bool recordar) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_claveRecordar, recordar);
    if (recordar) {
      await prefs.setString(_claveEmail, email);
    } else {
      await prefs.remove(_claveEmail);
    }
  }

  static Future<String> leerEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_claveEmail) ?? '';
  }

  static Future<bool> leerRecordar() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_claveRecordar) ?? false;
  }
}