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
| Hubungkan Konektor | `POST /manage-sessioncode` | 1 detik | Menunggu nozzle tercolok; pengguna berdiri di depan charger |
| Sedang Mengisi | `POST /transaction/charging/ongoing-kwh` | 1 detik | Angka kWh harus terlihat bergerak |

Daftar charge box dulu ikut menyegarkan diri tiap dua detik; itu
dihapus karena pemeriksaan statusnya pindah ke layar lain.

Isi charge box di bottom sheet diambil **sekali saat dilihat**, bukan
berkala: `POST /detail-chargerbox` dipanggil ketika bottom sheet daftar
konektor terbuka — satu panggilan untuk seluruh konektornya. Daftar charge box dimuat ulang lewat tarik-ke-bawah
atau saat pengguna kembali ke halaman itu.

Aturan yang dipakai:

- Satu permintaan berjalan dalam satu waktu (`_polling` sebagai
  penjaga), supaya permintaan tidak menumpuk saat jaringan lambat.
- Kegagalan polling **tidak** memunculkan error. Sesi tetap berjalan di
  charger; angka terakhir dibiarkan dan percobaan berikutnya menyusul.
- Timer dibatalkan di `dispose()`.

## Muat ulang saat kembali ke daftar

`appRouteObserver` (sebuah `RouteObserver`) dipasang di
`navigatorObservers`. Halaman Pilih Charge Box berlangganan lewat
`RouteAware`, lalu memuat ulang daftarnya pada `didPopNext()` — yaitu
saat rute di atasnya ditutup.

Bottom sheet "Daftar Konektor" juga terhitung rute di atas, jadi
menutupnya ikut memicu muat ulang. Itu disengaja: begitu sheet hilang,
halaman daftar terlihat lagi dan datanya harus segar.

## Keputusan yang menahan bug

Beberapa hal di kode ini terlihat berlebihan sampai tahu sebabnya.

**Seluruh perintah pengisian berkunci order.** `start`, `stop`, dan
`ongoing-kwh` cukup membawa `orderId` — charge box, konektor, dan
kWh-nya melekat pada ordernya. Daftar charge box tidak membawa orderId,
jadi sesi yang dibuka kembali memperolehnya dari jawaban
`POST /manage-sessioncode` saat kode sesi diverifikasi. `ActiveBooking`
menyimpannya sebagai cadangan. Tanpa salah satunya, halaman status
jatuh ke simulasi lokal alih-alih menembak backend dengan orderId
kosong.

**Energi akhir dibaca ulang setelah stop.** Charger masih menyalurkan
daya beberapa detik setelah perintah berhenti. `StopConfirmPage`
memanggil `ongoing-kwh` sampai lima kali sampai statusnya `4`, alih-alih
memakai angka saat tombol ditekan.

**Energi tersalur ditampilkan apa adanya.** Angka yang tampil adalah
`charged` dari `ongoing-kwh` persis seperti yang dikirim backend —
tidak dibulatkan dan desimalnya tidak dipangkas, hanya titiknya diganti
koma. `formatEnergy` sempat memangkas ke satu desimal mulai 1 kWh dan
tiga desimal di bawahnya; dengan aturan itu 0,126 dan 0,127 kWh tampil
sama, dan angka di layar berselisih dengan catatan backend. Nilai bulat
ditulis tanpa ",0" di ujungnya. Simulasi mode offline yang angkanya
karangan aplikasi sendiri dibulatkan **di sumbernya**, bukan di
formatternya, supaya penjumlahan pecahan biner tidak tampil sebagai
"1,2000000000000002 kWh".

**Tagihan dibulatkan ke bawah.** `usageCostFor()` membulatkan ke bawah
per seribu rupiah agar tagihan tidak pernah melebihi pemakaian
sebenarnya.

**Sesi lanjutan tidak mengarang angka.** Bila pengguna menekan charge
box yang sudah mengisi, aplikasi tidak tahu berapa yang dibayarkan
sebelumnya. `ChargingSession.nominal` bernilai null dan baris pembayaran
disembunyikan, bukan diisi nol.

