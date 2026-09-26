/// Kontak bantuan dari `GET /evtap/bantuan`.
///
/// ```json
/// { "email": "bantuan@pln.co.id", "hotline": "123",
///   "whatsapp": "+62 851 2345 6789" }
/// ```
///
/// Backend membalas ketiganya kosong bila belum diatur, jadi field yang
/// kosong tidak ditampilkan alih-alih memunculkan baris hampa.
class HelpContact {
  const HelpContact({this.email = '', this.hotline = '', this.whatsapp = ''});

  final String email;
  final String hotline;
  final String whatsapp;

  /// Tidak ada satu pun kontak yang bisa ditampilkan.
  bool get isEmpty => email.isEmpty && hotline.isEmpty && whatsapp.isEmpty;

  /// Nomor WhatsApp dalam bentuk yang diterima tautan `wa.me`: hanya
  /// angka, tanpa plus, spasi, atau tanda hubung.
  String get whatsappDigits => whatsapp.replaceAll(RegExp(r'[^0-9]'), '');

  /// Tautan chat WhatsApp; kosong bila nomornya tidak ada.
  String get whatsappLink =>
      whatsappDigits.isEmpty ? '' : 'https://wa.me/$whatsappDigits';

  factory HelpContact.fromJson(Map<String, dynamic>? json) => HelpContact(
    email: json?['email'] as String? ?? '',
    hotline: json?['hotline'] as String? ?? '',
    whatsapp: json?['whatsapp'] as String? ?? '',
  );
}
