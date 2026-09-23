import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/models/backend_status.dart';
import 'package:kossotrik/models/charge_box.dart';
import 'package:kossotrik/models/connector.dart';

import 'fixtures.dart';

Connector _connector({int status = 1, Object? estimasi}) => ChargeBox.fromJson(
      chargeBoxJson(
        connectors: [connectorJson(status: status, estimasi: estimasi)],
      ),
      number: 1,
    ).connectors.single;

void main() {
  group('status konektor dari /list-chargerbox', () {
    test('status 1 berarti bisa dipakai', () {
      final c = _connector();

      expect(c.status, ConnectorStatus.available);
      expect(c.isAvailable, isTrue);
      expect(c.isSelectable, isTrue);
      expect(c.statusCode, 1);
    });

    test('status 2 berarti menunggu konektor dihubungkan', () {
      final c = _connector(status: 2);

      expect(c.status, ConnectorStatus.preparing);
      expect(c.isPreparing, isTrue);
      // Sudah diklaim orang lain, tapi tetap bisa ditekan — lewat
      // verifikasi kode sesi.
      expect(c.isAvailable, isFalse);
      expect(c.isSelectable, isTrue);
    });

    test('status 3 berarti sedang mengisi', () {
      final c = _connector(status: 3);

      expect(c.status, ConnectorStatus.inUse);
      expect(c.isInUse, isTrue);
      expect(c.isAvailable, isFalse);
      expect(c.isSelectable, isTrue);
    });

    test('status 4 berarti pengisian selesai', () {
      final c = _connector(status: 4);

      expect(c.status, ConnectorStatus.finished);
      expect(c.isFinished, isTrue);
      expect(c.isAvailable, isFalse);
      expect(c.isSelectable, isTrue);
    });

    test('status 0 berarti sedang dipesan', () {
      final c = _connector(status: 0);

      expect(c.status, ConnectorStatus.reserved);
      expect(c.isReserved, isTrue);
      // Sudah diklaim, tapi pemiliknya harus bisa kembali.
      expect(c.isAvailable, isFalse);
      expect(c.isSelectable, isTrue);
    });

    test('angka di luar kelimanya tidak bisa ditekan', () {
      for (final status in [5, 9, 99]) {
        final c = _connector(status: status);
        expect(c.status, ConnectorStatus.unavailable, reason: '$status');
        expect(c.isSelectable, isFalse, reason: '$status');
      }
    });

    test('status yang hilang diperlakukan seperti bebas', () {
      expect(Connector.mapStatus(null), ConnectorStatus.available);
    });

    test('nomor konektor dari teks diurai jadi angka', () {
      final box = ChargeBox.fromJson(
        chargeBoxJson(
          connectors: [
            connectorJson(id: '1'),
            connectorJson(id: '2', nama: 'Gun 2'),
          ],
        ),
        number: 1,
      );

      // /start, /stop, dan /progress menerimanya sebagai angka.
      expect(box.connectors.map((c) => c.id), [1, 2]);
    });

    test('nama, tipe, dan jenis arus dibaca dari backend', () {
      final c = _connector();

      expect(c.name, 'Gun 1');
      expect(c.typeConnector, 'CCS2');
      expect(c.currentType, 'DC');
      expect(c.typeLabel, 'CCS2 · DC');
    });

    test('tanpa nama, jatuh ke nomor konektor', () {
      final c = ChargeBox.fromJson({
        'chargeBoxId': 'CB-SMR-01',
        'connectors': [
          {'connectorId': '3', 'status': 1},
        ],
      }, number: 1).connectors.single;

      expect(c.name, 'Konektor 3');
      expect(c.typeLabel, isEmpty);
    });

    test('estimationAvailable jadi perkiraan menit bila ada', () {
      expect(_connector(estimasi: 15).estimatedMinutes, 15);
      expect(_connector(estimasi: '20').estimatedMinutes, 20);
      expect(_connector().estimatedMinutes, isNull);
    });
  });

  group('ketersediaan charge box', () {
    test('kartu mati bila semua status konektornya tak dikenal', () {
      final box = ChargeBox.fromJson(
        chargeBoxJson(
          connectors: [
            connectorJson(id: '1', status: 5),
            connectorJson(id: '2', status: 9),
          ],
        ),
        number: 1,
      );

      expect(box.isAvailable, isFalse);
    });

    test('satu konektor yang dikenal sudah cukup', () {
      final box = ChargeBox.fromJson(
        chargeBoxJson(
          connectors: [
            connectorJson(id: '1', status: 9),
            connectorJson(id: '2', status: 1),
          ],
        ),
        number: 1,
      );

      expect(box.isAvailable, isTrue);
    });

    /// Kartu tetap bisa ditekan saat konektornya sedang melayani sesi —
    /// pemilik sesi harus bisa masuk lagi lewat verifikasi kode.
    test('konektor yang sedang mengisi tidak mematikan kartunya', () {
      final box = ChargeBox.fromJson(
        chargeBoxJson(connectors: [connectorJson(status: 3)]),
        number: 1,
      );

      expect(box.isAvailable, isTrue);
    });

    test('charge box yang dimatikan tidak bisa dipakai', () {
      final box = ChargeBox.fromJson(
        chargeBoxJson(isActive: false),
        number: 1,
      );

      expect(box.isAvailable, isFalse);
    });

    test('nama, merek, dan daya dibaca dari backend', () {
      final box = ChargeBox.fromJson(chargeBoxJson(), number: 4);

      expect(box.id, 'CB-SMR-01');
      expect(box.name, 'Kempower Satellite 200 kW');
      expect(box.merek, 'Kempower');
      expect(box.daya, '200 kW');
      expect(box.badge, '04');
      expect(box.connectorLabel, '1 Konektor');
    });

    /// Ejaan `chargeBoxId`/`namaChargeBox` dipakai versi backend
    /// sebelumnya; keduanya harus tetap terbaca.
    test('ejaan lama masih diterima', () {
      final box = ChargeBox.fromJson(const {
        'chargeBoxId': 'CB-LAMA',
        'namaChargeBox': 'Charger Lama',
        'connectors': [
          {'connectorId': '1', 'status': 1, 'estimationAvailable': 15},
        ],
      }, number: 1);

      expect(box.id, 'CB-LAMA');
      expect(box.name, 'Charger Lama');
      expect(box.connectors.single.estimatedMinutes, 15);
    });

    test('keterangan konektor memakai daya charge box', () {
      final box = ChargeBox.fromJson(chargeBoxJson(), number: 1);

      expect(
        box.connectors.single.describeWith(box.daya),
        'CCS2 - 200 kW DC',
      );
    });

    test('tanpa daya, jatuh ke tipe dan arusnya saja', () {
      final box = ChargeBox.fromJson(chargeBoxJson(daya: ''), number: 1);

      expect(box.connectors.single.describeWith(box.daya), 'CCS2 · DC');
    });
  });

  group('BackendStatus', () {
    test('status yang hilang dianggap bisa dipakai', () {
      expect(BackendStatus.isUsable(null), isTrue);
    });

    test('angka dibaca dari number maupun teks', () {
      expect(BackendStatus.parse(1), 1);
      expect(BackendStatus.parse('2'), 2);
      expect(BackendStatus.parse('bukan angka'), isNull);
      expect(BackendStatus.parse(null), isNull);
    });
  });
}
