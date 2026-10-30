import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

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

/// Cuenta colonias BLANCAS (más claras que su alrededor) en una caja Petri
/// y las marca con un círculo rojo.
///
/// CAMBIOS DE ESTA VERSIÓN (probados con dos fotos: una caja con ~200 colonias
/// sobre la mano y otra con ~1,200 colonias sobre mesa metálica):
///
///  1. FONDO ROBUSTO: el brillo del fondo se calcula en 2 pasadas. En la
///     primera se detectan pixeles candidatos y en la segunda se vuelve a
///     promediar EXCLUYÉNDOLOS. Antes, en cajas muy pobladas, las propias
///     colonias subían el promedio del fondo y las más tenues se perdían.
///  2. UMBRAL ADAPTATIVO: se estima el ruido de la foto con los pixeles más
///     oscuros que el fondo (ahí no hay colonias) y el umbral se ajusta solo,
///     entre [_umbralMin] y [_umbralMax]. Antes era fijo (22) y dejaba fuera
///     colonias translúcidas o poco contrastadas ("nubecitas").
///  3. FILTRO DE SATURACIÓN CORREGIDO: antes descartaba toda colonia cuya
///     saturación fuera >= 0.9 de la de su entorno. En un agar gris/metálico
///     las colonias cremas son MÁS saturadas que el fondo, así que se
///     descartaban casi todas (solo quedaban ~70 de ~1,200). Ahora el filtro
///     solo actúa cuando el entorno es realmente piel (saturación alta).
///  4. COLONIAS MÁS PEQUEÑAS: radio mínimo 1.5 px y separación mínima entre
///     colonias proporcional a su tamaño (antes 6 px fijos fusionaba
///     colonias diminutas vecinas).
///  5. COLONIAS GRANDES Y TRANSLÚCIDAS: umbral de contraste proporcional al
///     umbral adaptativo en vez de 28 fijo.
///  6. Reflejos del canto del vidrio: se descartan círculos pegados al borde
///     de la placa y manchas irregulares que no se explican como círculos.
///  7. Círculos de dibujo más ajustados (r+0) y línea fina para las chicas.
///  8. La posición de la placa ya no está fija: puede pasarse como parámetro.
class ColoniaCounter {
  /// Resolución utilizada para analizar la fotografía.
  static const int _anchoProceso = 900;

  /// Posición y tamaño de la placa dentro de la foto (relativos al ancho/alto
  /// de la imagen). Son los valores por defecto; pásalos como parámetros a
  /// [contar] si tu encuadre es distinto. Lo ideal es mostrar una guía
  /// circular en la cámara para que el usuario alinee la placa.
  ///
  /// Valores que funcionaron en las fotos de prueba:
  ///  * placa en la mano:      0.545, 0.525, 0.41
  ///  * placa sobre la mesa:   0.467, 0.500, 0.405
  static const double _centroXRel = 0.50;
  static const double _centroYRel = 0.52;
  static const double _radioRel = 0.41; // relativo al ANCHO

  /// Radio (px) de la ventana con la que se calcula el brillo del fondo
  /// (equivale a 45 px a 700 px de ancho).
  static const int _radioFondo = 58;

  /// Umbral adaptativo: cuánto más clara que el fondo debe ser un pixel.
  static const double _umbralMin = 7.0;
  static const double _umbralMax = 20.0;
  static const double _factorRuido = 2.5;

  /// Un pixel con diferencia > este valor se considera "posible colonia" y
  /// se excluye al recalcular el fondo en la segunda pasada.
  static const double _umbralExclusionFondo = 6.0;

  /// Radio mínimo (px) de una colonia.
  static const double _radioMinimo = 1.5;

  /// Saturación (0-255) a partir de la cual el entorno se considera piel y se
  /// activa el filtro anti-reflejo por saturación.
  static const double _saturacionPiel = 70.0;

