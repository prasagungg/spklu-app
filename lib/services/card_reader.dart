import 'package:flutter/foundation.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';

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
  const TappedCard({required this.uid, this.technologies = const []});

  /// Nomor seri kartu dalam heksadesimal, mis. "04A2B3C4".
  final String uid;

  /// Teknologi yang didukung kartu, mis. `["MifareClassic", "NfcA"]`.
  final List<String> technologies;

  @override
  String toString() => 'TappedCard($uid [${technologies.join(', ')}])';
}

/// Pembaca kartu uang elektronik.
///
/// ## Batas yang harus diketahui
///
/// Pembaca ini hanya **mendeteksi** kartu dan membaca nomor serinya.
/// Saldo kartu uang elektronik Indonesia — Flazz, BRIZZI, e-Money,
/// TapCash — tersimpan di sektor yang terkunci kunci milik penerbit dan
/// hanya bisa dibaca atau didebit lewat SAM (Secure Access Module)
/// bersertifikat. Aplikasi Android biasa tidak bisa melakukannya, dan
/// tidak ada pustaka yang mengubah kenyataan itu.
///
/// Jadi tap di halaman pembayaran berfungsi sebagai *pemicu* bahwa
/// kartu sudah ditempelkan, bukan sebagai transaksi. Pemotongan saldo
/// sungguhan harus lewat reader atau backend pembayaran bersertifikat;
/// begitu itu tersedia, panggilannya masuk di [CardPaymentPage] setelah
/// kartu terbaca dan sebelum berpindah halaman.
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
        onDiscovered: (tag) => onTap(_toCard(tag)),
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

  static TappedCard _toCard(NfcTag tag) {
    final android = NfcTagAndroid.from(tag);
    if (android == null) return const TappedCard(uid: '-');

    return TappedCard(uid: _hex(android.id), technologies: android.techList);
  }

  static String _hex(Uint8List bytes) => [
        for (final byte in bytes)
          byte.toRadixString(16).padLeft(2, '0').toUpperCase(),
      ].join();
}
