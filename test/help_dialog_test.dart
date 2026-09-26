import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/data/charge_point_repository.dart';
import 'package:kossotrik/data/charging_scope.dart';
import 'package:kossotrik/models/help_contact.dart';
import 'package:kossotrik/services/api_client.dart';
import 'package:kossotrik/theme/app_theme.dart';
import 'package:kossotrik/widgets/help_dialog.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'fixtures.dart';

/// Menjawab `/evtap/bantuan`; bisa dibuat kosong atau gagal.
class _Stub extends Interceptor {
  _Stub({this.empty = false, this.fail = false});

  final bool empty;
  final bool fail;
  final List<RequestOptions> requests = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    requests.add(options);

    if (fail) {
      handler.reject(
        DioException.connectionError(requestOptions: options, reason: 'mati'),
      );
      return;
    }

    handler.resolve(
      Response<Map<String, dynamic>>(
        requestOptions: options,
        statusCode: 200,
        data: empty
            ? bantuanResponse(email: '', hotline: '', whatsapp: '')
            : bantuanResponse(),
      ),
    );
  }
}

Future<_Stub> _openHelp(
  WidgetTester tester, {
  bool empty = false,
  bool fail = false,
}) async {
  // Layar kios tinggi; ukuran bawaan test memotong modalnya.
  await tester.binding.setSurfaceSize(const Size(800, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final stub = _Stub(empty: empty, fail: fail);
  final repo = ChargePointRepository(
    client: ApiClient.withDio(Dio()..interceptors.add(stub)),
  );

  await tester.pumpWidget(
    ChargingScope(
      repository: repo,
      child: MaterialApp(
        theme: AppTheme.build(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showHelpDialog(context),
                child: const Text('Bantuan'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Bantuan'));
  await tester.pumpAndSettle();

  return stub;
}

void main() {
  testWidgets('kontak diambil dari /evtap/bantuan', (tester) async {
    final stub = await _openHelp(tester);

    expect(stub.requests.single.path, '/evtap/bantuan');
    expect(stub.requests.single.method, 'GET');

    expect(find.text('Butuh Bantuan?'), findsOneWidget);
    expect(find.text('bantuan@pln.co.id'), findsOneWidget);
    expect(find.text('123'), findsOneWidget);
    expect(find.text('+62 851 2345 6789'), findsOneWidget);
  });

  testWidgets('QR chat WhatsApp ikut ditampilkan', (tester) async {
    await _openHelp(tester);

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.textContaining('Scan QR'), findsOneWidget);
  });

  /// Nomor yang dipindai harus tautan wa.me berisi angkanya saja —
  /// spasi dan tanda plus membuat tautannya tidak terbuka. Isi QR-nya
  /// tidak bisa dibaca dari widgetnya, jadi tautannya diuji di sini.
  group('tautan WhatsApp', () {
    test('dibersihkan dari spasi dan plus', () {
      const contact = HelpContact(whatsapp: '+62 851 2345 6789');

      expect(contact.whatsappLink, 'https://wa.me/6285123456789');
    });

    test('kosong bila nomornya tidak ada', () {
      expect(const HelpContact().whatsappLink, '');
    });
  });

  testWidgets('tombol salin menaruh nilainya di papan tempel', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );

    await _openHelp(tester);
    await tester.tap(find.byTooltip('Salin Email'));
    await tester.pumpAndSettle();

    expect(copied, 'bantuan@pln.co.id');
  });

  testWidgets('kontak kosong menjelaskan keadaannya', (tester) async {
    await _openHelp(tester, empty: true);

    expect(find.textContaining('kontak bantuan belum diatur'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('kegagalan tidak mengosongkan modal', (tester) async {
    await _openHelp(tester, fail: true);

    expect(find.text('Butuh Bantuan?'), findsOneWidget);
    expect(find.text('Kontak bantuan gagal diambil.'), findsOneWidget);
  });

  testWidgets('Tutup menutup modalnya', (tester) async {
    await _openHelp(tester);

    await tester.tap(find.text('Tutup'));
    await tester.pumpAndSettle();

    expect(find.text('Butuh Bantuan?'), findsNothing);
  });
}
