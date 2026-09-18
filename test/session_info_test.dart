import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/models/charge_box.dart';
import 'package:kossotrik/models/connector.dart';

/// Payload nyata yang tertangkap dari `GET /list` saat SIM-456
/// konektor 2 sedang mengisi.
const _liveChargePoint = {
  'id': 'SIM-456',
  'vendor': 'Icon Digital',
  'model': 'OCPP Simulator',
  'serialNumber': 'SIM-456',
  'firmwareVersion': 'sim-1.0.0',
  'connectedAt': '2026-09-17T20:13:35.93237262+07:00',
  'lastHeartbeat': null,
  'connectors': [
    {'id': 1, 'status': 'Preparing', 'errorCode': 'NoError', 'session': null},
    {
      'id': 2,
      'status': 'Charging',
      'errorCode': 'NoError',
      'session': {
        'chargePointId': 'SIM-456',
        'connectorId': 2,
        'transactionId': 1789648926,
        'idTag': 'REMOTE',
        'state': 'charging',
        'connectorStatus': 'Charging',
        'percent': 20.1,
        'energyWh': 24,
        'powerW': 12330,
        'durationSeconds': 6,
        'stoppedAt': null,
        'updatedAt': '2026-09-17T20:13:51.943093729+07:00',
      },
    },
  ],
};

void main() {
  final box = ChargeBox.fromJson(
    Map<String, dynamic>.from(_liveChargePoint),
    number: 2,
  );
  final idle = box.connectors[0];
  final charging = box.connectors[1];

  test('konektor tanpa sesi tidak melaporkan energi', () {
    expect(idle.hasActiveSession, isFalse);
    expect(idle.sessionEnergyKwh, isNull);
    // "Preparing" bukan "Available", tapi tetap bisa ditekan — untuk
    // melanjutkan ke layar mulai mengisi.
    expect(idle.status, ConnectorStatus.preparing);
    expect(idle.isAvailable, isFalse);
    expect(idle.isSelectable, isTrue);
  });

  test('sesi berjalan diurai lengkap dari payload nyata', () {
    final session = charging.session!;

    expect(session.transactionId, 1789648926);
    expect(session.idTag, 'REMOTE');
    expect(session.state, 'charging');
    expect(session.isCharging, isTrue);
    expect(session.isFinished, isFalse);
    expect(session.percent, 20.1);
    expect(session.durationSeconds, 6);
    expect(session.updatedAt, isNotNull);
  });

  test('meter Wh dikonversi ke kWh untuk ditampilkan', () {
    expect(charging.session!.energyWh, 24);
    expect(charging.sessionEnergyKwh, 0.024);
    expect(charging.session!.powerKw, 12.33);
  });

  test('estimasi sisa waktu dihitung dari persen dan durasi', () {
    // 6 detik untuk 20,1% -> sisa 79,9% butuh ~24 detik -> dibulatkan 1 menit.
    expect(charging.estimatedMinutes, 1);
    expect(idle.estimatedMinutes, isNull);
  });

  test('charge box tetap bisa ditekan untuk melanjutkan sesi', () {
    // Konektor 1 "Preparing", konektor 2 "Charging" — dua-duanya punya
    // tujuan sendiri, jadi kartunya tidak dimatikan.
    expect(box.isAvailable, isTrue);
    expect(box.connectorLabel, '2 Konektor');
  });
}
