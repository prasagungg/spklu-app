/// Membaca nomor kartu uang elektronik dari kartu yang ditempelkan.
///
/// ## Apa yang bisa dan tidak bisa dibaca
///
/// Nomor seri kartu (UID) selalu terbaca, tetapi itu **nomor chip**,
/// bukan nomor uang elektroniknya. Nomor 16 digit yang diminta backend
/// tersimpan di dalam data kartu, dan cara membacanya berbeda-beda:
///
/// - Kartu berbasis **ISO-DEP/EMV** — Flazz keluaran baru dan sebagian
///   kartu lain — menjawab perintah APDU standar, dan nomornya ada di
///   tag EMV `5A` (Application PAN) atau `57` (Track 2). Itulah yang
///   dibaca berkas ini.
/// - Kartu berbasis **MIFARE Classic** — e-Money Mandiri, TapCash,
///   Brizzi — menyimpannya di sektor yang terkunci kunci milik
///   penerbit. Tanpa kunci itu atau SAM bersertifikat, nomornya tidak
///   bisa dibaca aplikasi Android biasa.
///
/// Semua perintah di sini **hanya membaca**: SELECT dan READ RECORD.
/// Tidak ada yang menulis ke kartu atau menyentuh saldo.
///
/// Kartu yang tidak menjawab menghasilkan string kosong, dan pemanggil
/// jatuh ke [Env.cardNumber].
library;

import 'dart:typed_data';

/// Nama direktori kontaktless EMV: "2PAY.SYS.DDF01".
///
/// Kartu yang mendukungnya menyebutkan sendiri AID aplikasinya, jadi
/// daftar AID tidak perlu ditebak.
final Uint8List ppseName = Uint8List.fromList('2PAY.SYS.DDF01'.codeUnits);

/// `00 A4 04 00 Lc <nama> 00` — SELECT berdasarkan nama aplikasi.
Uint8List selectApdu(Uint8List name) => Uint8List.fromList([
  0x00, 0xA4, 0x04, 0x00, name.length, ...name, 0x00, //
]);

/// `00 B2 <record> <(sfi<<3)|4> 00` — READ RECORD.
Uint8List readRecordApdu(int sfi, int record) => Uint8List.fromList([
  0x00, 0xB2, record, (sfi << 3) | 4, 0x00, //
]);

/// Kartu menjawab dengan SW1 SW2 di dua byte terakhir; "9000" sukses.
bool isSuccess(Uint8List response) =>
    response.length >= 2 &&
    response[response.length - 2] == 0x90 &&
    response[response.length - 1] == 0x00;

/// Isi data jawaban, tanpa dua byte status di ujungnya.
Uint8List payloadOf(Uint8List response) => response.length <= 2
    ? Uint8List(0)
    : response.sublist(0, response.length - 2);

/// Mencari nilai [tag] di dalam struktur BER-TLV, termasuk di dalam
/// tag bersusun (constructed).
///
/// Mengembalikan null bila tidak ada. Data yang cacat — panjang yang
/// melebihi sisa buffer — dihentikan, bukan dilempar: yang dibaca di
/// sini datang dari kartu orang lain, dan satu kartu aneh tidak boleh
/// menjatuhkan halaman pembayaran.
Uint8List? findTag(Uint8List data, int tag) {
  var i = 0;

  while (i < data.length) {
    // Tag bisa satu atau dua byte; lima bit pertama bernilai 1 berarti
    // ada byte lanjutan.
    var current = data[i];
    i++;
    if (current & 0x1F == 0x1F) {
      if (i >= data.length) return null;
      current = (current << 8) | data[i];
      i++;
    }

    if (i >= data.length) return null;

    // Panjang: satu byte, atau 0x8N diikuti N byte panjang.
    var length = data[i];
    i++;
    if (length & 0x80 != 0) {
      final count = length & 0x7F;
      if (count == 0 || count > 4 || i + count > data.length) return null;
      length = 0;
      for (var n = 0; n < count; n++) {
        length = (length << 8) | data[i];
        i++;
      }
    }

    if (i + length > data.length) return null;
    final value = Uint8List.sublistView(data, i, i + length);

    if (current == tag) return Uint8List.fromList(value);

    // Tag bersusun: bit ke-6 pada byte pertamanya menyala.
    final first = current > 0xFF ? current >> 8 : current;
    if (first & 0x20 != 0) {
      final found = findTag(value, tag);
      if (found != null) return found;
    }

    i += length;
  }

  return null;
}

