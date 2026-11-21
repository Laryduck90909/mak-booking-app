import 'package:flutter_test/flutter_test.dart';
import 'package:mak_booking/data/catalog_data.dart';
import 'package:mak_booking/models/design_request.dart';

void main() {
  test('request JSON survives a local cache round trip', () {
    final request = DesignRequest(
      id: '00000000-0000-4000-8000-000000000100',
      clientId: 'client-id',
      status: 'submitted',
      items: [CatalogData.services.first],
      mockups: const ['mockup_1'],
      styles: const ['minimal'],
      colors: const ['0B3B3A', 'FFCCBF', 'D9A441'],
      brief: const {'q01': 'M.A.K'},
      createdAt: DateTime.utc(2026, 10, 31),
      verificationCode: 'ABC123',
    );
    final restored = DesignRequest.fromJson(request.toJson());
    expect(restored.id, request.id);
    expect(restored.total, 300);
    expect(restored.items.single.titleAr, 'شعار أساسي');
    expect(restored.brief['q01'], 'M.A.K');
    expect(restored.verificationCode, 'ABC123');
  });
}
