import 'package:flutter/widgets.dart';

import '../services/card_reader.dart';

/// Menyediakan pembaca kartu ke halaman pembayaran tanpa menyalurkannya
/// lewat konstruktor setiap halaman di jalur menuju ke sana.
///
/// Harus dipasang di atas MaterialApp, dengan alasan yang sama seperti
/// `ChargingScope`: halaman pembayaran dibuka lewat `Navigator.push`,
/// dan rute yang didorong disisipkan sejajar dengan `home` — bukan
/// sebagai turunannya. Scope yang dipasang sebagai `home` tidak akan
/// terlihat oleh halaman itu.
///
/// Bila scope ini tidak dipasang, halaman pembayaran memakai
/// [NfcCardReader] miliknya sendiri. Di perangkat tanpa NFC — termasuk
/// lingkungan test — pembaca itu melapor [CardReaderStatus.unsupported]
/// dan halamannya menjelaskan keadaan itu alih-alih menggantung.
class CardReaderScope extends InheritedWidget {
  CardReaderScope({super.key, required super.child, CardReader? reader})
    : reader = reader ?? NfcCardReader();

  final CardReader reader;

  static CardReader? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CardReaderScope>()?.reader;

  @override
  bool updateShouldNotify(CardReaderScope oldWidget) =>
      reader != oldWidget.reader;
}