/// Semua AID (`4F`) yang disebutkan jawaban PPSE.
List<Uint8List> aidsFrom(Uint8List payload) {
  final aids = <Uint8List>[];

  // Tiap aplikasi dibungkus template `61`; dicari satu per satu
  // dengan memotong bagian yang sudah dibaca.
  var rest = payload;
  while (true) {
    final template = findTag(rest, 0x61);
    if (template == null) break;

    final aid = findTag(template, 0x4F);
    if (aid != null && aid.isNotEmpty) aids.add(aid);

    final at = _indexOf(rest, template);
    if (at < 0) break;
    rest = Uint8List.sublistView(rest, at + template.length);
    if (rest.isEmpty) break;
  }

  return aids;
}

int _indexOf(Uint8List haystack, Uint8List needle) {
  if (needle.isEmpty || needle.length > haystack.length) return -1;

  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return i;
  }
  return -1;
}

/// Nomor kartu dari satu jawaban kartu, bila ada.
///
/// Dicari di tag `5A` (Application PAN) lebih dulu, lalu `57` (Track 2)
/// yang memuat nomor sebelum pemisah "D".
String? panFrom(Uint8List payload) {
  final pan = findTag(payload, 0x5A);
  if (pan != null) {
    final digits = _digitsOf(pan);
    if (digits.length >= 12) return digits;
  }

  final track2 = findTag(payload, 0x57);
  if (track2 != null) {
    final digits = _digitsOf(track2);
    if (digits.length >= 12) return digits;
  }

  return null;
}

/// BCD menjadi angka, berhenti pada nibble pertama yang bukan angka —
/// "D" memisahkan nomor dari sisa data Track 2, "F" mengisi ujung
/// nomor yang lebih pendek dari tempatnya.
String _digitsOf(Uint8List bytes) {
  final buffer = StringBuffer();

  for (final byte in bytes) {
    for (final nibble in [byte >> 4, byte & 0x0F]) {
      // "F" pengisi di ujung nomor, "D" pemisah Track 2 — keduanya
      // menandai nomornya sudah habis.
      if (nibble > 9) return buffer.toString();
      buffer.write(nibble);
    }
  }

  return buffer.toString();
}

/// Mengirim satu APDU ke kartu dan mengembalikan jawabannya.
typedef Transceive = Future<Uint8List> Function(Uint8List apdu);

/// Membaca nomor kartu lewat perintah EMV standar.
///
/// Urutannya: SELECT PPSE untuk menanyakan aplikasi apa saja yang ada
/// di kartu, SELECT tiap aplikasi, lalu baca beberapa record pertamanya
/// sampai ketemu tag nomor kartu.
///
/// Mengembalikan string kosong bila kartunya tidak menjawab, tidak
/// punya aplikasi EMV, atau menyimpan nomornya di tempat yang terkunci.
Future<String> readCardNumber(
  Transceive transceive, {

  /// Berapa banyak record yang dicoba per aplikasi. Nomor kartu
  /// hampir selalu ada di record pertama SFI 1 atau 2; batas ini
  /// menjaga tap tetap terasa seketika.
  int maxSfi = 3,
  int maxRecord = 4,
}) async {
  Future<Uint8List?> ask(Uint8List apdu) async {
    try {
      final answer = await transceive(apdu);
      return isSuccess(answer) ? payloadOf(answer) : null;
    } on Object {
      // Kartu dilepas di tengah jalan, atau perintahnya tidak
      // dikenali. Keduanya berarti nomornya tidak terbaca.
      return null;
    }
  }

  final directory = await ask(selectApdu(ppseName));
  if (directory == null) return '';

  for (final aid in aidsFrom(directory)) {
    final selected = await ask(selectApdu(aid));
    if (selected == null) continue;

    // Sebagian kartu sudah menyebut nomornya di jawaban SELECT.
    final fromSelect = panFrom(selected);
    if (fromSelect != null) return fromSelect;

    for (var sfi = 1; sfi <= maxSfi; sfi++) {
      for (var record = 1; record <= maxRecord; record++) {
        final data = await ask(readRecordApdu(sfi, record));
        if (data == null) continue;

        final pan = panFrom(data);
        if (pan != null) return pan;
      }
    }
  }

  return '';
}
