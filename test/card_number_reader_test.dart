import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kossotrik/services/card_number_reader.dart';

Uint8List _bytes(List<int> values) => Uint8List.fromList(values);

/// Jawaban kartu: isi ditambah status "9000".
Uint8List _ok(List<int> payload) => _bytes([...payload, 0x90, 0x00]);

/// Jawaban gagal: "6A82" — berkas tidak ditemukan.
final _notFound = _bytes([0x6A, 0x82]);

/// Satu simpul BER-TLV: tag, panjang, lalu isinya.
List<int> _tlv(List<int> tag, List<int> value) => [
  ...tag,
  value.length,
  ...value,
];

/// Kartu palsu yang menjawab APDU seperti kartu EMV sungguhan.
///
/// Meniru urutan yang sebenarnya: PPSE menyebut satu AID, SELECT AID
/// menjawab tanpa nomor, lalu nomornya muncul di record pertama.
class _FakeCard {
  _FakeCard({required this.recordPayload});

  final List<int> recordPayload;

  /// AID yang disebutkan kartu lewat PPSE.
  static const aid = [0xA0, 0x00, 0x01];

  final List<Uint8List> sent = [];

  Future<Uint8List> transceive(Uint8List apdu) async {
    sent.add(apdu);

    // SELECT
    if (apdu[1] == 0xA4) {
      final name = apdu.sublist(5, 5 + apdu[4]);
      if (String.fromCharCodes(name) == '2PAY.SYS.DDF01') {
        // FCI PPSE: 6F ( 84 <nama> A5 ( BF0C ( 61 ( 4F <aid> ) ) ) )
        final entry = _tlv([0x61], _tlv([0x4F], aid));
        final fci = _tlv(
          [0x6F],
          [
            ..._tlv([0x84], [0x31, 0x50]),
            ..._tlv([0xA5], _tlv([0xBF, 0x0C], entry)),
          ],
        );
        return _ok(fci);
      }
      // SELECT aplikasi: tidak menyebut nomor kartunya.
      return _ok([0x6F, 0x02, 0x84, 0x00]);
    }

    // READ RECORD: hanya SFI 1 record 1 yang berisi.
    if (apdu[1] == 0xB2) {
      final sfi = apdu[3] >> 3;
      final record = apdu[2];
      if (sfi == 1 && record == 1) return _ok(recordPayload);
      return _notFound;
    }

    return _notFound;
  }
}

void main() {
  group('penguraian TLV', () {
    test('tag ditemukan di dalam tag bersusun', () {
      final data = _bytes([
        0x70, 0x08, // template
        0x5A, 0x06, 0x60, 0x19, 0x21, 0x00, 0x00, 0x01,
      ]);

      expect(findTag(data, 0x5A), _bytes([0x60, 0x19, 0x21, 0x00, 0x00, 0x01]));
    });

    /// Datanya datang dari kartu orang lain; satu kartu cacat tidak
    /// boleh menjatuhkan halaman pembayaran.
    test('panjang yang melebihi buffer berhenti, bukan melempar', () {
      expect(findTag(_bytes([0x5A, 0x40, 0x12]), 0x5A), isNull);
      expect(findTag(_bytes([0x5A]), 0x5A), isNull);
      expect(findTag(_bytes([]), 0x5A), isNull);
    });

    test('panjang dua byte dibaca', () {
      final value = List.filled(130, 0x11);
      final data = _bytes([0x5A, 0x81, 130, ...value]);

      expect(findTag(data, 0x5A), hasLength(130));
    });
  });

  group('nomor kartu', () {
    test('diambil dari tag 5A tanpa pengisi F', () {
      final record = _bytes([
        0x70,
        0x0A,
        0x5A,
        0x08,
        0x60,
        0x19,
        0x21,
        0x34,
        0x56,
        0x78,
        0x90,
        0x12,
      ]);

      expect(panFrom(record), '6019213456789012');
    });

    /// Nomor yang lebih pendek dari tempatnya diisi nibble "F".
    test('pengisi F di ujung dibuang', () {
      final record = _bytes([
        0x5A,
        0x08,
        0x60,
        0x19,
        0x21,
        0x34,
        0x56,
        0x78,
        0x90,
        0xFF,
      ]);

      expect(panFrom(record), '60192134567890');
    });

    /// Track 2 menggabungkan nomor dan tanggal kedaluwarsa, dipisah "D".
    test('diambil dari Track 2 sebelum pemisah D', () {
      final record = _bytes([
        0x57,
        0x0B,
        0x60,
        0x19,
        0x21,
        0x34,
        0x56,
        0x78,
        0x90,
        0x12,
        0xD2,
        0x81,
        0x22,
      ]);

      expect(panFrom(record), '6019213456789012');
    });

    test('tanpa tag nomor menghasilkan null', () {
      expect(panFrom(_bytes([0x6F, 0x02, 0x84, 0x00])), isNull);
    });
  });

  group('pembacaan kartu', () {
    test('mengikuti PPSE lalu membaca record pertama', () async {
      final card = _FakeCard(
        recordPayload: [
          0x70,
          0x0A,
          0x5A,
          0x08,
          0x60,
          0x19,
          0x21,
          0x34,
          0x56,
          0x78,
          0x90,
          0x12,
        ],
      );

      expect(await readCardNumber(card.transceive), '6019213456789012');

      // Perintah pertamanya menanyakan direktori kartu, bukan AID yang
      // ditebak aplikasi.
      final first = card.sent.first;
      expect(first[1], 0xA4);
      expect(
        String.fromCharCodes(first.sublist(5, 5 + first[4])),
        '2PAY.SYS.DDF01',
      );
    });

    /// Kartu MIFARE Classic — e-Money, TapCash — tidak mengenal APDU
    /// sama sekali. Yang terjadi harus string kosong, bukan error.
    test('kartu yang tidak menjawab menghasilkan kosong', () async {
      Future<Uint8List> refuse(Uint8List apdu) async => _notFound;

      expect(await readCardNumber(refuse), isEmpty);
    });

    test('kartu yang dilepas di tengah jalan tidak melempar', () async {
      Future<Uint8List> disconnect(Uint8List apdu) async =>
          throw StateError('Tag was lost');

      expect(await readCardNumber(disconnect), isEmpty);
    });

    test('kartu tanpa nomor di record mana pun menghasilkan kosong', () async {
      final card = _FakeCard(recordPayload: [0x70, 0x02, 0x82, 0x00]);

      expect(await readCardNumber(card.transceive), isEmpty);
    });
  });
}
