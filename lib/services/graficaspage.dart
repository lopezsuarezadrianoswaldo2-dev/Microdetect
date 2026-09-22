import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class GraficaPageBonita extends StatelessWidget {
  // Datos simulados reales
  final List<Map<String, dynamic>> datos = [
    {'hora': 1, 'conteo': 10},
    {'hora': 2, 'conteo': 20},
    {'hora': 3, 'conteo': 35},
    {'hora': 4, 'conteo': 50},
    {'hora': 5, 'conteo': 70},
    {'hora': 6, 'conteo': 90},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Gráfica de Conteo",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: datos.last["conteo"].toDouble(), // máximo conteo
            minY: 0,
            maxY: datos.last["hora"].toDouble(), // última hora

            gridData: FlGridData(show: true),

            borderData: FlBorderData(
              show: true,
              border: Border.all(color: Colors.black12, width: 1),
            ),

            titlesData: FlTitlesData(
              // EJE X → Conteo
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  reservedSize: 32,
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    return Text(
                      "${value.toInt()}",
                      style: TextStyle(fontSize: 12),
                    );
                  },
                ),
              ),

              // EJE Y → Horas
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  reservedSize: 40,
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    return Text(
                      "${value.toInt()} h",
                      style: TextStyle(fontSize: 12),
                    );
                  },
                ),
              ),

              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),

            lineBarsData: [
              LineChartBarData(
                isCurved: true,
                barWidth: 4,
                color: Colors.blueAccent,
                dotData: FlDotData(show: true),
                belowBarData: BarAreaData(
                  show: true,
                  color: Colors.blue.withOpacity(0.2),
                ),

                // IMPORTANTÍSIMO:
                // Gráfica basada en X = conteo, Y = hora
                spots: datos
                    .map(
                      (p) => FlSpot(
                        p['conteo'].toDouble(), // eje X
                        p['hora'].toDouble(),   // eje Y
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
