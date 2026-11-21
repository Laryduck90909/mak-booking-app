import 'package:flutter_test/flutter_test.dart';
import 'package:mak_booking/data/catalog_data.dart';

void main() {
  test('catalog contains all required content', () {
    expect(CatalogData.services, hasLength(75));
    expect(CatalogData.mockups, hasLength(68));
    expect(CatalogData.styles, hasLength(19));
    expect(CatalogData.briefQuestions, hasLength(30));
    expect(CatalogData.styles.any((style) => style.id == 'graphity'), isTrue);
  });

  test('service prices use the three agreed tiers', () {
    final prices = CatalogData.services.map((item) => item.unitPrice).toSet();
    expect(prices, {300.0, 700.0, 1800.0});
    expect(CatalogData.services.map((item) => item.key).toSet(), hasLength(75));
  });
}
