import 'session_info.dart';

/// Status konektor yang dipakai UI.
///
/// - [available]   "Available" — bebas, bisa langsung dipakai.
/// - [preparing]   "Preparing" — kabel baru dicolok, belum mengisi.
///                 Masih boleh dipilih; justru inilah kondisi yang
///                 dibutuhkan `/start`.
/// - [inUse]       "Charging" dan turunannya — sedang mengisi daya.
/// - [unavailable] Rusak, dipesan, atau dimatikan.
enum ConnectorStatus { available, preparing, inUse, unavailable }

class Connector {
  const Connector({
    required this.id,
    required this.status,
    this.displayName,
    this.rawStatus = '',
    this.errorCode = 'NoError',
    this.estimatedMinutes,
    this.session,
  });

  final int id;
  final ConnectorStatus status;

  /// Nama tampilan. Backend belum mengirim tipe/daya konektor, jadi
  /// hanya terisi pada data dummy.
  final String? displayName;

  /// Status mentah dari OCPP, mis. "Available", "Charging", "Faulted".
  /// Disimpan supaya pesan error bisa menyebut kondisi sebenarnya.
  final String rawStatus;
  final String errorCode;

  /// Hanya terisi bila backend mengirim estimasi di `session`.
  final int? estimatedMinutes;

  /// Sesi yang sedang berjalan pada konektor ini. Null berarti tidak
  /// ada pengisian.
  final SessionInfo? session;

  factory Connector.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status'] as String? ?? 'Unknown';
    final errorCode = json['errorCode'] as String? ?? 'NoError';

    return Connector(
      id: (json['id'] as num?)?.toInt() ?? 0,
      rawStatus: rawStatus,
      errorCode: errorCode,
      status: _mapStatus(rawStatus, errorCode),
      estimatedMinutes: _estimatedMinutes(json['session']),
      session: json['session'] is Map<String, dynamic>
          ? SessionInfo.fromJson(json['session'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Pemetaan status OCPP 1.6 ke kelompok UI.
  static ConnectorStatus _mapStatus(String rawStatus, String errorCode) {
    // Error apa pun membuat konektor tidak bisa dipakai, sekalipun
    // status-nya masih "Available".
    if (errorCode != 'NoError') return ConnectorStatus.unavailable;

    return switch (rawStatus) {
      'Available' => ConnectorStatus.available,
      'Preparing' => ConnectorStatus.preparing,
      'Charging' || 'SuspendedEV' || 'SuspendedEVSE' || 'Finishing' =>
        ConnectorStatus.inUse,
      // Reserved, Unavailable, Faulted, dan status tak dikenal.
      _ => ConnectorStatus.unavailable,
    };
  }

  /// Perkiraan sisa waktu dari persentase dan lama pengisian berjalan.
  /// Null bila belum cukup data untuk menghitung.
  static int? _estimatedMinutes(dynamic raw) {
    if (raw is! Map) return null;
    final percent = (raw['percent'] as num?)?.toDouble();
    final elapsed = (raw['durationSeconds'] as num?)?.toDouble();
    if (percent == null || elapsed == null || percent <= 0 || percent >= 100) {
      return null;
    }
    final remaining = elapsed * (100 - percent) / percent;
    return (remaining / 60).ceil();
  }

  /// Bebas sepenuhnya, belum ada kabel tercolok.
  bool get isAvailable => status == ConnectorStatus.available;

  /// Kabel sudah tercolok tapi belum mengisi.
  bool get isPreparing => status == ConnectorStatus.preparing;

  /// Sedang mengisi daya.
  bool get isInUse => status == ConnectorStatus.inUse;

  /// Boleh ditekan pengguna. "Available" dan "Preparing" sama-sama
  /// memulai alur pembelian; "Charging" membuka layar pemantauan.
  /// Hanya konektor rusak atau dimatikan yang tidak bisa ditekan.
  bool get isSelectable => isAvailable || isPreparing || isInUse;

  /// Status OCPP mentah yang berarti kabel sudah tercolok ke kendaraan.
  ///
  /// "Preparing" muncul begitu konektor terpasang tetapi sesi belum
  /// dimulai — inilah saat `/start` boleh dikirim. "Charging" berarti
  /// sesi sudah berjalan.
  static const pluggedInStatuses = {'Preparing', 'Charging'};

  bool get isPluggedIn => pluggedInStatuses.contains(rawStatus);

  bool get hasActiveSession => session != null;

  /// Energi yang sudah tersalur pada sesi berjalan, dalam kWh.
  double? get sessionEnergyKwh => session?.energyKwh;

  /// Jatuh ke nomor konektor bila backend tidak mengirim namanya.
  String get name => displayName ?? 'Konektor $id';
}
