import 'package:flutter/widgets.dart';

/// Memberi tahu halaman ketika rute di atasnya ditutup, sehingga
/// halaman itu bisa memuat ulang datanya saat kembali terlihat.
///
/// Dipasang di `navigatorObservers` pada MaterialApp; halaman yang
/// butuh memakainya cukup `with RouteAware` lalu berlangganan.
final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();