**Kebijakan sertifikat dihitung ulang tiap ganti alamat.** Lihat
[konfigurasi.md](konfigurasi.md#sertifikat-tls).

**Kode `responseCode` tidak ditebak.** Seluruh kosakatanya ada di
`lib/services/response_code.dart`, disalin dari definisi backend.
Sebelum tabelnya diketahui, tiga kode ditebak dan ketiganya salah —
`12`, `13`, `15` dipakai sebagai error charger padahal berarti error
autentikasi, sehingga tanda tangan yang ditolak muncul sebagai "Charger
menolak perintah". Lihat
[api-backend.md](api-backend.md#koreksi-yang-dibawa-tabel-ini).

**Arti angka `status` ditafsirkan di satu berkas.**
`lib/models/backend_status.dart` memegang kosakata angkanya — 1 bebas,
2 menunggu konektor, 3 mengisi, 4 selesai — supaya perubahan berikutnya
cukup diikuti di satu tempat. `Connector.mapStatus` satu-satunya yang
menerjemahkannya ke `ConnectorStatus`.

## Pemesanan konektor

Konektor dipesan atas nama pengguna sejak ia memilih nozzle, supaya
tidak diambil orang lain selama ia memilih nominal dan membayar.
`POST /booked-connector` dipanggil **sekali** di situ, dan jawabannya
membawa tiga hal yang dipakai sisa alur: `reservationId` untuk
`push-order` dan pembatalan, `sessionCode` yang langsung ditunjukkan di
halaman Kode Sesi, dan `sessionExpired` sebagai hitung mundurnya.

Tahap `connectorStatus` ("R0", lalu "R1" setelah ordernya dibuat)
ditetapkan backend sendiri. Aplikasi dulu mengirimkannya empat kali
untuk menaikkan tahap; sekarang tidak pernah mengirimnya sama sekali,
karena memanggil endpoint itu lagi berarti membuat pemesanan baru.

Yang menahan bug di sini adalah **melepasnya lagi**. Konektor yang
dipesan tidak lepas sendiri, jadi pengguna yang pergi di tengah jalan
akan membuatnya terkunci sampai kedaluwarsa. `ActiveBooking` — dipegang
`ChargingScope`, bukan variabel global, supaya tiap test punya miliknya
sendiri — mencatat pemesanan yang sedang dipegang beserta kode sesinya,
dan `didPopNext()` di halaman Pilih Charge Box melepasnya begitu
pengguna kembali ke sana.

Satu tempat itu menangkap semua jalan keluar: "Kembali", "Batalkan
Transaksi" di halaman Kode Sesi, tombol Home, dan tombol kembali
perangkat semuanya berujung ke halaman daftar. Pemesanannya dilupakan
tanpa dibatalkan begitu perintah start berhasil, sehingga sesi yang
sedang berjalan tidak ikut dilepas.

**Harga tidak pernah dihitung di aplikasi.** `POST /count-kwh` yang
berwenang; `KwhPrice` menyimpan angkanya apa adanya dan `CostRows`
menampilkannya tanpa menurunkan apa pun. Angka turunan yang berselisih
dengan total dari backend lebih buruk daripada rincian yang ringkas.

## Data dummy

`data/demo_data.dart` menyediakan pilihan kWh dan harga tiruan untuk
mode offline, dipakai hanya bila tidak ada `ChargingScope`.
`DemoData.chargeBoxes` sudah tidak dipakai alur utama dan hanya tersisa
untuk test.

Nomor referensi transaksi dan kode sesi tidak lagi dikarang: keduanya
datang dari `POST /transaction/push-order` lewat
`ChargingSession.fromOrder`.

## Pembayaran kartu

Halaman pembayaran menunggu kartu e-Money ditempelkan ke pembaca NFC;
tap kartu itulah yang memajukan alur. Tidak ada tombol bayar.

**Yang bisa dan tidak bisa dibaca.** Nomor seri kartu (UID) selalu
terbaca, tetapi itu nomor chip — bukan nomor uang elektronik 16 digit
yang diminta backend. Untuk nomor itu, `card_number_reader.dart`
menjalankan urutan EMV standar: SELECT PPSE untuk menanyakan aplikasi
apa saja yang ada di kartu, SELECT tiap aplikasi, lalu READ RECORD
sampai ketemu tag `5A` (Application PAN) atau `57` (Track 2). Semua
perintahnya **hanya membaca**.

Yang menjawab hanya kartu ISO-DEP/EMV — Flazz keluaran baru dan
sebagian kartu lain. **e-Money, TapCash, dan Brizzi berbasis MIFARE
Classic**, yang menyimpan nomor dan saldonya di sektor terkunci kunci
milik penerbit; tanpa kunci itu atau SAM (Secure Access Module)
bersertifikat, keduanya tidak terbaca aplikasi Android biasa. Kartu
seperti itu menghasilkan nomor kosong, dan pembayaran jatuh ke
`Env.cardNumber`.

**Saldonya tetap tidak dipotong di sini.** Tap berfungsi sebagai
pemicu: begitu kartu terbaca, aplikasi menanyakan tagihan lewat
`POST /transaction/inquiry-billing` dengan nomor kartu yang didapat.
Gagal di situ menahan alur dan membuka lagi pembacaan kartu.

**Dua hal yang masih menghalangi pemakaian sungguhan.** Pertama, tabel
penerbit di backend baru mengenal empat prefiks percobaan — BIN asli
dibalas `05`, lihat
[api-backend.md](api-backend.md#nomor-kartu-dibaca-dari-kartunya-bila-bisa).
Kedua, pemotongan saldo tetap memerlukan mesin kartu bersertifikat,
yang juga jadi sumber `bankLog`.

Tagihannya lalu dibayar lewat `POST /transaction/payment-billing`,
dengan nomor kartu yang sama seperti saat inquiry. Nominalnya diambil
dari jawaban inquiry, tidak pernah dari angka yang diingat: backend
menolak selisih sekecil apa pun sebagai "Amount mismatch". `bankLog`,
`merchantId`, dan `terminalId` masih nilai tetap karena mesin kartunya
belum ada.

Yang ditampilkan di rincian akhir adalah `ChargingSession.paidAmount`,
yaitu angka yang benar-benar didebit. Tagihan bisa melebihi total order
karena inquiry menambahkan `fee`, `idleFee`, dan `serviceFee`, dan
struk yang menyebut angka lain dari yang terpotong adalah struk yang
salah.

**Abstraksi dan penyuntikan.** `CardReader` (`services/card_reader.dart`)
memisahkan "menunggu kartu" dari NFC-nya, dengan `NfcCardReader` sebagai
implementasi produksi. `CardReaderScope` menyalurkannya, dipasang di
atas `MaterialApp` dengan alasan yang sama seperti `ChargingScope`.
Tanpa abstraksi ini seluruh alur pembayaran tidak bisa diuji, karena
lingkungan test tidak punya NFC.

Tiga keadaan yang ditangani halaman: pembaca siap (menunggu kartu), NFC
mati (arahan menyalakannya plus tombol Periksa Lagi), dan perangkat
tanpa NFC (arahan menghubungi petugas). Tanpa penanganan ini, perangkat
tanpa NFC akan menggantung selamanya di layar "Menunggu Kartu".

Kartu yang masih menempel dilaporkan Android berkali-kali, jadi
`_accepted` memastikan hanya tap pertama yang mendorong halaman.
