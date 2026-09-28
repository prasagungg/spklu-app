import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/data/charging_scope.dart';
import 'package:kossotrik/data/demo_data.dart';
import 'package:kossotrik/main.dart';
import 'package:kossotrik/models/billing.dart';
import 'package:kossotrik/models/charging_session.dart';
import 'package:kossotrik/models/order.dart';
import 'package:kossotrik/pages/charge_box_page.dart';
import 'package:kossotrik/pages/charging_finished_page.dart';
import 'package:kossotrik/services/api_client.dart';
import 'package:kossotrik/theme/app_theme.dart';

import 'fake_card_reader.dart';
import 'fixtures.dart';
import 'flow_helpers.dart';

class _Stub extends Interceptor {
  _Stub(this.progress, {this.detail});

  final Map<String, dynamic> Function() progress;

  /// Jawaban `charging/detail`. Null berarti amplop kosong — yang
  /// dipakai test untuk memastikan angka pemantauan tidak tertimpa.
  final Map<String, dynamic> Function()? detail;

  /// Setelah perintah start, konektornya melapor sedang mengisi.
  bool _charging = false;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path == '/transaction/charging/start') _charging = true;
    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        data: switch (options.path) {
          '/list-chargerbox' => listResponse([
            chargeBoxJson(id: 'CB-SMR-01', nama: 'CB-SMR-01'),
          ]),
          '/booked-connector' => bookingResponse(),
          '/manage-sessioncode' => sessionCodeResponse(),
          // Kabelnya dianggap sudah terpasang; penungguannya
          // diuji tersendiri di connector_detection_poll_test.
          '/check-status-connector' => connectorStatusResponse(),
          '/detail-chargerbox' => chargeBoxDetailResponse(
            connectors: [connectorJson(status: _charging ? 2 : 1)],
          ),
          '/list-kwh' => kwhOptionsResponse(),
          '/count-kwh' => countKwhResponse(),
          '/transaction/push-order' => pushOrderResponse(),
          '/transaction/inquiry-billing' => inquiryBillingResponse(),
          '/transaction/payment-billing' => paymentBillingResponse(),
          '/transaction/charging/ongoing-kwh' => progress(),
          '/transaction/charging/detail' => detail?.call() ?? okResponse,
          // Layar penutup menanyakan ini juga: nomor dan penerbit
          // kartunya tidak ada di `charging/detail`.
          '/transaction/detail-history-transaction' =>
            transactionDetailResponse(orderId: 'YZ00ZG5SP9HUNVRPTZH69Y7POW'),
          _ => okResponse,
        },
        statusCode: 200,
      ),
    );
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

/// Membeli satu sesi sampai layar pemantauan terbuka.
Future<void> _runUntilCharging(WidgetTester tester, _Stub stub) async {
  final repo = ChargePointRepository(
    client: ApiClient.withDio(Dio()..interceptors.add(stub)),
  );
  final reader = FakeCardReader();

  await tester.pumpWidget(SPKLUApp(repository: repo, cardReader: reader));
  await tester.pumpAndSettle();

  await tester.tap(find.text('01'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Gun 1'));
  await passSessionCode(tester);
  // Tidak ada pilihan yang tercentang sejak awal.
  await tester.tap(find.text('10'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Lanjutkan'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Konfirmasi & Bayar'));
  await _settle(tester);

  reader.tap();
  await _settle(tester);
  // Inquiry tagihan menambah satu hop async sebelum halaman pindah.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pump(const Duration(milliseconds: 600));
  await tester.tap(find.text('Mulai Pengisian'));
  await _settle(tester);

  // Kabelnya sudah terpasang sejak halaman dibuka, jadi perintah start
  // berangkat sendiri setelah jeda acaknya habis.
  await pumpUntil(tester, find.text('Pengisian Dimulai'));

  await reopenChargingSession(tester);
  expect(find.text('Sedang Mengisi'), findsOneWidget);

  await endCharging(tester);
}

/// Sesi yang kartunya benar-benar ditempelkan di unit ini.
ChargingSession _paidSession() {
  final box = DemoData.chargeBoxes[3];

  return ChargingSession.fromOrder(
    chargeBox: box,
    connector: box.connectors.first,
    order: const Order(
      orderId: 'ORDER-1',
      sessionCode: '29',
      partnerReference: '81067',
      kwh: 10,
      rpTotal: 25400,
    ),
    now: DateTime(2026, 9, 16),
  ).paidWith(
    const BillingInquiry(
      orderId: 'ORDER-1',
      totalAmount: 25400,
      cardNumber: '0123456789012345',
    ),
  );
}

/// Menjawab `charging/detail`, dan riwayat transaksinya hanya bila
/// diminta — yang tidak dijawab dibiarkan menggantung, meniru endpoint
/// yang lebih lambat.
class _HalfStub extends Interceptor {
  _HalfStub(this.answerTransaction);

  final bool answerTransaction;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.path == '/transaction/detail-history-transaction' &&
        !answerTransaction) {
      return;
    }

    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: switch (options.path) {
          '/transaction/charging/detail' => chargingDetailResponse(
            orderId: 'ORDER-1',
          ),
          '/transaction/detail-history-transaction' =>
            transactionDetailResponse(orderId: 'ORDER-1'),
          _ => okResponse,
        },
      ),
    );
  }
}

