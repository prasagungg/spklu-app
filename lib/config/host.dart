/// Membereskan alamat backend yang diketik manusia, dan mengenali
/// alamat yang berada di jaringan lokal.
class Host {
  const Host._();

  /// Melengkapi alamat yang ditulis seadanya menjadi URL utuh.
  ///
  /// Edge controller kerap dijalankan di perangkat lokal, sehingga yang
  /// diketik sering hanya `192.168.1.10:8080` atau bahkan `10.0.2.2`.
  /// Tanpa skema, Dio menolak alamat itu. Yang tidak berskema dianggap
  /// `http://` — perangkat di jaringan lokal jarang memakai TLS.
  ///
  /// ```
  /// 192.168.1.10:8080  -> http://192.168.1.10:8080
  /// 10.0.2.2           -> http://10.0.2.2
  /// http://host/api/   -> http://host/api
  /// https://host/api   -> https://host/api
  /// ```
  static String normalizeBaseUrl(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return value;

    if (!value.contains('://')) value = 'http://$value';

    // Path digabung Dio dengan path relatif yang sudah berawalan "/",
    // jadi garis miring di ujung hanya menghasilkan "//".
    while (value.length > 1 && value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  /// Apakah [url] menunjuk ke jaringan lokal atau perangkat ini sendiri.
  ///
  /// Dipakai untuk memutuskan apakah sertifikat TLS yang tidak
  /// tepercaya boleh diterima: edge controller di LAN biasanya memakai
  /// sertifikat self-signed, sedangkan host publik tidak boleh
  /// diperlakukan begitu.
  static bool isPrivate(String url) {
    final uri = Uri.tryParse(normalizeBaseUrl(url));
    if (uri == null) return false;
    return isPrivateHost(uri.host);
  }

  static bool isPrivateHost(String host) {
    if (host.isEmpty) return false;
    if (host == 'localhost' || host.endsWith('.local')) return true;

    final octets = host.split('.');
    if (octets.length != 4) return false;

    final numbers = <int>[];
    for (final octet in octets) {
      final value = int.tryParse(octet);
      if (value == null || value < 0 || value > 255) return false;
      numbers.add(value);
    }

    final [a, b, _, _] = numbers;
    return switch (a) {
      10 => true,
      127 => true,
      // 172.16.0.0/12
      172 => b >= 16 && b <= 31,
      // 192.168.0.0/16
      192 => b == 168,
      // 100.64.0.0/10 — dipakai CGNAT dan Tailscale.
      100 => b >= 64 && b <= 127,
      _ => false,
    };
  }
}
