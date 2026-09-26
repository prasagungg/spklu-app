/// Jenis autentikasi charge box pada `POST /master/set-chargerbox-evtap`.
///
/// Backend hanya menerima tiga nilai ini (`ErrInvalidAuthType`), jadi
/// petugas memilihnya alih-alih mengetiknya.
abstract final class AuthType {
  static const none = 'NONE';
  static const usernamePassword = 'USERNAME_PASSWORD';
  static const basic = 'BASIC_AUTH';

  /// Bawaannya BASIC_AUTH — yang dipakai charger di lapangan.
  static const values = [basic, usernamePassword, none];

  /// Label yang dibaca petugas.
  static String label(String value) => switch (value) {
    basic => 'Basic Auth',
    usernamePassword => 'Username & Password',
    none => 'Tanpa Autentikasi',
    _ => value,
  };
}