  static Future<ResultadoConteo> contar(
    File archivoImagen, {
    double? centroXRel,
    double? centroYRel,
    double? radioRel,
  }) async {
    // ============================================================
    // 1. LEER IMAGEN (corrigiendo orientación) Y REESCALAR
    // ============================================================

    final Uint8List bytes = await archivoImagen.readAsBytes();
    final img.Image? decodificada = img.decodeImage(bytes);

    if (decodificada == null) {
      throw Exception('No se pudo leer la imagen.');
    }

    final img.Image original = img.bakeOrientation(decodificada);

    final img.Image imagen = img.copyResize(
      original,
      width: _anchoProceso,
      interpolation: img.Interpolation.average,
    );

    final int w = imagen.width;
    final int h = imagen.height;
    final int n = w * h;

    // ============================================================
    // 2. LUMINANCIA Y SATURACIÓN
    // ============================================================

    final Float64List lum = Float64List(n);
    final Float64List sat = Float64List(n);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final img.Pixel p = imagen.getPixel(x, y);
        final double r = p.r.toDouble();
        final double g = p.g.toDouble();
        final double b = p.b.toDouble();

        final int i = (y * w) + x;
        lum[i] = (0.299 * r) + (0.587 * g) + (0.114 * b);

        final double mx = math.max(r, math.max(g, b));
        final double mn = math.min(r, math.min(g, b));
        sat[i] = mx > 0 ? ((mx - mn) / mx) * 255.0 : 0.0;
      }
    }

    // ============================================================
    // 3. ZONA DE ANÁLISIS (círculo de la placa)
    // ============================================================

    final double cx = w * (centroXRel ?? _centroXRel);
    final double cy = h * (centroYRel ?? _centroYRel);
    final double radioPlaca = w * (radioRel ?? _radioRel);
    final double radioPlaca2 = radioPlaca * radioPlaca;

    final Uint8List zona = Uint8List(n);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final double dx = x - cx;
        final double dy = y - cy;

        if ((dx * dx) + (dy * dy) <= radioPlaca2) {
          zona[(y * w) + x] = 1;
        }
      }
    }

    // ============================================================
    // 4. CONTRASTE LOCAL POSITIVO (más claro que el fondo)
    //    con fondo en 2 pasadas y umbral adaptativo
    // ============================================================

    final Float64List integral = _integral(lum, w, h);

    // Luminancia suavizada (caja 3x3).
    final Float64List suave = Float64List(n);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final int i = (y * w) + x;

        if (zona[i] == 1) {
          suave[i] = _mediaCaja(integral, w, h, x, y, 1);
        }
      }
    }

    // --- Pasada 1: fondo con todo incluido, para localizar candidatos ---
    final Float64List fondo1 = Float64List(n);
    final Float64List lumValida = Float64List(n);
    final Float64List valida = Float64List(n);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final int i = (y * w) + x;

        if (zona[i] == 0) {
          continue;
        }

        fondo1[i] = _mediaCaja(integral, w, h, x, y, _radioFondo);

        // Solo cuentan para el fondo los pixeles de la placa que NO parecen
        // colonia.
        if (suave[i] - fondo1[i] <= _umbralExclusionFondo) {
          valida[i] = 1.0;
          lumValida[i] = lum[i];
        }
      }
    }

    // --- Pasada 2: fondo promediando solo pixeles sin colonia ---
    final Float64List integralLumValida = _integral(lumValida, w, h);
    final Float64List integralValida = _integral(valida, w, h);

    final Float64List dif = Float64List(n);

    double sumaCuadradosNegativos = 0;
    int cantidadNegativos = 0;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final int i = (y * w) + x;

        if (zona[i] == 0) {
          continue;
        }

        final double fraccion =
            _mediaCaja(integralValida, w, h, x, y, _radioFondo);

        double fondo = fondo1[i];

        if (fraccion > 0.05) {
          fondo = _mediaCaja(integralLumValida, w, h, x, y, _radioFondo) /
              fraccion;
        }

        final double d = suave[i] - fondo;
        dif[i] = d;

        if (d < 0) {
          sumaCuadradosNegativos += d * d;
          cantidadNegativos++;
        }
      }
    }

    // Ruido estimado con la mitad "oscura" (ahí no hay colonias blancas).
    final double sigma = cantidadNegativos > 0
        ? math.sqrt(sumaCuadradosNegativos / cantidadNegativos)
        : (_umbralMin / _factorRuido);

    final double umbral = (sigma * _factorRuido).clamp(_umbralMin, _umbralMax);

    Uint8List mascara = Uint8List(n);

    for (int i = 0; i < n; i++) {
      if (zona[i] == 1 && dif[i] >= umbral) {
        mascara[i] = 1;
      }
    }

    // ============================================================
    // 5. LIMPIEZA: cerrar huecos pequeños y rellenar el interior
    // ============================================================

    mascara = _erosionar(_dilatar(mascara, w, h), w, h);
    mascara = _rellenarHuecos(mascara, w, h);

    for (int i = 0; i < n; i++) {
      if (zona[i] == 0) {
        mascara[i] = 0;
      }
    }

    // ============================================================
    // 6. COMPONENTES CONECTADOS (con momentos para partir manchas)
    // ============================================================

    final Int32List etiqueta = Int32List(n);
    final List<int> area = <int>[0];
    final List<double> sumaX = <double>[0];
    final List<double> sumaY = <double>[0];
    final List<double> sumaXX = <double>[0];
    final List<double> sumaYY = <double>[0];
    final List<double> sumaXY = <double>[0];
    final List<bool> tocaBorde = <bool>[false];

    int totalComponentes = 0;

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final int inicio = (y * w) + x;

        if (mascara[inicio] == 0 || etiqueta[inicio] != 0) {
          continue;
        }

        totalComponentes++;
        final int k = totalComponentes;

        int a = 0;
        double sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0;
        bool borde = false;

        final List<int> pila = <int>[inicio];
        etiqueta[inicio] = k;

        while (pila.isNotEmpty) {
          final int i = pila.removeLast();
          final int px = i % w;
          final int py = i ~/ w;

          a++;
          sx += px;
          sy += py;
          sxx += px * px;
          syy += py * py;
          sxy += px * py;

          final double dx = px - cx;
          final double dy = py - cy;

          if (math.sqrt((dx * dx) + (dy * dy)) > radioPlaca - 6) {
            borde = true;
          }

          for (int oy = -1; oy <= 1; oy++) {
            for (int ox = -1; ox <= 1; ox++) {
              if (ox == 0 && oy == 0) {
                continue;
              }

              final int nx = px + ox;
              final int ny = py + oy;

              if (nx < 0 || nx >= w || ny < 0 || ny >= h) {
                continue;
              }

              final int j = (ny * w) + nx;

              if (mascara[j] == 1 && etiqueta[j] == 0) {
                etiqueta[j] = k;
                pila.add(j);
              }
            }
          }
        }

        area.add(a);
        sumaX.add(sx);
        sumaY.add(sy);
        sumaXX.add(sxx);
        sumaYY.add(syy);
        sumaXY.add(sxy);
        tocaBorde.add(borde);
      }
    }

    // ============================================================
    // 7. TRANSFORMADA DE DISTANCIA: cada máximo local = una colonia
    //    (separa colonias pegadas y da el radio de cada una)
    // ============================================================

    final Float64List dist2 = _distanciaCuadrada(mascara, w, h);
    final Float64List dt = Float64List(n);

    for (int i = 0; i < n; i++) {
      dt[i] = math.sqrt(dist2[i]);
    }

    final List<int> candidatos = <int>[];

    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final int i = (y * w) + x;

        if (mascara[i] == 0 || dt[i] < _radioMinimo) {
          continue;
        }

        final double v = dt[i];
        bool esMaximo = true;

        for (int oy = -1; oy <= 1 && esMaximo; oy++) {
          for (int ox = -1; ox <= 1; ox++) {
            if (dt[((y + oy) * w) + (x + ox)] > v) {
              esMaximo = false;
              break;
            }
          }
        }

        if (esMaximo) {
          candidatos.add(i);
        }
      }
    }

    candidatos.sort((a, b) => dt[b].compareTo(dt[a]));

    final List<_Circulo> aceptados = <_Circulo>[];

    for (final int i in candidatos) {
      final double x = (i % w).toDouble();
      final double y = (i ~/ w).toDouble();
      final double r = dt[i];

      bool libre = true;

      for (final _Circulo c in aceptados) {
        final double d = math.sqrt(
          ((x - c.x) * (x - c.x)) + ((y - c.y) * (y - c.y)),
        );

        // Separación mínima proporcional al tamaño: evita duplicar una misma
        // colonia sin fusionar colonias diminutas vecinas.
        if (d < math.max(3.0, 0.8 * (r + c.radio))) {
          libre = false;
          break;
        }
      }

      if (libre) {
        aceptados.add(_Circulo(x, y, r, etiqueta[i]));
      }
    }

    // ============================================================
    // 8. PARTIR MANCHAS ALARGADAS (dos colonias encimadas que solo
    //    produjeron un máximo)
    // ============================================================

    final Map<int, int> circulosPorComponente = <int, int>{};

    for (final _Circulo c in aceptados) {
      circulosPorComponente[c.comp] =
          (circulosPorComponente[c.comp] ?? 0) + 1;
    }

    final List<_Circulo> circulos = <_Circulo>[];

    for (final _Circulo c in aceptados) {
      final int k = c.comp;

      if (k > 0 &&
          circulosPorComponente[k] == 1 &&
          area[k] > 1.5 * math.pi * (c.radio + 1) * (c.radio + 1)) {
        final double a = area[k].toDouble();
        final double mx = sumaX[k] / a;
        final double my = sumaY[k] / a;

        final double vxx = (sumaXX[k] / a) - (mx * mx);
        final double vyy = (sumaYY[k] / a) - (my * my);
        final double vxy = (sumaXY[k] / a) - (mx * my);

        final double media = (vxx + vyy) / 2;
        final double raiz = math.sqrt(
          (((vxx - vyy) / 2) * ((vxx - vyy) / 2)) + (vxy * vxy),
        );

        final double l1 = media + raiz;
        final double l2 = media - raiz;

        final double largo = 4 * math.sqrt(math.max(l1, 1e-6));
        final double ancho = 4 * math.sqrt(math.max(l2, 1e-6));
        final double proporcion = largo / ancho;

        if (proporcion >= 1.25 && proporcion <= 3.5) {
          double ux;
          double uy;

          if (vxy.abs() > 1e-9) {
            ux = l1 - vyy;
            uy = vxy;
          } else if (vxx >= vyy) {
            ux = 1;
            uy = 0;
          } else {
            ux = 0;
            uy = 1;
          }

          final double norma = math.sqrt((ux * ux) + (uy * uy));
          ux /= norma;
          uy /= norma;

          final double desplazamiento = (largo / 2) - (ancho / 2);
          final double radioNuevo = (ancho / 2) - 1;

          circulos.add(_Circulo(
            mx + (ux * desplazamiento),
            my + (uy * desplazamiento),
            radioNuevo,
            k,
          ));

          circulos.add(_Circulo(
            mx - (ux * desplazamiento),
            my - (uy * desplazamiento),
            radioNuevo,
            k,
          ));

          continue;
        }
      }

      circulos.add(c);
    }

    // ============================================================
    // 9. FILTROS DE REFLEJOS Y FALSOS POSITIVOS
    // ============================================================

    // Cuánto de cada mancha explican los círculos encontrados.
    final Map<int, double> cubierto = <int, double>{};
    final Map<int, int> circulosPorMancha = <int, int>{};

    for (final _Circulo c in circulos) {
      cubierto[c.comp] = (cubierto[c.comp] ?? 0) +
          (math.pi * (c.radio + 1) * (c.radio + 1));

      circulosPorMancha[c.comp] = (circulosPorMancha[c.comp] ?? 0) + 1;
    }

    final List<_Circulo> colonias = <_Circulo>[];

    for (final _Circulo c in circulos) {
      final int k = c.comp;

      if (k > 0) {
        // Mancha irregular grande que no se parece a círculos (reflejo).
        // Las manchas diminutas se dejan pasar: su área es muy ruidosa.
        if (area[k] > 40 && (cubierto[k] ?? 0) / area[k] < 0.45) {
          continue;
        }

        // Arco pegado al borde de la placa con varios "círculos":
        // es el brillo del canto del vidrio.
        if (tocaBorde[k] && (circulosPorMancha[k] ?? 0) >= 2) {
          continue;
        }
      }

      // Círculos centrados justo en el borde de la placa = canto del vidrio.
      final double dxc = c.x - cx;
      final double dyc = c.y - cy;
      final double distanciaCentro = math.sqrt((dxc * dxc) + (dyc * dyc));

      if (distanciaCentro > radioPlaca - 5) {
        continue;
      }

      final double radio = c.radio + 2;

      final double contraste = _contrasteCirculo(
        lum,
        mascara,
        w,
        h,
        c.x,
        c.y,
        radio,
      );

      // El contraste mínimo depende del umbral adaptativo de esta foto.
      // Las colonias grandes (translúcidas) exigen un poco más para no
      // confundirlas con reflejos.
      final double contrasteMinimo =
          math.max(0.6 * umbral, 6.0) * (radio >= 8 ? 1.6 : 1.0);

      if (contraste < contrasteMinimo) {
        continue;
      }

      // Reflejo sobre la piel: conserva la saturación de la piel.
      // Solo se aplica cuando el entorno ES piel (saturación alta); sobre
      // agar gris o mesa metálica este filtro no tiene sentido.
      final double ratioSaturacion = _ratioSaturacion(
        sat,
        mascara,
        w,
        h,
        c.x,
        c.y,
        radio,
      );

      if (ratioSaturacion > 0.9) {
        continue;
      }

      colonias.add(_Circulo(c.x, c.y, radio, k));
    }

    // ============================================================
    // 10. DIBUJAR CÍRCULOS ROJOS
    // ============================================================

    final img.Image marcada = img.copyResize(
      original,
      width: _anchoProceso,
      interpolation: img.Interpolation.average,
    );

    for (final _Circulo c in colonias) {
      final int r = c.radio.round();

      // Colonias chicas: línea fina. Colonias grandes: dos círculos
      // concéntricos = línea un poco más gruesa.
      final int vueltas = c.radio >= 6 ? 1 : 0;

      for (int extra = 0; extra <= vueltas; extra++) {
        img.drawCircle(
          marcada,
          x: c.x.round(),
          y: c.y.round(),
          radius: r + extra,
          color: img.ColorRgb8(255, 0, 0),
        );
      }
    }

    // ============================================================
    // 11. GENERAR JPG
    // ============================================================

    final Uint8List jpgMarcada = Uint8List.fromList(
      img.encodeJpg(
        marcada,
        quality: 90,
      ),
    );

    return ResultadoConteo(
      conteo: colonias.length,
      imagenProcesada: jpgMarcada,
    );
  }

  // ==============================================================
  // IMAGEN INTEGRAL Y PROMEDIO DE CAJA
  // ==============================================================

  static Float64List _integral(Float64List datos, int w, int h) {
    final int iw = w + 1;
    final Float64List r = Float64List((w + 1) * (h + 1));

    for (int y = 1; y <= h; y++) {
      double fila = 0;

      for (int x = 1; x <= w; x++) {
        fila += datos[((y - 1) * w) + (x - 1)];
        r[(y * iw) + x] = r[((y - 1) * iw) + x] + fila;
      }
    }

    return r;
  }

  /// Promedio de una ventana cuadrada de radio [rad] centrada en (x, y),
  /// recortada a los bordes de la imagen.
  static double _mediaCaja(
    Float64List integral,
    int w,
    int h,
    int x,
    int y,
    int rad,
  ) {
    final int iw = w + 1;

    final int x1 = math.max(0, x - rad);
    final int y1 = math.max(0, y - rad);
    final int x2 = math.min(w - 1, x + rad);
    final int y2 = math.min(h - 1, y + rad);

    final double suma = integral[((y2 + 1) * iw) + (x2 + 1)] -
        integral[(y1 * iw) + (x2 + 1)] -
        integral[((y2 + 1) * iw) + x1] +
        integral[(y1 * iw) + x1];

    return suma / ((x2 - x1 + 1) * (y2 - y1 + 1));
  }

  // ==============================================================
  // MORFOLOGÍA
  // ==============================================================

  static Uint8List _dilatar(Uint8List m, int w, int h) {
    final Uint8List salida = Uint8List(m.length);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        bool alguno = false;

        for (int oy = -1; oy <= 1 && !alguno; oy++) {
          final int yy = y + oy;

          if (yy < 0 || yy >= h) {
            continue;
          }

          for (int ox = -1; ox <= 1; ox++) {
            final int xx = x + ox;

            if (xx < 0 || xx >= w) {
              continue;
            }

            if (m[(yy * w) + xx] == 1) {
              alguno = true;
              break;
            }
          }
        }

        if (alguno) {
          salida[(y * w) + x] = 1;
        }
      }
    }

    return salida;
  }

  static Uint8List _erosionar(Uint8List m, int w, int h) {
    final Uint8List salida = Uint8List(m.length);

    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        bool todos = true;

        for (int oy = -1; oy <= 1 && todos; oy++) {
          final int yy = y + oy;

          if (yy < 0 || yy >= h) {
            todos = false;
            break;
          }

          for (int ox = -1; ox <= 1; ox++) {
            final int xx = x + ox;

            if (xx < 0 || xx >= w || m[(yy * w) + xx] == 0) {
              todos = false;
              break;
            }
          }
        }

        if (todos) {
          salida[(y * w) + x] = 1;
        }
      }
    }

    return salida;
  }

  /// Rellena los huecos internos de las manchas (por ejemplo, el brillo
  /// central de una colonia).
  static Uint8List _rellenarHuecos(Uint8List m, int w, int h) {
    final Uint8List fuera = Uint8List(m.length);
    final List<int> pila = <int>[];

    void sembrar(int i) {
      if (m[i] == 0 && fuera[i] == 0) {
        fuera[i] = 1;
        pila.add(i);
      }
    }

    for (int x = 0; x < w; x++) {
      sembrar(x);
      sembrar(((h - 1) * w) + x);
    }

    for (int y = 0; y < h; y++) {
      sembrar(y * w);
      sembrar((y * w) + (w - 1));
    }

    const List<List<int>> vecinos4 = [
      [1, 0],
      [-1, 0],
      [0, 1],
      [0, -1],
    ];

    while (pila.isNotEmpty) {
      final int i = pila.removeLast();
      final int x = i % w;
      final int y = i ~/ w;

      for (final List<int> v in vecinos4) {
        final int nx = x + v[0];
        final int ny = y + v[1];

        if (nx < 0 || nx >= w || ny < 0 || ny >= h) {
          continue;
        }

        sembrar((ny * w) + nx);
      }
    }

    final Uint8List salida = Uint8List(m.length);

    for (int i = 0; i < m.length; i++) {
      salida[i] = (m[i] == 1 || fuera[i] == 0) ? 1 : 0;
    }

    return salida;
  }

  // ==============================================================
  // TRANSFORMADA DE DISTANCIA EUCLIDIANA (exacta, Felzenszwalb)
  //
  // Devuelve, para cada pixel de la máscara, la distancia AL CUADRADO
  // al pixel de fondo más cercano.
  // ==============================================================

  static Float64List _distanciaCuadrada(Uint8List m, int w, int h) {
    const double inf = 1e12;

    final int mayor = math.max(w, h);

    final Float64List g = Float64List(w * h);
    final Float64List f = Float64List(mayor);
    final Float64List d = Float64List(mayor);
    final Int32List v = Int32List(mayor);
    final Float64List z = Float64List(mayor + 1);

    // Columnas.
    for (int x = 0; x < w; x++) {
      for (int y = 0; y < h; y++) {
        f[y] = m[(y * w) + x] == 1 ? inf : 0.0;
      }

      _edt1d(f, h, d, v, z);

      for (int y = 0; y < h; y++) {
        g[(y * w) + x] = d[y];
      }
    }

    // Filas.
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        f[x] = g[(y * w) + x];
      }

      _edt1d(f, w, d, v, z);

      for (int x = 0; x < w; x++) {
        g[(y * w) + x] = d[x];
      }
    }

    return g;
  }

  static void _edt1d(
    Float64List f,
    int n,
    Float64List d,
    Int32List v,
    Float64List z,
  ) {
    int k = 0;

    v[0] = 0;
    z[0] = -1e30;
    z[1] = 1e30;

    for (int q = 1; q < n; q++) {
      double s = ((f[q] + (q * q)) - (f[v[k]] + (v[k] * v[k]))) /
          ((2.0 * q) - (2.0 * v[k]));

      while (s <= z[k]) {
        k--;

        s = ((f[q] + (q * q)) - (f[v[k]] + (v[k] * v[k]))) /
            ((2.0 * q) - (2.0 * v[k]));
      }

      k++;
      v[k] = q;
      z[k] = s;
      z[k + 1] = 1e30;
    }

    k = 0;

    for (int q = 0; q < n; q++) {
      while (z[k + 1] < q) {
        k++;
      }

      final double dq = (q - v[k]).toDouble();
      d[q] = (dq * dq) + f[v[k]];
    }
  }

  // ==============================================================
  // CONTRASTE: brillo interior menos brillo del fondo real
  // (el anillo exterior ignora pixeles que pertenecen a otras manchas)
  // ==============================================================

  static double _contrasteCirculo(
    Float64List lum,
    Uint8List mascara,
    int w,
    int h,
    double cx,
    double cy,
    double radio,
  ) {
    final double ri = math.max(radio, 2.0);
    final double ro = math.max(ri + 6, (ri * 2.2).roundToDouble());

    double sumaInterior = 0;
    int cantidadInterior = 0;

    double sumaAnilloFondo = 0;
    int cantidadAnilloFondo = 0;

    double sumaAnilloTodo = 0;
    int cantidadAnilloTodo = 0;

    final int y1 = math.max(0, (cy - ro).floor());
    final int y2 = math.min(h - 1, (cy + ro).ceil());
    final int x1 = math.max(0, (cx - ro).floor());
    final int x2 = math.min(w - 1, (cx + ro).ceil());

    for (int y = y1; y <= y2; y++) {
      for (int x = x1; x <= x2; x++) {
        final double dx = x - cx;
        final double dy = y - cy;
        final double d = math.sqrt((dx * dx) + (dy * dy));

        final int i = (y * w) + x;

        if (d <= ri) {
          sumaInterior += lum[i];
          cantidadInterior++;
        } else if (d <= ro) {
          sumaAnilloTodo += lum[i];
          cantidadAnilloTodo++;

          if (mascara[i] == 0) {
            sumaAnilloFondo += lum[i];
            cantidadAnilloFondo++;
          }
        }
      }
    }

    if (cantidadInterior == 0 || cantidadAnilloTodo == 0) {
      return 0;
    }

    final double anillo = cantidadAnilloFondo >= 8
        ? sumaAnilloFondo / cantidadAnilloFondo
        : sumaAnilloTodo / cantidadAnilloTodo;

    return (sumaInterior / cantidadInterior) - anillo;
  }

  // ==============================================================
  // SATURACIÓN: interior / exterior
  // Solo se evalúa si el entorno es piel (saturación alta). Una colonia
  // (blanca/crema) es más pálida que la piel que la rodea: ratio < 1.
  // Un reflejo sobre piel: ratio cercano a 1.
  // Sobre agar gris o metal devuelve 0 (no se descarta nada).
  // ==============================================================

  static double _ratioSaturacion(
    Float64List sat,
    Uint8List mascara,
    int w,
    int h,
    double cx,
    double cy,
    double radio,
  ) {
    final double rExterior = (radio * 2.2) + 6;

    double sumaInterior = 0;
    int cantidadInterior = 0;

    double sumaExterior = 0;
    int cantidadExterior = 0;

    final int y1 = math.max(0, (cy - rExterior).floor());
    final int y2 = math.min(h - 1, (cy + rExterior).ceil());
    final int x1 = math.max(0, (cx - rExterior).floor());
    final int x2 = math.min(w - 1, (cx + rExterior).ceil());

    for (int y = y1; y <= y2; y++) {
      for (int x = x1; x <= x2; x++) {
        final double dx = x - cx;
        final double dy = y - cy;
        final double d = math.sqrt((dx * dx) + (dy * dy));

        final int i = (y * w) + x;

        if (d <= radio - 1) {
          sumaInterior += sat[i];
          cantidadInterior++;
        } else if (d > radio + 2 && d <= rExterior && mascara[i] == 0) {
          sumaExterior += sat[i];
          cantidadExterior++;
        }
      }
    }

    // Sin datos suficientes no se descarta nada.
    if (cantidadInterior == 0 || cantidadExterior <= 8) {
      return 0;
    }

    final double interior = sumaInterior / cantidadInterior;
    final double exterior = sumaExterior / cantidadExterior;

    // Entorno poco saturado (agar, metal, vidrio): no es piel, no filtrar.
    if (exterior <= _saturacionPiel) {
      return 0;
    }

    return interior / exterior;
  }
}

class _Circulo {
  final double x;
  final double y;
  final double radio;

  /// Mancha (componente conectado) de la que salió este círculo.
  final int comp;

  _Circulo(this.x, this.y, this.radio, this.comp);
}