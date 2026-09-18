import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/models/charge_box.dart';
import 'package:kossotrik/models/connector.dart';

Connector _connector(String status) => ChargeBox.fromJson({
      'id': 'SIM-456',
      'connectors': [
        {'id': 1, 'status': status, 'errorCode': 'NoError', 'session': null},
      ],
    }, number: 1).connectors.single;

void main() {
  group('status konektor dari /list', () {
    test('Available: bebas, belum tercolok, bisa dipakai', () {
      final c = _connector('Available');
      expect(c.status, ConnectorStatus.available);
      expect(c.isAvailable, isTrue);
      expect(c.isSelectable, isTrue);
      expect(c.isPluggedIn, isFalse);
    });

    test('Preparing: baru dicolok, ditekan untuk lanjut mulai mengisi', () {
      final c = _connector('Preparing');
      expect(c.status, ConnectorStatus.preparing);
      expect(c.isPreparing, isTrue);
      expect(c.isPluggedIn, isTrue);
      expect(c.isSelectable, isTrue);
      // Bukan "Available" — tujuannya berbeda.
      expect(c.isAvailable, isFalse);
    });

    test('Charging: ditekan untuk membuka layar pemantauan', () {
      final c = _connector('Charging');
      expect(c.status, ConnectorStatus.inUse);
      expect(c.isInUse, isTrue);
      expect(c.isPluggedIn, isTrue);
      expect(c.isSelectable, isTrue);
      expect(c.isAvailable, isFalse);
    });

    test('status lain tidak dianggap tercolok', () {
      for (final status in ['Finishing', 'Faulted', 'Unavailable', 'Reserved']) {
        expect(_connector(status).isPluggedIn, isFalse, reason: status);
      }
    });

    test('hanya konektor rusak atau dimatikan yang tidak bisa ditekan', () {
      for (final status in ['Faulted', 'Unavailable', 'Reserved']) {
        expect(_connector(status).isSelectable, isFalse, reason: status);
      }
    });

    test('kartu hanya dimatikan bila semua konektornya rusak/dimatikan', () {
      final unusable = ChargeBox.fromJson({
        'id': 'SIM-789',
        'connectors': [
          {'id': 1, 'status': 'Faulted', 'errorCode': 'GroundFailure'},
          {'id': 2, 'status': 'Unavailable', 'errorCode': 'NoError'},
        ],
      }, number: 1);
      expect(unusable.isAvailable, isFalse);

      // Satu-satunya konektor "Preparing" — kartunya tetap bisa
      // ditekan untuk melanjutkan ke layar mulai mengisi.
      final preparingOnly = ChargeBox.fromJson({
        'id': 'SIM-123',
        'connectors': [
          {'id': 1, 'status': 'Preparing', 'errorCode': 'NoError'},
        ],
      }, number: 1);
      expect(preparingOnly.isAvailable, isTrue);

      // errorCode tetap mengalahkan status apa pun.
      final faulted = ChargeBox.fromJson({
        'id': 'SIM-999',
        'connectors': [
          {'id': 1, 'status': 'Preparing', 'errorCode': 'GroundFailure'},
        ],
      }, number: 1);
      expect(faulted.isAvailable, isFalse);
    });
  });
}
