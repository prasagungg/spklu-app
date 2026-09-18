import 'package:flutter/widgets.dart';

import 'charge_point_repository.dart';

/// Menyediakan akses backend ke seluruh alur pengisian tanpa harus
/// menyalurkan repository lewat konstruktor setiap halaman.
///
/// Bila scope ini tidak dipasang, [maybeOf] mengembalikan null dan
/// halaman-halaman berjalan dalam mode offline: `/start` dan `/stop`
/// dilewati, dan angka kWh disimulasikan lokal. Itulah mode yang
/// dipakai widget test supaya tidak menyentuh jaringan.
class ChargingScope extends InheritedWidget {
  ChargingScope({
    super.key,
    required super.child,
    ChargePointRepository? repository,
  }) : repository = repository ?? ChargePointRepository();

  final ChargePointRepository repository;

  static ChargingScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChargingScope>();

  @override
  bool updateShouldNotify(ChargingScope oldWidget) =>
      repository != oldWidget.repository;
}
