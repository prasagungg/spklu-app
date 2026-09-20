import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/models/session_info.dart';

/// Payload nyata `GET /progress` saat sesi sedang berjalan.
///
/// Sejak daftar charge box pindah ke `POST /list-chargerbox`, bentuk
/// ini hanya datang dari `/progress` — daftar tidak lagi membawa sesi
/// yang sedang berjalan.
const _charging = {
  'chargePointId': 'CB-SMR-01',
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
};

/// Sesi yang sudah berhenti: `powerW` null dan muncul `stopReason`.
const _finished = {
  'chargePointId': 'CB-SMR-01',
  'connectorId': 2,
  'transactionId': 1789648926,
  'state': 'finished',
  'connectorStatus': 'Preparing',
  'percent': 55.5,
  'energyWh': 207,
  'powerW': null,
  'durationSeconds': 59,
  'stopReason': 'Remote',
  'stoppedAt': '2026-09-17T20:58:35.135618667+07:00',
};

void main() {
  test('sesi berjalan diurai lengkap dari payload nyata', () {
    final session = SessionInfo.fromJson(Map<String, dynamic>.from(_charging));

    expect(session.transactionId, 1789648926);
    expect(session.state, 'charging');
    expect(session.isCharging, isTrue);
    expect(session.isFinished, isFalse);
    expect(session.percent, 20.1);
    expect(session.powerKw, closeTo(12.33, 0.001));
    expect(session.duration, const Duration(seconds: 6));
    expect(session.updatedAt, isNotNull);
  });

  test('meter Wh dikonversi ke kWh untuk ditampilkan', () {
    final session = SessionInfo.fromJson(Map<String, dynamic>.from(_charging));

    expect(session.energyWh, 24);
    expect(session.energyKwh, closeTo(0.024, 0.0001));
  });

  test('energyKwh dari backend dipakai apa adanya bila ada', () {
    final session = SessionInfo.fromJson({
      ...Map<String, dynamic>.from(_charging),
      'energyKwh': 6.4,
    });

    expect(session.energyKwh, 6.4);
  });

  test('sesi selesai: powerW null tidak membuat parsing gagal', () {
    final session = SessionInfo.fromJson(Map<String, dynamic>.from(_finished));

    expect(session.powerW, 0);
    expect(session.state, 'finished');
    expect(session.isFinished, isTrue);
    expect(session.stopReason, 'Remote');
    expect(session.stoppedAt, isNotNull);
  });

  /// `stoppedAt` yang terisi sudah cukup, sekalipun `state` belum
  /// berubah — halaman status memakainya untuk berhenti menghitung.
  test('stoppedAt yang terisi sudah berarti selesai', () {
    final session = SessionInfo.fromJson({
      ...Map<String, dynamic>.from(_charging),
      'stoppedAt': '2026-09-17T20:58:35.135618667+07:00',
    });

    expect(session.isFinished, isTrue);
  });

  test('field yang hilang tidak membuat parsing gagal', () {
    final session = SessionInfo.fromJson(const {});

    expect(session.chargePointId, isEmpty);
    expect(session.energyWh, 0);
    expect(session.energyKwh, 0);
    expect(session.percent, 0);
    expect(session.isFinished, isFalse);
  });
}
