import 'package:flutter/foundation.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';

import 'card_number_reader.dart';

/// Kesiapan pembaca kartu pada perangkat ini.
enum CardReaderStatus {
  /// Siap menunggu kartu ditempelkan.
  ready,

  /// Perangkat punya NFC tetapi sedang dimatikan pengguna.
  disabled,

  /// Perangkat tidak punya pembaca NFC sama sekali.
  unsupported,
}

/// Kartu yang baru ditempelkan.
@immutable
class TappedCard {
  const TappedCard({
    required this.uid,
    this.technologies = const [],
    this.cardNumber = '',
  });

  /// Nomor seri kartu dalam heksadesimal, mis. "04A2B3C4".
  ///
  /// Ini **nomor chip**, bukan nomor uang elektroniknya — keduanya
  /// berbeda, dan backend meminta yang kedua.
  final String uid;

  /// Teknologi yang didukung kartu, mis. `["MifareClassic", "NfcA"]`.
  final List<String> technologies;

  /// Nomor uang elektronik yang berhasil dibaca dari kartu, atau
  /// kosong bila kartunya tidak mengungkapkannya — lihat
  /// `card_number_reader.dart`.
  final String cardNumber;

  @override
  String toString() => 'TappedCard($uid [${technologies.join(', ')}]'
      '${cardNumber.isEmpty ? '' : ', nomor $cardNumber'})';
}

/// Pembaca kartu uang elektronik.
///
/// ## Batas yang harus diketahui
///
/// Pembaca ini **mendeteksi** kartu, membaca nomor serinya, dan — untuk
/// kartu yang menjawab perintah EMV — mencoba membaca nomor uang
/// elektroniknya (`card_number_reader.dart`). Kartu berbasis MIFARE
/// Classic seperti e-Money, TapCash, dan Brizzi menyimpan nomor serta
/// saldonya di sektor yang terkunci kunci milik penerbit, dan hanya
/// bisa dibaca atau didebit lewat SAM (Secure Access Module)
/// bersertifikat.
///
/// **Saldonya tidak dipotong di sini.** Tap di halaman pembayaran
/// adalah pemicu bahwa kartu sudah ditempelkan; pemotongan sungguhan
/// lewat mesin kartu bersertifikat, yang juga jadi sumber `bankLog`.
abstract class CardReader {
  /// Apakah perangkat ini siap membaca kartu.
  Future<CardReaderStatus> status();

  /// Mulai menunggu kartu.
  ///
  /// [onTap] dipanggil setiap kali ada kartu terdeteksi — Android bisa
  /// melaporkan kartu yang sama berulang selama masih menempel, jadi
  /// pemanggil yang menyaring dan memutuskan berhenti lewat [stop].
  Future<void> start(ValueChanged<TappedCard> onTap);

  /// Berhenti menunggu. Aman dipanggil walau sesi belum dimulai.
  Future<void> stop();
}

/// [CardReader] di atas NFC perangkat, lewat paket `nfc_manager`.
class NfcCardReader implements CardReader {
  NfcCardReader({NfcManager? manager}) : _manager = manager;

  /// Diambil malas: `NfcManager.instance` melempar di platform yang
  /// tidak didukung, dan itu tidak boleh terjadi saat objek dibuat.
  final NfcManager? _manager;

  bool _running = false;

  @override
  Future<CardReaderStatus> status() async {
    try {
      return switch (await (_manager ?? NfcManager.instance)
          .checkAvailability()) {
        NfcAvailability.enabled => CardReaderStatus.ready,
        NfcAvailability.disabled => CardReaderStatus.disabled,
        NfcAvailability.unsupported => CardReaderStatus.unsupported,
      };
    } on Object catch (e) {
      // Plugin tidak terpasang (mis. saat test) atau platformnya tidak
      // didukung. Diperlakukan sama seperti perangkat tanpa NFC.
      debugPrint('[NFC] Ketersediaan tidak bisa diperiksa: $e');
      return CardReaderStatus.unsupported;
    }
  }

  @override
  Future<void> start(ValueChanged<TappedCard> onTap) async {
    if (_running) return;
    _running = true;

    try {
      await (_manager ?? NfcManager.instance).startSession(
        // Kartu uang elektronik Indonesia memakai ISO 14443 (turunan
        // MIFARE); ISO 18092 disertakan untuk kartu berbasis FeliCa.
        pollingOptions: const {
          NfcPollingOption.iso14443,
          NfcPollingOption.iso18092,
        },
        onDiscovered: (tag) async => onTap(await _toCard(tag)),
      );
      debugPrint('[NFC] Menunggu kartu ditempelkan');
    } on Object catch (e) {
      _running = false;
      debugPrint('[NFC] Sesi gagal dimulai: $e');
    }
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _running = false;

    try {
      await (_manager ?? NfcManager.instance).stopSession();
    } on Object catch (e) {
      debugPrint('[NFC] Sesi gagal dihentikan: $e');
    }
  }

  static Future<TappedCard> _toCard(NfcTag tag) async {
    final android = NfcTagAndroid.from(tag);
    if (android == null) return const TappedCard(uid: '-');

    return TappedCard(
      uid: _hex(android.id),
      technologies: android.techList,
      cardNumber: await _cardNumber(tag),
    );
  }

  /// Nomor uang elektronik kartu, bila kartunya mengungkapkannya.
  ///
  /// Hanya kartu ISO-DEP yang ditanyai: perintah EMV tidak berlaku di
  /// MIFARE Classic, dan mencobanya hanya memperlambat tap.
  ///
  /// Kegagalan tidak pernah dilempar ke pemanggil — kartu yang tidak
  /// menjawab cukup berarti nomornya tidak terbaca, dan pembayaran
  /// jatuh ke nomor dari konfigurasi.
  static Future<String> _cardNumber(NfcTag tag) async {
    final isoDep = IsoDepAndroid.from(tag);
    if (isoDep == null) return '';

    try {
      final number = await readCardNumber(isoDep.transceive);
      debugPrint(
        number.isEmpty
            ? '[NFC] Kartu tidak mengungkapkan nomornya'
            : '[NFC] Nomor kartu terbaca: $number',
      );
      return number;
    } on Object catch (e) {
      debugPrint('[NFC] Nomor kartu gagal dibaca: $e');
      return '';
    }
  }

  static String _hex(Uint8List bytes) => [
        for (final byte in bytes)
          byte.toRadixString(16).padLeft(2, '0').toUpperCase(),
      ].join();
}
