import 'package:flutter/foundation.dart';
import 'package:kossotrik/services/card_reader.dart';

/// [CardReader] palsu untuk test.
///
/// Tidak menyentuh NFC sama sekali; tap kartunya dipicu manual lewat
/// [tap], menggantikan tombol "Bayar (Simulasi)" yang dulu dipakai test
/// untuk memajukan alur pembayaran.
class FakeCardReader implements CardReader {
  FakeCardReader({this.reportedStatus = CardReaderStatus.ready});

  /// Kesiapan yang dilaporkan — ubah untuk menguji perangkat tanpa NFC
  /// atau NFC yang sedang dimatikan.
  final CardReaderStatus reportedStatus;

  ValueChanged<TappedCard>? _onTap;

  /// Berapa kali [stop] dipanggil, untuk memastikan sesi NFC ditutup.
  int stopCount = 0;

  /// Apakah pembaca sedang menunggu kartu.
  bool get isWaiting => _onTap != null;

  @override
  Future<CardReaderStatus> status() async => reportedStatus;

  @override
  Future<void> start(ValueChanged<TappedCard> onTap) async => _onTap = onTap;

  @override
  Future<void> stop() async {
    stopCount++;
    _onTap = null;
  }

  /// Meniru kartu ditempelkan ke pembaca.
  ///
  /// [cardNumber] kosong meniru kartu yang tidak mengungkapkan nomor
  /// uang elektroniknya — MIFARE Classic seperti e-Money dan TapCash —
  /// sehingga pembayaran jatuh ke nomor dari konfigurasi.
  void tap({String uid = '04A2B3C4', String cardNumber = ''}) => _onTap?.call(
        TappedCard(
          uid: uid,
          technologies: const ['MifareClassic', 'NfcA'],
          cardNumber: cardNumber,
        ),
      );
}
