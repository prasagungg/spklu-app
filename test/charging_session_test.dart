import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/demo_data.dart';
import 'package:kossotrik/models/charging_session.dart';
import 'package:kossotrik/models/session_check.dart';
import 'package:kossotrik/models/billing.dart';
import 'package:kossotrik/models/order.dart';

ChargingSession _session() {
  final box = DemoData.chargeBoxes[3];
  return ChargingSession.fromOrder(
    chargeBox: box,
    connector: box.connectors.first,
    // Rp50.000 untuk 19,5 kWh — angka bulat supaya pembulatan
    // tagihan ke bawah mudah dibaca.
    order: const Order(
      orderId: 'ORDER-1',
      sessionCode: '29',
      partnerReference: '81067',
      kwh: 19.5,
      rpTotal: 50000,
    ),
    now: DateTime(2026, 9, 16, 18, 40, 39),
  );
}

void main() {
  _sessionCheckExpiryTests();

  /// Tagihan bisa berbeda dari total order — inquiry menambahkan fee,
  /// idleFee, dan serviceFee — jadi rincian akhir memakai angka yang
  /// benar-benar didebit.
  group('angka yang dipakai adalah yang dibayar', () {
    test('tanpa bukti pembayaran, jatuh ke total order', () {
      expect(_session().paidAmount, 50000);
    });

    test('bukti pembayaran mengalahkan total order', () {
      final paid = _session().paidWith(
        const BillingInquiry(
          orderId: 'ORDER-1',
          totalAmount: 56000,
          bankLog: '123',
        ),
      );

      expect(paid.paidAmount, 56000);
      expect(paid.billing!.isPaid, isTrue);
    });

    test('dana kembali dihitung dari yang dibayar', () {
      final paid = _session().paidWith(
        const BillingInquiry(orderId: 'ORDER-1', totalAmount: 56000),
      );

      // 0 kWh terpakai: seluruh yang didebit kembali.
      expect(paid.refundFor(0), 56000);
    });
  });

  test('biaya pemakaian dihitung proporsional dan dibulatkan ke bawah', () {
    final session = _session();

    // 6,4 dari 19,5 kWh -> 16.410 -> dibulatkan ke bawah jadi 16.000,
    // sesuai angka pada desain Figma.
    expect(session.usageCostFor(6.4), 16000);
    expect(session.refundFor(6.4), 34000);
  });

  test('belum ada energi tersalur berarti dana kembali penuh', () {
    final session = _session();

    expect(session.usageCostFor(0), 0);
    expect(session.refundFor(0), 50000);
  });

  test('pemakaian tidak pernah melebihi nominal yang dibayar', () {
    final session = _session();

    expect(session.usageCostFor(999), 50000);
    expect(session.refundFor(999), 0);
  });

  test('breadcrumb menggabungkan badge, nama box, dan konektor', () {
    expect(_session().breadcrumb, '04 • CS DC Charger • Gun 1');
  });

  test('tanggal transaksi diformat untuk ditampilkan', () {
    expect(_session().formattedDate, '2026-09-16 18:40:39');
  });

  group('batas waktu sesi', () {
    test('sisa waktu dihitung dari tenggat dan tidak pernah negatif', () {
      final now = DateTime(2026, 9, 16, 18, 40, 39);
      final session = ChargingSession(
        chargeBox: DemoData.chargeBoxes[3],
        connector: DemoData.chargeBoxes[3].connectors.first,
        sessionCode: '29',
        reference: '81067',
        createdAt: now,
        expiresAt: now.add(const Duration(minutes: 9, seconds: 33)),
      );

      expect(session.remainingAt(now), const Duration(minutes: 9, seconds: 33));
      // Lewat tenggat berhenti di nol, bukan menghitung mundur ke minus.
      expect(
        session.remainingAt(now.add(const Duration(minutes: 20))),
        Duration.zero,
      );
    });

    test('sesi tanpa tenggat tidak punya sisa waktu', () {
      expect(_session().remainingAt(DateTime(2026)), isNull);
    });

    test('pembayaran memperbarui tenggat dengan sessionExpired tagihan', () {
      final paid = _session().paidWith(
        BillingInquiry.fromJson(const {
          'orderId': 'ORDER-1',
          'totalAmount': 25400,
          'bankLog': 'BANKLOG-0001',
          'sessionExpired': '2026-09-23T09:56:04Z',
        }),
      );

      expect(paid.expiresAt, DateTime.utc(2026, 9, 23, 9, 56, 4));
    });

    test('tagihan tanpa sessionExpired membiarkan tenggat order', () {
      final before = _session().expiresAt;

      final paid = _session().paidWith(
        BillingInquiry.fromJson(const {
          'orderId': 'ORDER-1',
          'totalAmount': 25400,
          'bankLog': 'BANKLOG-0001',
        }),
      );

      expect(paid.expiresAt, before);
    });
  });
}

void _sessionCheckExpiryTests() {
  group('tenggat dari manage-sessioncode', () {
    test('sessionExpiredTime diurai', () {
      final check = SessionCheck.fromJson(const {
        'orderId': 'ORDER-1',
        'sessionCode': '70',
        'statusProcess': 2,
        'sessionExpiredTime': '2026-09-25T12:33:51Z',
      });

      expect(check.sessionExpiredAt, DateTime.utc(2026, 9, 25, 12, 33, 51));
    });

    /// `payment-billing` memakai ejaan tanpa "Time"; keduanya diterima.
    test('ejaan sessionExpired ikut diterima', () {
      final check = SessionCheck.fromJson(const {
        'sessionExpired': '2026-09-25T12:33:51Z',
      });

      expect(check.sessionExpiredAt, DateTime.utc(2026, 9, 25, 12, 33, 51));
    });

    test('tanpa tenggat tetap null, bukan melempar', () {
      expect(SessionCheck.fromJson(const {}).sessionExpiredAt, isNull);
    });
  });
}
