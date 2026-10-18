// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:bioconteo_colonias_bacterinas/services/plan_service.dart';

void main() {
  test('PlanService.fromId devuelve el plan correcto', () {
    expect(PlanService.fromId('premium'), AppPlan.premium);
    expect(PlanService.fromId('intermedio'), AppPlan.intermedio);
    expect(PlanService.fromId(null), AppPlan.basico);
  });

  test('Permisos por plan', () {
    expect(PlanService.tieneHistorial(AppPlan.basico), false);
    expect(PlanService.tieneHistorial(AppPlan.intermedio), true);
    expect(PlanService.tieneGraficas(AppPlan.intermedio), false);
    expect(PlanService.tieneIA(AppPlan.premium), true);
  });
}