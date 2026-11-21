import 'package:flutter_test/flutter_test.dart';
import 'package:mak_booking/data/catalog_data.dart';
import 'package:mak_booking/features/requests/wizard_controller.dart';

void main() {
  test('wizard validates each step and computes total and deposit', () {
    final controller = WizardController();
    expect(controller.next(), 'validationServices');
    controller.toggleService(CatalogData.services[2]);
    controller.toggleService(CatalogData.services[0]);
    controller.quantity(CatalogData.services[0].key, 1);
    expect(controller.state.total, 2400);
    expect(controller.next(), isNull);
    controller.toggleMockup(CatalogData.mockups.first.id);
    expect(controller.next(), isNull);
    controller.toggleStyle('graphity');
    expect(controller.next(), isNull);
    expect(controller.next(), 'validationColors');
    for (final color in CatalogData.palette.take(3)) {
      controller.toggleColor(color);
    }
    expect(controller.next(), isNull);
    for (final question in CatalogData.briefQuestions) {
      controller.answer(question.id, 'إجابة تجريبية');
    }
    expect(controller.next(), isNull);
    expect(controller.next(), isNull);
    expect(controller.next(), isNull);
    expect(controller.state.step, 5);
    final request = controller.buildRequest('client-id');
    expect(request.total, 2400);
    expect(request.deposit, 240);
    expect(request.remaining, 2160);
    expect(request.brief, hasLength(30));
  });
}
