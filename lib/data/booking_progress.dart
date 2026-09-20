import 'dart:async';

import 'package:flutter/widgets.dart';

import '../models/booking.dart';
import 'charging_scope.dart';

/// Menaikkan tahap booking tanpa menghalangi pengguna.
///
/// Dipakai untuk R1–R3. Konektornya sudah dikunci sejak R0, jadi tahap
/// berikutnya hanya laporan kemajuan: kegagalannya dicatat ke log dan
/// alurnya jalan terus. Menghentikan pengguna di tengah pembelian
/// karena satu laporan meleset akan jauh lebih merugikan daripada
/// tahapnya tertinggal satu langkah di backend.
///
/// Tanpa [ChargingScope] — mode offline untuk test — tidak ada yang
/// dikirim.
void reportBookingStage(
  BuildContext context, {
  required String chargeBoxId,
  required int connectorId,
  required BookingStage stage,
}) {
  final scope = ChargingScope.maybeOf(context);
  if (scope == null) return;

  scope.booking.advance(stage);
  final repository = scope.repository;

  unawaited(
    repository
        .bookConnector(
          chargeBoxId: chargeBoxId,
          connectorId: connectorId,
          stage: stage,
        )
        .then(
          (result) => debugPrint('[FLOW] Booking ${stage.code}: $result'),
        )
        .catchError((Object e) {
          debugPrint('[FLOW] Booking ${stage.code} gagal dilaporkan: $e');
        }),
  );
}