void main() {
  /// Angka penutup milik pembukuan backend: berapa yang benar-benar
  /// terpakai dan berapa yang dikembalikan tidak pernah bisa dijamin
  /// sama kalau aplikasi menghitungnya sendiri.
  testWidgets('rincian akhir diambil dari charging/detail', (tester) async {
    var status = 3;
    var charged = 0.0;

    final stub = _Stub(
      () => ongoingKwhResponse(
        orderId: 'YZ00ZG5SP9HUNVRPTZH69Y7POW',
        status: status,
        charged: charged,
      ),
      detail: () => chargingDetailResponse(
        kwhPakai: 6.4,
        rpPesan: 25400,
        rpPakai: 16256,
        rpSisa: 9144,
      ),
    );
    await _runUntilCharging(tester, stub);

    status = 4;
    charged = 0.017;
    for (var attempt = 0; attempt < 6; attempt++) {
      await tester.pump(const Duration(seconds: 1));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Pengisian Selesai'), findsOneWidget);
    // Angka dari backend menggantikan hasil pemantauan dan hitungan
    // lokal: 10 kWh dipesan, 6,4 kWh terpakai, 3,6 kWh tersisa,
    // Rp16.256 dipakai, Rp9.144 kembali.
    // Pegangan pengguna bila ada yang perlu ditanyakan ke petugas.
    expect(find.text('No Order'), findsOneWidget);
    expect(find.text('YZ00ZG5SP9HUNVRPTZH69Y7POW'), findsOneWidget);
    // Sesi di test ini dibuka ulang lewat kode sesi, jadi kartunya tidak
    // pernah ditempelkan di instance aplikasi ini. Riwayat transaksi
    // yang mengisinya — dan hanya riwayat yang tahu penerbitnya.
    expect(find.text('Nomor Kartu'), findsOneWidget);
    expect(find.text('601••••••••••890'), findsOneWidget);
    expect(find.text('Penerbit Kartu'), findsOneWidget);
    expect(find.text('EM-BNI'), findsOneWidget);

    expect(find.text('10 kWh'), findsOneWidget);
    expect(find.text('6,4 kWh'), findsOneWidget);
    expect(find.text('3,6 kWh'), findsOneWidget);
    expect(find.text('Rp25.400'), findsOneWidget);
    expect(find.text('Rp16.256'), findsOneWidget);
    expect(find.text('Rp9.144'), findsOneWidget);
  });

  /// Rincian yang muncul satu per satu begitu jawabannya berdatangan
  /// terbaca seperti aplikasi yang tersendat. Penerbit kartu paling
  /// terasa: ia datang dari permintaan yang kedua.
  group('rinciannya ditahan sampai kedua permintaan selesai', () {
    /// Menjawab `charging/detail`, tapi menggantung riwayat transaksi.
    Future<void> pumpFinished(
      WidgetTester tester, {
      required bool answerTransaction,
    }) async {
      final repo = ChargePointRepository(
        client: ApiClient.withDio(
          Dio()..interceptors.add(_HalfStub(answerTransaction)),
        ),
      );

      await tester.pumpWidget(
        ChargingScope(
          repository: repo,
          child: MaterialApp(
            theme: AppTheme.build(),
            home: ChargingFinishedPage(session: _paidSession(), energyKwh: 6.4),
          ),
        ),
      );
      await _settle(tester);
      await _settle(tester);
    }

    testWidgets('yang satu menjawab, yang lain belum: tetap menunggu', (
      tester,
    ) async {
      await pumpFinished(tester, answerTransaction: false);

      expect(find.text('Menyiapkan rincian…'), findsOneWidget);
      // Tidak ada satu baris pun yang bocor lebih dulu.
      expect(find.text('No Order'), findsNothing);
      expect(find.text('Energi Tersalur'), findsNothing);
      expect(find.text('Penerbit Kartu'), findsNothing);
      // Jaringan lambat tidak boleh mengurung siapa pun.
      expect(find.text('Kembali ke Halaman Awal'), findsOneWidget);
    });

    testWidgets('keduanya menjawab: semuanya muncul sekaligus', (tester) async {
      await pumpFinished(tester, answerTransaction: true);

      expect(find.text('Menyiapkan rincian…'), findsNothing);
      expect(find.text('No Order'), findsOneWidget);
      expect(find.text('Penerbit Kartu'), findsOneWidget);
      expect(find.text('Energi Tersalur'), findsOneWidget);
    });
  });

  /// Tanpa [ChargingScope] tidak ada `charging/detail` untuk ditanya,
  /// jadi angkanya jatuh ke pembelian yang dipegang sesi ini — jalur
  /// yang juga dilewati bila panggilannya gagal.
  testWidgets('nomor order dan kartu dari sesi yang dibayar di unit ini', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(),
        home: ChargingFinishedPage(session: _paidSession(), energyKwh: 6.4),
      ),
    );
    await tester.pump();

    expect(find.text('No Order'), findsOneWidget);
    expect(find.text('ORDER-1'), findsOneWidget);
    // Tanpa riwayat, cadangannya tagihan yang dipegang sesi ini —
    // disamarkan aplikasi. Penerbitnya hanya diketahui riwayat, jadi
    // barisnya tidak muncul di sini.
    expect(find.text('Nomor Kartu'), findsOneWidget);
    expect(find.text('•••• 2345'), findsOneWidget);
    expect(find.text('Penerbit Kartu'), findsNothing);

    // Sisanya dihitung di sini, dan 10 - 6,4 dalam floating point
    // menghasilkan 3,5999999999999996 kalau tidak dirapikan.
    expect(find.text('10 kWh'), findsOneWidget);
    expect(find.text('6,4 kWh'), findsOneWidget);
    expect(find.text('3,6 kWh'), findsOneWidget);
  });

  /// `sisaKwh` diambil apa adanya, tidak dihitung ulang dari selisih.
  /// Backend memotong idle fee dan biaya layanan dari sisa itu, jadi
  /// selisih yang dihitung aplikasi tidak selalu sama angkanya.
  testWidgets('sisa kWh dibaca dari backend, bukan dihitung', (tester) async {
    var status = 3;
    var charged = 0.0;

    final stub = _Stub(
      () => ongoingKwhResponse(
        orderId: 'YZ00ZG5SP9HUNVRPTZH69Y7POW',
        status: status,
        charged: charged,
      ),
      // 10 dipesan, 6,4 terpakai — selisihnya 3,6, tapi backend
      // menyebut 2,5. Yang tampil harus angka backend.
      detail: () => {
        ...chargingDetailResponse(),
        'data': {
          ...chargingDetailResponse()['data']! as Map<String, dynamic>,
          'sisaKwh': 2.5,
        },
      },
    );
    await _runUntilCharging(tester, stub);

    status = 4;
    charged = 0.017;
    for (var attempt = 0; attempt < 6; attempt++) {
      await tester.pump(const Duration(seconds: 1));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('2,5 kWh'), findsOneWidget);
    expect(find.text('3,6 kWh'), findsNothing);
  });

  testWidgets('kWh akhir diambil dari /progress terakhir, bukan saat ditekan', (
    tester,
  ) async {
    // Saat tombol ditekan energinya 0,003 kWh; charger masih
    // menyalurkan daya sampai akhirnya berhenti di 0,017 kWh.
    var status = 3;
    var charged = 0.003;

    final repo = ChargePointRepository(
      client: ApiClient.withDio(
        Dio()
          ..interceptors.add(
            _Stub(() => ongoingKwhResponse(status: status, charged: charged)),
          ),
      ),
    );
    final reader = FakeCardReader();

    await tester.pumpWidget(SPKLUApp(repository: repo, cardReader: reader));
    await tester.pumpAndSettle();

    // Alur pembelian sampai layar pemantauan.
    await tester.tap(find.text('01'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gun 1'));
    await passSessionCode(tester);
    // Tidak ada pilihan yang tercentang sejak awal.
    await tester.tap(find.text('10'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lanjutkan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Konfirmasi & Bayar'));
    await _settle(tester);

    reader.tap();
    await _settle(tester);
    // Inquiry tagihan menambah satu hop async sebelum halaman pindah.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 600));
    await tester.tap(find.text('Mulai Pengisian'));
    await _settle(tester);

    // Kabelnya sudah terpasang sejak halaman dibuka, jadi perintah
    // start berangkat sendiri setelah jeda acaknya habis.
    await pumpUntil(tester, find.text('Pengisian Dimulai'));

    // Kode sesi dari push-order ditunjukkan dulu; pemantauan dibuka
    // dengan kode itu dari daftar charge box.
    await reopenChargingSession(tester);
    expect(find.text('Sedang Mengisi'), findsOneWidget);

    // Polling pertama membawa 0,003 kWh.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('0,003 kWh'), findsOneWidget);

    await endCharging(tester);

    // Charger berhenti dan melaporkan angka akhir yang lebih besar.
    status = 4;
    charged = 0.017;

    for (var attempt = 0; attempt < 6; attempt++) {
      await tester.pump(const Duration(seconds: 1));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('Pengisian Selesai'), findsOneWidget);
    // 17 Wh, bukan 3 Wh yang terbaca saat tombol ditekan. Stub ini
    // tidak menjawab `charging/detail`, jadi yang tampil memang angka
    // pemantauan terakhir — rincian dari backend diuji tersendiri.
    expect(find.text('0,017 kWh'), findsOneWidget);
    expect(find.text('0,003 kWh'), findsNothing);

    await tester.tap(find.text('Kembali ke Halaman Awal'));
    await tester.pumpAndSettle();
    expect(find.byType(ChargeBoxPage), findsOneWidget);
  });
}
