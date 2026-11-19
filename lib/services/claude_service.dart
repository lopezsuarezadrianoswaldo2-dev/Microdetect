import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

/// Error "amigable" para mostrar al usuario.
class ClaudeException implements Exception {
  final String mensaje;
  ClaudeException(this.mensaje);

  @override
  String toString() => mensaje;
}

/// Resultado del análisis de Claude sobre una caja Petri.
class AnalisisIA {
  final bool esPlacaPetri;
  final int? conteoEstimado;

  /// razonable | posible_subestimacion | posible_sobreestimacion | no_evaluable
  final String valoracionConteo;
  final String morfologia;
  final String calidadImagen;
  final String posibleContaminacion;
  final String recomendaciones;

  const AnalisisIA({
    required this.esPlacaPetri,
    required this.conteoEstimado,
    required this.valoracionConteo,
    required this.morfologia,
    required this.calidadImagen,
    required this.posibleContaminacion,
    required this.recomendaciones,
  });

  String get valoracionTexto {
    switch (valoracionConteo) {
      case 'razonable':
        return 'El conteo automático parece razonable';
      case 'posible_subestimacion':
        return 'El conteo automático podría estar por debajo del real';
      case 'posible_sobreestimacion':
        return 'El conteo automático podría estar por encima del real';
      default:
        return 'No se pudo evaluar el conteo automático';
    }
  }

  /// Secciones listas para mostrar (pantalla, imagen o PDF).
  List<MapEntry<String, String>> get secciones => [
        MapEntry('Conteo estimado por Claude',
            conteoEstimado?.toString() ?? 'No disponible'),
        MapEntry('Valoración del conteo automático', valoracionTexto),
        MapEntry('Morfología de las colonias', morfologia),
        MapEntry('Calidad de la imagen', calidadImagen),
        MapEntry('Posible contaminación', posibleContaminacion),
        MapEntry('Recomendaciones', recomendaciones),
      ]..removeWhere((e) => e.value.trim().isEmpty);

  Map<String, dynamic> toMap() => {
        'esPlacaPetri': esPlacaPetri,
        'conteoEstimado': conteoEstimado,
        'valoracionConteo': valoracionConteo,
        'morfologia': morfologia,
        'calidadImagen': calidadImagen,
        'posibleContaminacion': posibleContaminacion,
        'recomendaciones': recomendaciones,
      };

  factory AnalisisIA.fromMap(Map<String, dynamic> m) {
    final dynamic c = m['conteoEstimado'];
    return AnalisisIA(
      esPlacaPetri: m['esPlacaPetri'] != false,
      conteoEstimado: c is num ? c.round() : int.tryParse('${c ?? ''}'),
      valoracionConteo: (m['valoracionConteo'] ?? 'no_evaluable').toString(),
      morfologia: (m['morfologia'] ?? '').toString(),
      calidadImagen: (m['calidadImagen'] ?? '').toString(),
      posibleContaminacion: (m['posibleContaminacion'] ?? '').toString(),
      recomendaciones: (m['recomendaciones'] ?? '').toString(),
    );
  }
}

/// Reduce la foto a un tamaño que Claude procesa bien (lado mayor 1568 px)
/// y la convierte a JPG. Va en un hilo aparte para no congelar la pantalla.
Uint8List _prepararImagenParaClaude(Uint8List bytes) {
  final img.Image? decodificada = img.decodeImage(bytes);
  if (decodificada == null) {
    throw Exception('No se pudo leer la imagen.');
  }

  img.Image imagen = img.bakeOrientation(decodificada);

  const int maxLado = 1568;
  if (imagen.width >= imagen.height) {
    if (imagen.width > maxLado) {
      imagen = img.copyResize(imagen, width: maxLado);
    }
  } else {
    if (imagen.height > maxLado) {
      imagen = img.copyResize(imagen, height: maxLado);
    }
  }

  return Uint8List.fromList(img.encodeJpg(imagen, quality: 85));
}

class ClaudeService {
  ClaudeService._();

  // ============================================================
  // CONFIGURACIÓN
  //
  // La clave NO se escribe en el código. Se pasa al ejecutar la app:
  //
  //   flutter run --dart-define=ANTHROPIC_API_KEY=sk-ant-xxxxxxxx
  //
  // (y igual con "flutter build apk --dart-define=...").
  // ============================================================
  static const String _apiKey = String.fromEnvironment('ANTHROPIC_API_KEY');

  /// Modelo de Claude. Si algún día quieres otro, solo cambia esta línea.
  static const String _modelo = 'claude-sonnet-5-5';

  static const String _url = 'https://api.anthropic.com/v1/messages';
  static const String _version = '2023-06-01';

  static const String _sistema =
      'Eres un asistente de apoyo para laboratorio de microbiología dentro de '
      'una app que cuenta colonias bacterianas en cajas Petri. Analizas la '
      'fotografía que se te envía y respondes en español. Tu análisis es '
      'orientativo y no sustituye el criterio del laboratorista. Responde '
      'SOLO con un objeto JSON válido, sin texto antes ni después y sin '
      'bloques de código. Dentro de los textos usa solo texto plano: sin '
      'markdown, sin emojis y sin símbolos especiales.';

