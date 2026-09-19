# Arsitektur

## Lapisan

Tidak ada pustaka state management. Yang dipakai hanya `StatefulWidget`
untuk state layar dan satu `InheritedWidget` untuk menyalurkan akses
backend. Itu cukup karena aplikasi ini kecil dan hampir seluruh state-nya
milik satu layar saja.

```
         pages/
            │  ChargingScope.maybeOf(context)
            ▼
   data/charging_scope.dart        InheritedWidget, di atas MaterialApp
            │
            ▼
   data/charge_point_repository.dart
            │  endpoint, amplop response, kode error bisnis
            ▼
   services/api_client.dart        satu Dio: base URL, timeout, header
            ├── services/api_exception.dart   DioException → pesan Indonesia
            └── services/api_logger.dart      satu baris log per request
```

`models/` dipakai semua lapisan; `widgets/` dan `theme/` hanya dipakai
`pages/`.

## Aturan tiap lapisan

**`services/api_client.dart`** — satu-satunya tempat Dio dikonfigurasi.
Base URL, timeout, header, dan `validateStatus` diatur di sini supaya
tidak tersebar. `validateStatus` sengaja menolak 4xx/5xx agar semuanya
masuk ke `DioException` dan diterjemahkan seragam.

**`services/api_exception.dart`** — menerjemahkan kegagalan menjadi
pesan berbahasa Indonesia plus `ApiErrorType`. Widget tidak perlu tahu
`DioException` itu apa. Pesan dari backend (`responseMessage`)
didahulukan bila ada.

**`data/charge_point_repository.dart`** — memetakan endpoint ke method,
membuka amplop response, dan melempar `ApiException` bila
`responseCode` bukan `"00"`. Di sinilah nama kode error bisnis
didefinisikan (`ChargeErrorCode`).

**`models/`** — hanya parsing dan perhitungan murni. Tidak ada yang
menyentuh jaringan atau `BuildContext`, sehingga bisa diuji tanpa
widget.

**`pages/`** — memegang timer, polling, dan navigasi. Satu berkas per
frame Figma; nomor node-nya ditulis di komentar kelas supaya mudah
dicocokkan dengan desain.

**`theme/`** — sumber kebenaran tunggal warna dan gaya teks. Jangan
tulis hex di widget.

## ChargingScope dan mode offline

`ChargingScope` menyediakan `ChargePointRepository` ke seluruh pohon
widget tanpa menyalurkannya lewat konstruktor tiap halaman.

Dua hal yang penting:

**Scope harus berada di atas `MaterialApp`, bukan sebagai `home:`.**
Rute yang dibuka lewat `Navigator.push` disisipkan sejajar dengan `home`
di bawah Navigator, bukan sebagai turunannya. Kalau scope dipasang
sebagai `home`, `ChargingScope.maybeOf()` mengembalikan null di semua
halaman lanjutan dan `/start` maupun `/stop` tidak pernah terkirim.
`test/charging_scope_test.dart` mengunci perilaku ini.

**Scope yang tidak ada berarti mode offline.** `maybeOf()` yang
mengembalikan null membuat halaman melewati `/start` dan `/stop` serta
menyimulasikan kenaikan kWh secara lokal. Itulah mode yang dipakai
widget test supaya tidak menyentuh jaringan, dan alasan hampir semua
halaman bisa dirender sendirian di test.

## Polling, bukan push

Controller tidak mengirim notifikasi, jadi semua perubahan status
diketahui dengan menanyai berkala. Jedanya ada di `Env`:

| Layar | Endpoint | Jeda | Alasan |
|---|---|---|---|
| Pilih Charge Box | `GET /list` | 2 detik | Charger bisa tersambung atau terputus kapan saja |
| Hubungkan Konektor | `GET /list` | 2 detik | Pengguna sedang berdiri di depan charger menunggu |
| Sedang Mengisi | `GET /progress` | 1 detik | Angka kWh harus terlihat bergerak |

Aturan yang dipakai konsisten di ketiganya:

- Satu permintaan berjalan dalam satu waktu (`_polling` / `_checking`
  sebagai penjaga), supaya permintaan tidak menumpuk saat jaringan
  lambat.
- Kegagalan polling **tidak** memunculkan error. Sesi tetap berjalan di
  charger; angka terakhir dibiarkan dan percobaan berikutnya menyusul.
- Timer dibatalkan di `dispose()`.
- Halaman daftar juga memeriksa `ModalRoute.of(context)?.isCurrent`
  sebelum menembak, supaya tidak berisik saat tertutup halaman lain.

## Muat ulang saat kembali ke daftar

`appRouteObserver` (sebuah `RouteObserver`) dipasang di
`navigatorObservers`. Halaman Pilih Charge Box berlangganan lewat
`RouteAware`, lalu memuat ulang `/list` pada `didPopNext()` — yaitu saat
rute di atasnya ditutup.

Bottom sheet "Daftar Konektor" juga terhitung rute di atas, jadi
menutupnya ikut memicu muat ulang. Itu disengaja: begitu sheet hilang,
halaman daftar terlihat lagi dan datanya harus segar.

## Keputusan yang menahan bug

Beberapa hal di kode ini terlihat berlebihan sampai tahu sebabnya.

**`connectorId` wajib di `fetchProgress`.** Backend menerima permintaan
tanpa parameter itu dan mengembalikan konektor mana pun yang sedang
aktif; salah ejaan seperti `connecterId` juga diabaikan tanpa error.
Dua-duanya gagal secara senyap, jadi pemanggil dipaksa menyebut
konektornya. Ada test khusus untuk ejaannya.

**Energi akhir dibaca ulang setelah `/stop`.** Charger masih menyalurkan
daya beberapa detik setelah perintah berhenti. `StopConfirmPage`
memanggil `/progress` sampai lima kali sampai `state` menjadi
`"finished"`, alih-alih memakai angka saat tombol ditekan.

**Desimal kWh menyesuaikan.** Di bawah 1 kWh dipakai tiga desimal.
Dengan satu desimal, 127 Wh tampil "0,1 kWh" dan 3 Wh tampil "0,0 kWh",
sehingga pengisian yang baru mulai terlihat mandek.

**Tagihan dibulatkan ke bawah.** `usageCostFor()` membulatkan ke bawah
per seribu rupiah agar tagihan tidak pernah melebihi pemakaian
sebenarnya.

**Sesi lanjutan tidak mengarang angka.** Bila pengguna menekan charge
box yang sudah mengisi, aplikasi tidak tahu berapa yang dibayarkan
sebelumnya. `ChargingSession.nominal` bernilai null dan baris pembayaran
disembunyikan, bukan diisi nol.

**Kebijakan sertifikat dihitung ulang tiap ganti alamat.** Lihat
[konfigurasi.md](konfigurasi.md#sertifikat-tls).

## Data dummy

`data/demo_data.dart` masih menyediakan daftar nominal yang dipakai
halaman Pilih Nominal — backend belum punya endpoint harga.
`DemoData.chargeBoxes` sudah tidak dipakai alur utama dan hanya tersisa
untuk test.

Hal lain yang masih dibangkitkan lokal: nomor referensi transaksi, kode
sesi (`ChargingSession.demo`), dan pembayaran kartu e-Money yang memakai
tombol "Bayar (Simulasi)" karena tap kartu sungguhan butuh perangkat
NFC.
