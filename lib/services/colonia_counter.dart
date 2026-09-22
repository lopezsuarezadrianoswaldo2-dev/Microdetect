import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

/// Resultado del conteo automático de colonias.
class ResultadoConteo {
  final int conteo;
  final Uint8List imagenProcesada;

  ResultadoConteo({
    required this.conteo,
    required this.imagenProcesada,
  });
}

class ColoniaCounter {
  /// Resolución utilizada para analizar la fotografía.
  static const int _anchoProceso = 700;

  /// Zona interior que analizaremos.
  ///
  /// Se amplía casi hasta el borde de la placa para poder detectar
  /// colonias que crecen cerca del vidrio, sin llegar al 100% para
  /// evitar el reflejo/brillo del canto de la placa.
  static const double _radioZonaAnalisis = 0.94;

  /// Radio usado para comparar cada píxel con sus alrededores.
  static const int _radioContraste = 10;

  /// Contraste mínimo inicial.
  ///
  /// Después se adapta automáticamente a cada fotografía.
  static const double _contrasteMinimoBase = 12.0;

  static Future<ResultadoConteo> contar(File archivoImagen) async {
    // ============================================================
    // 1. LEER IMAGEN
    // ============================================================

    final Uint8List bytes = await archivoImagen.readAsBytes();

    final img.Image? original = img.decodeImage(bytes);

    if (original == null) {
      throw Exception('No se pudo leer la imagen.');
    }

    // ============================================================
    // 2. REESCALAR
    // ============================================================

    final img.Image imagen = img.copyResize(
      original,
      width: _anchoProceso,
    );

    final int w = imagen.width;
    final int h = imagen.height;

    // ============================================================
    // 3. ESCALA DE GRISES
    // ============================================================

    final img.Image gris = img.grayscale(imagen);

    // ============================================================
    // 4. CENTRO Y ZONA DE ANÁLISIS
    // ============================================================

    final int centroX = w ~/ 2;
    final int centroY = h ~/ 2;

    final double radioPlaca =
        (math.min(w, h) / 2) * _radioZonaAnalisis;

    final double radioPlaca2 = radioPlaca * radioPlaca;

    // ============================================================
    // 5. GUARDAR LUMINANCIA DE TODOS LOS PÍXELES
    // ============================================================

    final List<int> luminancia = List<int>.filled(w * h, 0);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        luminancia[(y * w) + x] =
            img.getLuminance(gris.getPixel(x, y)).toInt();
      }
    }

    // ============================================================
    // 6. CREAR IMAGEN INTEGRAL
    //
    // Nos permite obtener rápidamente el brillo promedio alrededor
    // de cada píxel.
    // ============================================================

    final int integralWidth = w + 1;

    final List<int> integral =
        List<int>.filled((w + 1) * (h + 1), 0);

    for (int y = 1; y <= h; y++) {
      int sumaFila = 0;

      for (int x = 1; x <= w; x++) {
        sumaFila += luminancia[((y - 1) * w) + (x - 1)];

        integral[(y * integralWidth) + x] =
            integral[((y - 1) * integralWidth) + x] + sumaFila;
      }
    }

    // ============================================================
    // 7. CALCULAR CONTRASTES DE LA IMAGEN
    //
    // Ya no importa si una colonia es clara u oscura.
    // Lo importante es cuánto se diferencia de su alrededor.
    // ============================================================

    final List<double> diferencias = [];

    for (int y = _radioContraste;
        y < h - _radioContraste;
        y += 3) {
      for (int x = _radioContraste;
          x < w - _radioContraste;
          x += 3) {
        final double dx = (x - centroX).toDouble();
        final double dy = (y - centroY).toDouble();

        if ((dx * dx) + (dy * dy) > radioPlaca2) {
          continue;
        }

        final double promedio = _promedioZona(
          integral,
          integralWidth,
          x - _radioContraste,
          y - _radioContraste,
          x + _radioContraste,
          y + _radioContraste,
        );

        final double brillo =
            luminancia[(y * w) + x].toDouble();

        diferencias.add(
          (brillo - promedio).abs(),
        );
      }
    }

    // ============================================================
    // 8. UMBRAL ADAPTATIVO
    // ============================================================

    double promedioDiferencias = 0;

    if (diferencias.isNotEmpty) {
      promedioDiferencias =
          diferencias.reduce((a, b) => a + b) /
              diferencias.length;
    }

    double sumaVarianza = 0;

    for (final diferencia in diferencias) {
      final double d =
          diferencia - promedioDiferencias;

      sumaVarianza += d * d;
    }

    double desviacion = 0;

    if (diferencias.isNotEmpty) {
      desviacion =
          math.sqrt(sumaVarianza / diferencias.length);
    }

    // Se adapta a cada fotografía.
    double umbralContraste =
        promedioDiferencias + (desviacion * 1.15);

    if (umbralContraste < _contrasteMinimoBase) {
      umbralContraste = _contrasteMinimoBase;
    }

    // Evitar que una fotografía con muchísimo contraste
    // produzca un umbral exageradamente alto.
    if (umbralContraste > 28) {
      umbralContraste = 28;
    }

    // ============================================================
    // 9. CREAR MÁSCARA DE POSIBLES COLONIAS
    // ============================================================

    List<List<bool>> mascara = List.generate(
      h,
      (_) => List<bool>.filled(w, false),
    );

    for (int y = _radioContraste;
        y < h - _radioContraste;
        y++) {
      for (int x = _radioContraste;
          x < w - _radioContraste;
          x++) {
        final double dx = (x - centroX).toDouble();
        final double dy = (y - centroY).toDouble();

        final double distancia2 =
            (dx * dx) + (dy * dy);

        // No analizar fuera de la zona segura.
        if (distancia2 > radioPlaca2) {
          continue;
        }

        final double promedio = _promedioZona(
          integral,
          integralWidth,
          x - _radioContraste,
          y - _radioContraste,
          x + _radioContraste,
          y + _radioContraste,
        );

        final double brillo =
            luminancia[(y * w) + x].toDouble();

        // IMPORTANTE:
        // usamos valor absoluto.
        //
        // Claro sobre oscuro -> detectado
        // Oscuro sobre claro -> detectado
        final double contraste =
            (brillo - promedio).abs();

        if (contraste >= umbralContraste) {
          mascara[y][x] = true;
        }
      }
    }

    // ============================================================
    // 10. QUITAR PÍXELES AISLADOS
    // ============================================================

    mascara = _eliminarRuido(
      mascara,
      w,
      h,
    );

    // ============================================================
    // 11. TAMAÑOS ADAPTATIVOS
    // ============================================================

    final double areaPlaca =
        math.pi * radioPlaca * radioPlaca;

    final int areaMinima =
        math.max(7, (areaPlaca * 0.000035).round());

    final int areaMaxima =
        math.max(180, (areaPlaca * 0.008).round());

    // ============================================================
    // 12. FLOOD FILL
    // ============================================================

    final List<List<bool>> visitado = List.generate(
      h,
      (_) => List<bool>.filled(w, false),
    );

    final List<_Blob> colonias = [];

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (!mascara[y][x] || visitado[y][x]) {
          continue;
        }

        final _Blob blob = _floodFill(
          mascara,
          visitado,
          luminancia,
          x,
          y,
          w,
          h,
        );

        // --------------------------------------------------------
        // FILTRO 1: ÁREA
        // --------------------------------------------------------

        if (blob.area < areaMinima ||
            blob.area > areaMaxima) {
          continue;
        }

        // --------------------------------------------------------
        // FILTRO 2: DIMENSIONES
        // --------------------------------------------------------

        if (blob.ancho < 3 || blob.alto < 3) {
          continue;
        }

        // --------------------------------------------------------
        // FILTRO 3: FORMA
        //
        // Permitimos formas irregulares, pero eliminamos rayas,
        // reflejos o bordes muy alargados.
        // --------------------------------------------------------

        final int dimensionMayor =
            math.max(blob.ancho, blob.alto);

        final int dimensionMenor =
            math.min(blob.ancho, blob.alto);

        final double proporcion =
            dimensionMayor / dimensionMenor;

        if (proporcion > 2.8) {
          continue;
        }

        // --------------------------------------------------------
        // FILTRO 4: DENSIDAD
        //
        // Una colonia debe ocupar una parte razonable de su
        // rectángulo. Una línea o borde normalmente tendrá
        // densidad muy baja.
        // --------------------------------------------------------

        final double areaCaja =
            (blob.ancho * blob.alto).toDouble();

        final double densidad =
            blob.area / areaCaja;

        if (densidad < 0.20) {
          continue;
        }

        // --------------------------------------------------------
        // FILTRO 5: BORDE
        //
        // Margen reducido para permitir contar colonias que
        // crecen cerca del canto de la placa.
        // --------------------------------------------------------

        final double bx =
            (blob.cx - centroX).toDouble();

        final double by =
            (blob.cy - centroY).toDouble();

        final double distanciaCentro =
            math.sqrt((bx * bx) + (by * by));

        // Margen mínimo, solo para evitar el brillo del canto
        // de vidrio, no para descartar colonias reales.
        final double margenBorde =
            math.max(4.0, blob.radio * 0.5);

        if (distanciaCentro >
            radioPlaca - margenBorde) {
          continue;
        }

        // --------------------------------------------------------
        // FILTRO 6: CONTRASTE REAL DE LA MANCHA
        // --------------------------------------------------------

        final double contrasteBlob =
            _contrasteBlob(
          luminancia,
          w,
          h,
          blob,
        );

        if (contrasteBlob <
            umbralContraste * 0.70) {
          continue;
        }

        // --------------------------------------------------------
        // FILTRO 7: CIRCULARIDAD REAL
        //
        // Compara la mancha con un círculo perfecto usando su
        // perímetro real (no solo el rectángulo que la envuelve).
        // Esto descarta rayones, polvo y reflejos alargados o
        // irregulares, sin importar en qué parte de la placa
        // estén (esquinas, orillas, centro, etc).
        // --------------------------------------------------------

        final double circularidad = blob.perimetro > 0
            ? (4 * math.pi * blob.area) /
                (blob.perimetro * blob.perimetro)
            : 0;

        if (circularidad < 0.35) {
          continue;
        }

        // --------------------------------------------------------
        // FILTRO 8: UNIFORMIDAD INTERNA
        //
        // Una colonia real (blanca u oscura) tiene un color
        // bastante parejo por dentro, como una mancha sólida.
        //
        // Una burbuja o un reflejo de luz, en cambio, casi
        // siempre tiene un brillo MUY irregular por dentro: un
        // punto muy claro (el reflejo de la luz) rodeado de
        // sombra, lo que genera mucha variación de color dentro
        // de la misma mancha.
        //
        // Aquí medimos esa variación interna (desviación
        // estándar de luminancia dentro del blob) y la
        // comparamos contra el contraste que tiene la mancha
        // frente a su fondo. Si la variación interna es
        // demasiado grande respecto a ese contraste, es más
        // probable que sea una burbuja/reflejo que una colonia
        // real.
        // --------------------------------------------------------

        if (blob.desviacionInterna >
            contrasteBlob * 0.75) {
          continue;
        }

        colonias.add(blob);
      }
    }

    // ============================================================
    // 13. DIBUJAR CÍRCULOS
    // ============================================================

    final img.Image marcada = img.copyResize(
      original,
      width: _anchoProceso,
    );

    for (final _Blob colonia in colonias) {
      img.drawCircle(
        marcada,
        x: colonia.cx,
        y: colonia.cy,
        radius: colonia.radio + 3,
        color: img.ColorRgb8(
          255,
          40,
          40,
        ),
      );
    }

    // ============================================================
    // 14. GENERAR JPG
    // ============================================================

    final Uint8List jpgMarcada =
        Uint8List.fromList(
      img.encodeJpg(
        marcada,
        quality: 88,
      ),
    );

    return ResultadoConteo(
      conteo: colonias.length,
      imagenProcesada: jpgMarcada,
    );
  }

  // ==============================================================
  // PROMEDIO DE UNA ZONA USANDO IMAGEN INTEGRAL
  // ==============================================================

  static double _promedioZona(
    List<int> integral,
    int integralWidth,
    int x1,
    int y1,
    int x2,
    int y2,
  ) {
    final int ax = x1;
    final int ay = y1;

    final int bx = x2 + 1;
    final int by = y2 + 1;

    final int suma =
        integral[(by * integralWidth) + bx] -
            integral[(ay * integralWidth) + bx] -
            integral[(by * integralWidth) + ax] +
            integral[(ay * integralWidth) + ax];

    final int cantidad =
        (x2 - x1 + 1) * (y2 - y1 + 1);

    if (cantidad <= 0) {
      return 0;
    }

    return suma / cantidad;
  }

  // ==============================================================
  // ELIMINACIÓN DE RUIDO
  // ==============================================================

  static List<List<bool>> _eliminarRuido(
    List<List<bool>> mascara,
    int w,
    int h,
  ) {
    final List<List<bool>> limpia =
        List.generate(
      h,
      (_) => List<bool>.filled(w, false),
    );

    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        if (!mascara[y][x]) {
          continue;
        }

        int vecinos = 0;

        for (int dy = -1; dy <= 1; dy++) {
          for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) {
              continue;
            }

            if (mascara[y + dy][x + dx]) {
              vecinos++;
            }
          }
        }

        // Necesitamos al menos dos píxeles cercanos.
        if (vecinos >= 2) {
          limpia[y][x] = true;
        }
      }
    }

    return limpia;
  }

  // ==============================================================
  // CONTRASTE DE UN COMPONENTE
  // ==============================================================

  static double _contrasteBlob(
    List<int> luminancia,
    int w,
    int h,
    _Blob blob,
  ) {
    final int radioInterior =
        math.max(blob.radio, 2);

    final int radioExterior =
        math.max(
      radioInterior + 6,
      (radioInterior * 2.2).round(),
    );

    double sumaInterior = 0;
    int cantidadInterior = 0;

    double sumaExterior = 0;
    int cantidadExterior = 0;

    for (int y = blob.cy - radioExterior;
        y <= blob.cy + radioExterior;
        y++) {
      if (y < 0 || y >= h) {
        continue;
      }

      for (int x = blob.cx - radioExterior;
          x <= blob.cx + radioExterior;
          x++) {
        if (x < 0 || x >= w) {
          continue;
        }

        final double dx =
            (x - blob.cx).toDouble();

        final double dy =
            (y - blob.cy).toDouble();

        final double distancia =
            math.sqrt((dx * dx) + (dy * dy));

        final double brillo =
            luminancia[(y * w) + x].toDouble();

        if (distancia <= radioInterior) {
          sumaInterior += brillo;
          cantidadInterior++;
        } else if (distancia <= radioExterior) {
          sumaExterior += brillo;
          cantidadExterior++;
        }
      }
    }

    if (cantidadInterior == 0 ||
        cantidadExterior == 0) {
      return 0;
    }

    final double promedioInterior =
        sumaInterior / cantidadInterior;

    final double promedioExterior =
        sumaExterior / cantidadExterior;

    // Valor absoluto:
    // permite colonias claras Y colonias oscuras.
    return (promedioInterior -
            promedioExterior)
        .abs();
  }

  // ==============================================================
  // FLOOD FILL
  // ==============================================================

  static _Blob _floodFill(
    List<List<bool>> mascara,
    List<List<bool>> visitado,
    List<int> luminancia,
    int startX,
    int startY,
    int w,
    int h,
  ) {
    final List<List<int>> pila = [
      [startX, startY],
    ];

    visitado[startY][startX] = true;

    int area = 0;
    int perimetro = 0;

    int minX = startX;
    int maxX = startX;

    int minY = startY;
    int maxY = startY;

    int sumaX = 0;
    int sumaY = 0;

    // Para calcular la uniformidad interna (Filtro 8).
    double sumaLuminancia = 0;
    double sumaLuminancia2 = 0;

    const List<List<int>> vecinos = [
      [1, 0],
      [-1, 0],
      [0, 1],
      [0, -1],
      [1, 1],
      [-1, -1],
      [1, -1],
      [-1, 1],
    ];

    // Solo 4 direcciones (arriba/abajo/izq/der) para medir el
    // perímetro real de la mancha.
    const List<List<int>> vecinos4 = [
      [1, 0],
      [-1, 0],
      [0, 1],
      [0, -1],
    ];

    while (pila.isNotEmpty) {
      final List<int> punto =
          pila.removeLast();

      final int x = punto[0];
      final int y = punto[1];

      area++;

      sumaX += x;
      sumaY += y;

      final double brilloPixel =
          luminancia[(y * w) + x].toDouble();

      sumaLuminancia += brilloPixel;
      sumaLuminancia2 += brilloPixel * brilloPixel;

      if (x < minX) minX = x;
      if (x > maxX) maxX = x;

      if (y < minY) minY = y;
      if (y > maxY) maxY = y;

      // ------------------------------------------------------
      // Contar perímetro: un píxel cuenta como "borde" si al
      // menos uno de sus 4 vecinos directos NO es parte de
      // la mancha (o está fuera de la imagen).
      // ------------------------------------------------------
      for (final List<int> v4 in vecinos4) {
        final int nx4 = x + v4[0];
        final int ny4 = y + v4[1];

        if (nx4 < 0 ||
            nx4 >= w ||
            ny4 < 0 ||
            ny4 >= h ||
            !mascara[ny4][nx4]) {
          perimetro++;
        }
      }

      for (final List<int> vecino in vecinos) {
        final int nx = x + vecino[0];
        final int ny = y + vecino[1];

        if (nx < 0 ||
            nx >= w ||
            ny < 0 ||
            ny >= h) {
          continue;
        }

        if (mascara[ny][nx] &&
            !visitado[ny][nx]) {
          visitado[ny][nx] = true;

          pila.add([
            nx,
            ny,
          ]);
        }
      }
    }

    final int cx = area > 0
        ? (sumaX / area).round()
        : startX;

    final int cy = area > 0
        ? (sumaY / area).round()
        : startY;

    final int ancho =
        maxX - minX + 1;

    final int alto =
        maxY - minY + 1;

    final int radio =
        math.max(
      2,
      ((ancho + alto) / 4).round(),
    ).clamp(2, 45);

    // Desviación estándar de luminancia dentro de la mancha.
    double desviacionInterna = 0;

    if (area > 0) {
      final double media = sumaLuminancia / area;
      final double varianza =
          (sumaLuminancia2 / area) - (media * media);

      desviacionInterna =
          varianza > 0 ? math.sqrt(varianza) : 0;
    }

    return _Blob(
      area: area,
      cx: cx,
      cy: cy,
      radio: radio,
      ancho: ancho,
      alto: alto,
      perimetro: perimetro,
      desviacionInterna: desviacionInterna,
    );
  }
}

class _Blob {
  final int area;

  final int cx;
  final int cy;

  final int radio;

  final int ancho;
  final int alto;

  final int perimetro;

  final double desviacionInterna;

  _Blob({
    required this.area,
    required this.cx,
    required this.cy,
    required this.radio,
    required this.ancho,
    required this.alto,
    required this.perimetro,
    required this.desviacionInterna,
  });
}