  static String _instrucciones(int conteoLocal) {
    return 'La app ya contó con su algoritmo propio $conteoLocal colonias en '
        'esta imagen. Analiza la fotografía y devuelve exactamente este JSON:\n'
        '{\n'
        '  "es_placa_petri": true o false,\n'
        '  "conteo_estimado": numero entero aproximado de colonias que ves, o null si no es posible estimarlo,\n'
        '  "valoracion_conteo_local": "razonable" o "posible_subestimacion" o "posible_sobreestimacion" o "no_evaluable",\n'
        '  "morfologia": "descripcion breve de forma, tamano y color de las colonias",\n'
        '  "calidad_imagen": "comentario breve sobre enfoque, iluminacion, reflejos y si la placa se ve completa",\n'
        '  "posible_contaminacion": "indicios de hongos, colonias expansivas o morfologias mezcladas; o indica que no se observan",\n'
        '  "recomendaciones": "maximo 2 frases con sugerencias practicas"\n'
        '}\n'
        'Si la imagen no es una caja Petri, pon es_placa_petri en false y explica '
        'el motivo en calidad_imagen. Si hay cientos de colonias, el conteo '
        'estimado es solo una referencia aproximada; dilo en la valoracion.';
  }

  static Future<AnalisisIA> analizarPlaca(
    File imagen, {
    required int conteoLocal,
  }) async {
    if (_apiKey.isEmpty) {
      throw ClaudeException(
        'Falta la clave de Claude. Ejecuta la app con '
        '--dart-define=ANTHROPIC_API_KEY=tu_clave',
      );
    }

    try {
      final Uint8List original = await imagen.readAsBytes();
      final Uint8List preparada =
          await compute(_prepararImagenParaClaude, original);

      final http.Response respuesta = await http
          .post(
            Uri.parse(_url),
            headers: {
              'content-type': 'application/json',
              'x-api-key': _apiKey,
              'anthropic-version': _version,
            },
            body: jsonEncode({
              'model': _modelo,
              'max_tokens': 1000,
              'system': _sistema,
              'messages': [
                {
                  'role': 'user',
                  'content': [
                    {
                      'type': 'image',
                      'source': {
                        'type': 'base64',
                        'media_type': 'image/jpeg',
                        'data': base64Encode(preparada),
                      },
                    },
                    {
                      'type': 'text',
                      'text': _instrucciones(conteoLocal),
                    },
                  ],
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 60));

      final dynamic cuerpo = jsonDecode(utf8.decode(respuesta.bodyBytes));

      if (respuesta.statusCode != 200) {
        throw ClaudeException(_mensajeDeError(respuesta.statusCode, cuerpo));
      }

      final StringBuffer texto = StringBuffer();
      for (final dynamic bloque in (cuerpo['content'] as List? ?? [])) {
        if (bloque is Map && bloque['type'] == 'text') {
          texto.write(bloque['text']);
        }
      }

      return _interpretar(texto.toString());
    } on ClaudeException {
      rethrow;
    } on TimeoutException {
      throw ClaudeException(
          'Claude tardó demasiado en responder. Intenta de nuevo.');
    } on SocketException {
      throw ClaudeException('Sin conexión a internet.');
    }
  }

  static String _mensajeDeError(int codigo, dynamic cuerpo) {
    switch (codigo) {
      case 401:
        return 'La clave de Claude no es válida.';
      case 403:
        return 'La clave de Claude no tiene permiso para usar este modelo.';
      case 429:
        return 'Demasiadas solicitudes seguidas. Espera un momento e intenta de nuevo.';
      case 500:
      case 503:
      case 529:
        return 'Claude está saturado en este momento. Intenta de nuevo en unos minutos.';
    }

    String detalle = '';
    if (cuerpo is Map && cuerpo['error'] is Map) {
      detalle = (cuerpo['error']['message'] ?? '').toString();
    }
    return 'Error de Claude ($codigo). $detalle'.trim();
  }

  /// Convierte la respuesta de Claude (JSON en texto) en un [AnalisisIA].
  /// Si por algo no viniera como JSON, se muestra el texto tal cual.
  static AnalisisIA _interpretar(String texto) {
    final int inicio = texto.indexOf('{');
    final int fin = texto.lastIndexOf('}');

    if (inicio != -1 && fin > inicio) {
      try {
        final dynamic json = jsonDecode(texto.substring(inicio, fin + 1));
        if (json is Map<String, dynamic>) {
          final dynamic c = json['conteo_estimado'];
          return AnalisisIA(
            esPlacaPetri: json['es_placa_petri'] != false,
            conteoEstimado: c is num ? c.round() : int.tryParse('${c ?? ''}'),
            valoracionConteo:
                (json['valoracion_conteo_local'] ?? 'no_evaluable').toString(),
            morfologia: (json['morfologia'] ?? '').toString(),
            calidadImagen: (json['calidad_imagen'] ?? '').toString(),
            posibleContaminacion:
                (json['posible_contaminacion'] ?? '').toString(),
            recomendaciones: (json['recomendaciones'] ?? '').toString(),
          );
        }
      } catch (_) {
        // Cae al respaldo de abajo.
      }
    }

    return AnalisisIA(
      esPlacaPetri: true,
      conteoEstimado: null,
      valoracionConteo: 'no_evaluable',
      morfologia: texto.trim(),
      calidadImagen: '',
      posibleContaminacion: '',
      recomendaciones: '',
    );
  }
}