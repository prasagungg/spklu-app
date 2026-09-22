# API edge controller

Semua endpoint relatif terhadap base URL yang diatur di halaman
Konfigurasi Server. Base URL sudah memuat prefiks path-nya — misalnya
`https://contoh.id/api` membuat `/list` menjadi
`https://contoh.id/api/list`.

Implementasinya ada di `lib/data/charge_point_repository.dart`.

## Header tanda tangan

Setiap request wajib membawa tiga header. Tanpa ketiganya server
membalas **401**.

| Header | Isi |
|---|---|
| `client-id` | Identitas pemanggil, mis. `edge` |
| `timestamp` | ISO 8601 UTC tanpa pecahan detik, mis. `2026-09-19T10:23:45Z` |
| `signature` | HMAC-SHA256 dalam hex huruf kecil |

Tanda tangannya dibentuk begini:

```
key       = SHA1(secretKey)                               -> hex huruf kecil
signature = HMAC-SHA256(body + clientId + timestamp, key) -> hex huruf kecil
```

Dua hal yang mudah salah dan membuat tanda tangan ditolak:

- **Kunci HMAC adalah teks hex SHA1, bukan 20 byte mentahnya.** Skrip
  acuan memanggil `CryptoJS.HmacSHA256(pesan, key)` dengan `key` berupa
  String, dan CryptoJS memperlakukan String sebagai UTF-8 — jadi yang
  dipakai adalah 40 karakter hex itu apa adanya.
- **Yang ditandatangani harus persis byte yang dikirim.** Menyerialisasi
  body dua kali bisa menghasilkan urutan atau spasi yang berbeda.
  `SignatureInterceptor` menyerialisasi sekali lalu menuliskannya
  kembali ke request, sehingga Dio mengirim JSON yang sama.

Request tanpa body — semua GET — ditandatangani dengan body kosong.
Query string **tidak** ikut ditandatangani.

Implementasinya di `lib/services/signature_interceptor.dart`; nilai
`clientId` dan `secretKey` diatur lewat `--dart-define`, lihat
[konfigurasi.md](konfigurasi.md#--dart-define).

## Amplop response

Setiap response dibungkus amplop yang sama:

```json
{
  "responseCode": "00",
  "responseMessage": "Success",
  "data": { }
}
```

`_unwrap()` memeriksa amplop ini dan melempar `ApiException` bila
`responseCode` bukan `"00"`, lalu mengembalikan isi `data`. Kegagalan
sebenarnya dibalas dengan status 4xx/5xx, jadi pemeriksaan ini terutama
menangkap kasus status 2xx tetapi kodenya bukan sukses.

`data` yang null atau bukan objek dikembalikan sebagai null, bukan
error — ada endpoint yang memang tidak selalu punya isi.

## `POST /list-chargerbox`

Isi satu lokasi SPKLU beserta charge box dan konektornya. Lokasinya
disebut lewat body:

```json
{ "idSpklu": "SPKLU-SMR" }
```

Nilainya diambil dari `Env.idSpklu` (`--dart-define=SPKLU_ID`), yaitu
lokasi tempat unit dipasang.

Response:

```json
{
  "responseCode": "00",
  "responseMessage": "Success",
  "data": {
    "idSpklu": "SPKLU-SMR",
    "namaSpklu": "PLN Charging Station Sisingamangaraja",
    "alamatSpklu": "Jl. Sisingamangaraja No. 1, Jakarta Selatan",
    "status": 1,
    "dayaSpklu": "200 kW",
    "chargeBoxes": [
      {
        "chargeBoxId": "CB-SMR-01",
        "merek": "Kempower",
        "status": 1,
        "namaChargeBox": "Kempower Satellite 200 kW",
        "connectors": [
          {
            "connectorId": "1",
            "chargeBoxId": "CB-SMR-01",
            "status": 1,
            "namaKonektor": "Gun 1",
            "typeConnector": "CCS2",
            "connectorTypeCurrent": "DC",
            "estimationAvailable": null
          }
        ]
      }
    ]
  }
}
```

Diurai menjadi `Spklu` → `ChargeBox` → `Connector`.

Catatan:

- **Angka `status` pada konektor** menggambarkan perjalanan satu sesi:

  | `status` | Arti | `ConnectorStatus` |
  |---|---|---|
  | `1` | Belum dibayar atau masih bisa dipakai | `available` |
  | `2` | Sudah dibayar, menunggu konektor dihubungkan | `preparing` |
  | `3` | Sedang mengisi | `inUse` |
  | `4` | Pengisian selesai | `finished` |
  | lainnya | Tidak dikenal | `unavailable` |

  Seluruh aplikasi menafsirkannya lewat `lib/models/backend_status.dart`
  saja, jadi perubahan kosakata cukup diikuti di satu tempat.
- **`status` pada charge box dan SPKLU belum dipakai.** Keempat angka di
  atas menggambarkan keadaan sesi pada satu konektor, dan belum
  diketahui apakah kosakata yang sama berlaku di tingkat charge box.
  Ketersediaan kartu karena itu ditentukan konektornya saja — memakai
  angka yang belum pasti di sini berisiko mematikan kartu yang
  sebenarnya sedang melayani pengisian.
- **`connectorId` dikirim sebagai teks** (`"1"`), sedangkan `/start`,
  `/stop`, dan `/progress` menerimanya sebagai angka. Diurai sekali di
  `Connector.fromJson`.
- **Tidak ada objek `session`.** Endpoint ini tidak membawa kemajuan
  sesi yang sedang berjalan; angka kWh selalu datang dari `/progress`.
- **Status `2` tidak berarti kabel sudah tercolok** — artinya pengguna
  sedang *diminta* menghubungkannya. Deteksi kabel tercolok di halaman
  Hubungkan Konektor karena itu masih menunggu endpoint pengecekan
  terpisah.
- **Nomor charge box tidak dikirim backend.** Urutan tampil (01, 02, …)
  diambil dari posisi di daftar.
- `chargeBoxes` kosong adalah kondisi normal dan menghasilkan daftar
  kosong, bukan error.
- Keterangan lokasi — `namaSpklu`, `alamatSpklu`, `dayaSpklu` — diurai
  ke `Spklu` tetapi belum ditampilkan di layar mana pun.

## `POST /status-konektor`

Status sebenarnya satu konektor.

```json
{ "spkluId": "SPKLU-SMR", "chargeBoxId": "CB-SMR-01", "connectorId": "1" }
```

```json
{
  "responseCode": "00",
  "responseMessage": "Success",
  "data": {
    "spkluId": "SPKLU-SMR",
    "chargeBoxId": "CB-SMR-01",
    "chargeBoxName": "Kempower Satellite 200 kW",
    "connectorName": "Gun 1",
    "connectorId": "1",
    "connectorStatus": 1
  }
}
```

`connectorStatus` memakai kosakata angka yang sama seperti tabel di
`POST /list-chargerbox` di atas.

**Kapan dipanggil.** Status konektor tidak terlihat dari daftar charge
box, jadi ini dipanggil ketika pengguna membuka daftar konektor sebuah
charge box — satu permintaan per konektor, sekali saja. Tidak ada
polling: status cukup diperiksa saat pengguna melihatnya.

Selama jawabannya belum datang, konektor menampilkan chip "Memeriksa…"
dan belum bisa ditekan — tujuannya ditentukan status, jadi menekannya
lebih awal bisa salah arah. Konektor yang gagal diperiksa memakai status
dari daftar, supaya satu permintaan yang meleset tidak mengosongkan
seluruh sheet.

Konektor yang tidak dikenal dibalas 404 dengan `responseCode` `04`.

## `GET /list-kwh`

Pilihan kWh yang bisa dibeli.

```json
{ "responseCode": "00", "responseMessage": "Success",
  "data": { "list": [10, 20, 30] } }
```

Dipanggil sekali saat halaman Pilih Nominal dibuka. Daftar kosong
ditampilkan sebagai keadaan kosong, bukan error.

## `POST /count-kwh`

Rincian harga untuk sejumlah kWh pada satu konektor.

```json
{ "chargeBoxId": "CB-SMR-01", "connectorId": "1", "kwh": 10 }
```

```json
{
  "responseCode": "00",
  "responseMessage": "Success",
  "data": {
    "chargeBoxId": "CB-SMR-01", "connectorId": "1", "kwh": 10,
    "rpJaminanSpklu": 0, "rpAdmin": 0, "rpDiskon": 0,
    "rpPerKwh": 2466.78, "rpPpj": 2467, "rpPpn": 0,
    "rpTotal": 27135, "rpLayanan": 0, "rpMaterai": 0, "idleFee": 0
  }
}
```

Dipanggil setiap kali pengguna menekan salah satu pilihan kWh — jadi
sekali per penekanan, bukan berkala.

**Aplikasi tidak menghitung apa pun.** Semua angka ditampilkan apa
adanya, termasuk tidak mengalikan `kwh` dengan `rpPerKwh` untuk membuat
baris "Biaya Listrik": angka turunan yang berselisih dengan `rpTotal`
hanya membingungkan. Yang ditampilkan adalah tarif per kWh, PPJ-TL,
PPN, lalu biaya tambahan yang tidak nol, dan `rpTotal` sebagai Total
Pembayaran.

`rpPerKwh` adalah satu-satunya nilai rupiah yang pecahan, ditampilkan
lewat `formatRupiahDecimal` sebagai "Rp2.466,78".

### Yang diamati saat pengujian

Playground membalas **angka yang sama persis untuk kWh berapa pun** —
`rpTotal: 27135` untuk 10, 20, 30, bahkan 7 kWh; hanya `kwh` yang
bergema. Aritmetikanya cocok untuk 10 kWh (10 × 2466,78 + 2467 =
27134,8 ≈ 27135), jadi tampaknya harganya belum dihitung ulang untuk
nilai lain. `kwh` yang di luar daftar `/list-kwh` pun diterima.

Ini alasan lain kenapa aplikasi tidak menurunkan angka sendiri: kalau
"Biaya Listrik" dihitung dari kWh × tarif, untuk 30 kWh ia akan jauh
melebihi total yang dikirim backend.

## `POST /transaction/push-order`

Membuat order untuk kWh yang dipilih. Dipanggil saat "Lanjutkan"
ditekan di halaman Pilih Nominal.

```json
{ "chargeBoxId": "CB-SMR-01", "connectorId": "1", "kwh": 10 }
```

```json
{
  "responseCode": "00",
  "responseMessage": "Success",
  "data": {
    "orderId": "ADWTJU5D56QGZNXTTNOX9YZFTN",
    "chargeBoxId": "CB-SMR-01",
    "chargeBoxName": "Kempower Satellite 200 kW",
    "connectorName": "Gun 1", "connectorId": "1",
    "partnerReference": "81067", "sessionCode": "29",
    "sessionExpiredTime": "2026-09-22T04:22:14Z",
    "kwh": 10, "rpPerKwh": 2466, "rpPpj": 740, "rpPpn": 0,
    "rpTotal": 25400, "rpLayanan": 0, "rpMaterai": 0,
    "rpKwh": 24660, "idleFee": 0, "serviceFee": 0
  }
}
```

Inilah sumber tiga hal yang sebelumnya **dikarang aplikasi**:

| Field | Dipakai sebagai |
|---|---|
| `orderId` | Identitas order, disimpan di `ChargingSession.orderId` |
| `sessionCode` | Kode yang dipakai pengguna mengakhiri sesinya |
| `partnerReference` | "No Reference" pada Detail Transaksi |

Rinciannya juga lebih lengkap daripada `/count-kwh`: ada **`rpKwh`**,
biaya energi sebagai angka tersendiri, jadi baris "Biaya Listrik" muncul
di halaman Konfirmasi tanpa aplikasi perlu menghitungnya. Angkanya
konsisten — 24.660 + 740 = 25.400.

### Yang diamati saat pengujian

- **Hanya satu order tertunda per konektor.** Push kedua dibalas
  `responseCode` `16` "Processing Another Request" (HTTP 409).
- **`POST /cancelled-connector` tidak melepas order yang tertunda.**
  Setelah konektor dibatalkan, push berikutnya tetap dibalas `16`.
- `orderId` dan `sessionCode` baru setiap order; `partnerReference`
  tetap pada playground.
- `sessionExpiredTime` menyebut kapan ordernya kedaluwarsa. Lewat dari
  itu backend membalas `21` — baik saat menagih maupun saat memulai
  pengisian. Diurai ke `Order.sessionExpiredAt`, tetapi belum
  ditampilkan di layar mana pun.
- Angkanya **berbeda dari `/count-kwh`** untuk kWh yang sama — 2466 vs
  2466,78 per kWh, PPJ 740 vs 2467, total 25.400 vs 27.135. Yang
  berlaku adalah angka order, dan itulah yang ditampilkan sejak halaman
  Konfirmasi.

Kode `16` diterjemahkan jadi arahan yang bisa ditindaklanjuti — "Masih
ada pesanan yang belum selesai di konektor ini" — bukan pesan mentah
backend.

## `POST /transaction/inquiry-billing`

Menanyakan tagihan satu order untuk kartu tertentu, sebelum didebit.
Dipanggil begitu kartu ditempelkan di halaman Pembayaran.

```json
{ "orderId": "QHGQM7SNQ6IY7GQLQDSLTY2RJI",
  "cardNumber": "0123456789012345" }
```

```json
{
  "responseCode": "00",
  "responseMessage": "Success",
  "data": {
    "orderId": "QHGQM7SNQ6IY7GQLQDSLTY2RJI",
    "pspId": "EM-BNI", "cardNumber": "0123456789012345",
    "amount": 25400, "fee": 0, "idleFee": 0, "serviceFee": 0,
    "totalAmount": 25400, "sessionCode": ""
  }
}
```

### Nomor kartu masih tetap

NFC hanya bisa membaca nomor seri kartu, bukan nomor uang elektroniknya
— lihat [arsitektur.md](arsitektur.md#pembayaran-kartu). Yang dikirim
karena itu `Env.cardNumber`, bisa diganti lewat
`--dart-define=SPKLU_CARD_NUMBER=…`.

Empat digit pertamanya menentukan penerbit yang dikenali backend:

| Prefix | `pspId` |
|---|---|
| `0123` | EM-BNI |
| `4567` | EM-BRI |
| `8901` | EM-BCA |
| `2345` | EM-MANDIRI |

Bawaannya `0123456789012345` (EM-BNI).

### Yang diamati saat pengujian

- **Prefix diperiksa lebih dulu.** Prefix di luar keempatnya dibalas
  `responseCode` `05`, "E-Money Provider Is Not Supported" (400) —
  bahkan sebelum ordernya dicari.
- **Idempoten**: panggilan kedua untuk order dan kartu yang sama
  membalas persis sama.
- Panjang nomor tidak diperiksa; yang penting prefiksnya.
- Order yang tidak ditemukan dibalas `responseCode` `21`, "Transaction
  Not Found" (404).
- **`sessionCode` di sini dikirim kosong.** Yang berlaku adalah
  `sessionCode` dari `push-order`, dan aplikasi tidak menimpanya dengan
  nilai dari sini.

Kegagalan menahan alur: pengguna tidak dibiarkan maju ke "Pembayaran
Berhasil" untuk tagihan yang tidak pernah terverifikasi. Sesi NFC dibuka
lagi supaya kartu bisa ditempelkan ulang.

Saldonya sendiri **belum dipotong** — penagihan sungguhan menyusul
setelah inquiry, dan tempat memanggilnya sudah ditandai di
`CardPaymentPage._settleBilling`.

## `POST /transaction/payment-billing`

Membayar tagihan yang sudah ditanyakan. Dipanggil tepat setelah
inquiry, dalam rangkaian yang sama saat kartu terdeteksi.

```json
{ "orderId": "F3YYZCWLRC4FPR1YDZ7F1A30ID", "amount": 145670,
  "cardNumber": "0123456789012345",
  "bankLog": "1231408098812345678100500" }
```

Jawabannya sama dengan inquiry, ditambah `bankLog` sebagai bukti
transaksi:

```json
{
  "responseCode": "00", "responseMessage": "Success",
  "data": {
    "orderId": "F3YYZCWLRC4FPR1YDZ7F1A30ID",
    "pspId": "EM-BNI", "cardNumber": "0123456789012345",
    "amount": 145670, "fee": 0, "idleFee": 0, "serviceFee": 0,
    "totalAmount": 145670, "sessionCode": "",
    "bankLog": "1231408098812345678100500"
  }
}
```

### `amount` harus persis dari inquiry

Nilai lain dibalas `responseCode` `25`, "Amount mismatch" (422) — **total
order pun ditolak** kalau berbeda. Terbukti saat pengujian: order
bernilai 145.670, dibayar dengan 25.400 → `25`. Aplikasi karena itu
selalu mengirim `totalAmount` dari jawaban inquiry, tidak pernah angka
yang diingat atau dihitung sendiri.

Inquiry menambahkan `fee`, `idleFee`, dan `serviceFee` di atas `amount`,
jadi tagihan memang bisa berbeda dari total order. Yang ditampilkan di
rincian akhir adalah angka yang benar-benar didebit
(`ChargingSession.paidAmount`), bukan total order.

### `bankLog` wajib

Tanpa field itu dibalas `responseCode` `07`, "Missing Field: bankLog".
Isinya bukti transaksi dari mesin kartu; masih nilai tetap dari
`Env.bankLog` karena mesin kartunya belum ada, bisa diganti lewat
`--dart-define=SPKLU_BANK_LOG=…`.

### Yang diamati saat pengujian

- **Idempoten**: pembayaran kedua untuk order yang sama dibalas sukses,
  bukan `23` "Transaction already paid".
- Inquiry setelah pembayaran membalas sama seperti sebelumnya — tidak
  ada penanda sudah dibayar di jawabannya.
- **Membayar tidak melepas konektor.** Push order berikutnya pada
  konektor yang sama tetap dibalas `16`.
- Order kedaluwarsa cukup cepat: order yang dibuat beberapa menit
  sebelumnya sudah dibalas `21` "Transaction Not Found".

## `POST /manage-sessioncode`

```json
{ "chargeBoxId": "CB-SMR-01", "connectorId": "1", "sessionCode": "29" }
```

```json
{
  "responseCode": "00", "responseMessage": "Success",
  "data": {
    "chargeboxId": "delta_sensi",
    "chargeboxName": "Delta DC Wallbox",
    "connectorName": "AC TYPE 2 - 7.0",
    "connectorId": "1",
    "sessionCode": "29",
    "statusProcess": 1
  }
}
```

Dipakai dua tempat yang berbeda.

### Memeriksa kode sesi

Saat pengguna menekan konektor yang sedang dipakai, kode yang ia ketik
diperiksa di sini. Kode sesi melekat pada order, jadi aplikasi tidak
bisa — dan tidak boleh — memutuskannya sendiri. Sebelum endpoint ini
ada, verifikasi membandingkan dengan `SPKLU_SESSION_PIN` yang tetap,
sehingga kode yang ditunjukkan di layar "Pengisian Dimulai" sebenarnya
tidak membuka apa-apa.

### Memantau nozzle

`statusProcess` memakai kosakata angka yang sama dengan status konektor:
`1` belum bayar, `2` menunggu konektor dihubungkan, `3` sedang mengisi,
`4` selesai.

Halaman Hubungkan Konektor memanggil endpoint ini **tiap detik** dan
menunggu angkanya berpindah dari `2`. Selama masih `2`, tombol "Mulai
Pengisian" tetap mati. Inilah deteksi kabel tercolok yang sebelumnya
tidak ada penggantinya sejak `/list` diganti.

Angka yang **tidak dikenal tidak dianggap tercolok**. Menebaknya akan
mengirim perintah start yang pasti ditolak charger.

### Ejaan `chargeBoxId`

Endpoint ini sempat mengeja `chargeboxId` dengan b kecil sebelum
dirapikan. Penguraiannya menerima kedua ejaan, supaya versi backend
yang berbeda tidak memecahkan aplikasi.

### `orderId` menutup alurnya

Jawabannya menyertakan `orderId`, sehingga sesi yang dibuka kembali bisa
dipantau dan dihentikan — semua perintah pengisian berkunci order,
sedangkan daftar charge box tidak membawanya. Order yang diingat
`ActiveBooking` hanya dipakai sebagai cadangan bila field itu kosong.

Terkonfirmasi lewat pengujian: `sessionCode` wajib (`07` tanpa itu),
kode yang tidak cocok dibalas `21`, dan kode yang benar mengembalikan
order beserta `statusProcess`.

## `POST /booked-connector`

Mengunci konektor atas nama pengguna yang sedang memakai unit ini, lalu
menaikkan tahapnya seiring alur pembelian.

```json
{ "chargeBoxId": "CB-SMR-01", "connectorId": "1", "connectorStatus": "R0" }
```

```json
{
  "responseCode": "00",
  "responseMessage": "Success",
  "data": {
    "chargeBoxId": "CB-SMR-01",
    "chargeBoxName": "Kempower Satellite 200 kW",
    "connectorName": "Gun 1",
    "connectorId": "1",
    "connectorStatus": "R0",
    "status": true
  }
}
```

| Tahap | Arti | Dikirim saat |
|---|---|---|
| `R0` | Nozzle dipilih — konektor dikunci | Konektor ditekan di bottom sheet |
| `R1` | Order sedang dibuat | "Lanjutkan" di Pilih Nominal |
| `R2` | Pembayaran dikonfirmasi | Kartu e-Money terbaca |
| `R3` | Pengisian dimulai | "Mulai Pengisian" di Hubungkan Konektor |

### Arti `status`

`status` berarti konektornya **bersedia** (true) atau tidak (false).

Yang perlu diperhatikan: nilainya hanya bermakna pada **R0**. Di situ
false berarti konektornya sudah diambil orang lain, dan alur harus
berhenti — pengguna tidak boleh menghabiskan waktu memilih nominal dan
membayar untuk konektor yang tidak akan ia dapatkan.

Pada R1–R3 nilainya **selalu false**, dan itu wajar: bookingnya sudah
dipegang pengguna ini, jadi konektornya memang tidak lagi bersedia.
Permintaannya tidak membawa identitas pemesan, sehingga backend tidak
bisa membedakan "diambil Anda" dari "diambil orang lain". Karena itu
R1–R3 diperlakukan sebagai laporan kemajuan: kegagalannya dicatat ke log
dan alurnya jalan terus.

### Yang diamati saat pengujian

- Urutannya **tidak dipaksakan**. Konektor yang belum pernah dibooking
  menerima `R2` langsung dengan `status: true`; panggilan pertama yang
  menang, apa pun kodenya.
- Booking **tidak ikut mengubah** `connectorStatus` pada
  `POST /status-konektor` — sesudah R0 nilainya tetap `1`.
- Kode tahap di luar R0–R3, dan konektor yang tidak dikenal, dibalas
  404 dengan `responseCode` `04`.
- **Belum ada cara melepas booking.** Sesudah R3 pun konektor tetap
  terkunci, dan `R0` berikutnya dibalas `status: false`. Lihat catatan
  di bawah.

## `POST /cancelled-connector`

Melepas booking sehingga konektornya bisa diambil orang lain lagi.

```json
{ "chargeBoxId": "CB-SMR-01", "connectorId": "1", "connectorStatus": "R0" }
```

```json
{
  "responseCode": "00",
  "responseMessage": "Success",
  "data": {
    "chargeBoxId": "CB-SMR-01",
    "chargeBoxName": "Kempower Satellite 200 kW",
    "connectorName": "Gun 1",
    "connectorId": "1",
    "statusMessage": "Connector Cancelled"
  }
}
```

Tidak ada field `status`: pembatalan selalu berhasil selama konektornya
dikenal.

Yang diamati saat pengujian:

- Melepas booking **dari tahap mana pun**. Booking yang sudah sampai R3
  pun terlepas, dan `R0` sesudahnya kembali dibalas `status: true`.
- **Idempoten**: membatalkan konektor yang memang tidak dibooking tetap
  dibalas sukses.
- `connectorStatus` **wajib ada** — tanpa itu dibalas `responseCode`
  `07`, "Missing Field: connectorStatus" — tetapi nilainya tidak
  menentukan apa pun. Aplikasi mengirim tahap terakhir yang sempat
  dilaporkan.
- Konektor yang tidak dikenal dibalas 404.

### Kapan dipanggil

Saat pengguna kembali ke halaman Pilih Charge Box sementara masih
memegang booking — entah lewat "Kembali", tombol Home, atau tombol
kembali perangkat. Satu tempat, `didPopNext()` di `ChargeBoxPage`,
menangkap semua jalan keluar itu sekaligus.

Booking **dilupakan tanpa dibatalkan** begitu `POST /start` berhasil:
sejak saat itu konektornya sedang dipakai, bukan sekadar dipesan, jadi
pulangnya pengguna ke daftar tidak boleh melepasnya.

Kegagalan pembatalan hanya dicatat ke log. Pengguna sudah pergi dari
alur itu; memunculkan error atas sesuatu yang tidak ia minta hanya
membingungkan.

## `POST /transaction/charging/start`

Meminta charger memulai pengisian.

```json
{ "orderId": "F3YYZCWLRC4FPR1YDZ7F1A30ID" }
```

Charge box, konektor, dan kWh-nya sudah melekat pada order, jadi cukup
`orderId`. Tanpa itu dibalas `07`, "Missing Field: orderId".

Gagal dengan `31` bila charger tidak terhubung, `32` bila charger
menolak, atau `06` bila ordernya belum siap dimulai.

## `POST /transaction/charging/stop`

Menghentikan pengisian.

```json
{ "orderId": "F3YYZCWLRC4FPR1YDZ7F1A30ID" }
```

Dibalas `06` "Invalid Status Transition" bila ordernya memang sedang
tidak mengisi — terbukti saat pengujian.

## `POST /transaction/charging/ongoing-kwh`

Kemajuan pengisian. Di-polling tiap detik oleh halaman Sedang Mengisi.

```json
{ "orderId": "F3YYZCWLRC4FPR1YDZ7F1A30ID" }
```

```json
{
  "responseCode": "00", "responseMessage": "Success",
  "data": {
    "orderId": "F3YYZCWLRC4FPR1YDZ7F1A30ID",
    "chargeBoxId": "CB-SMR-01",
    "chargeBoxName": "Kempower Satellite 200 kW",
    "connectorName": "Gun 2",
    "orderKwh": 10, "charged": 0, "remaining": 10,
    "status": 2, "lastSoc": null, "firstSoc": null,
    "power": 0, "chargeDurationS": 0, "chargeDurationM": 0,
    "estRemainingTime": 0, "powerActiveImport": 0,
    "estimatedCharged": 0
  }
}
```

Dua hal yang berbeda dari `GET /progress` yang lama:

- **`charged` sudah dalam kWh**, bukan Wh. Angkanya dipakai apa adanya,
  tidak dibagi seribu.
- **`status` memakai kosakata angka yang sama dengan konektor** — lihat
  tabel di `POST /list-chargerbox`. Order yang sudah dibayar tetapi
  belum mulai membalas `2`; `3` berarti sedang mengisi dan `4` berarti
  selesai. Halaman status berpindah ke rincian akhir saat melihat `4`.

`firstSoc` dan `lastSoc` adalah daya baterai kendaraan dalam persen,
dan bisa null bila charger tidak melaporkannya.

### Sesi tanpa order belum bisa dipantau

Ketiga endpoint ini berkunci `orderId`. Sesi yang dilanjutkan dari
daftar charge box — konektor berstatus 2, 3, atau 4 milik orang lain —
tidak membawa orderId, jadi kemajuannya tidak bisa ditanyakan dan
pengisiannya tidak bisa dihentikan lewat aplikasi. Halaman status jatuh
ke simulasi lokal untuk sesi seperti itu.

Melanjutkan sesi orang lain baru benar-benar bisa jalan bila ada cara
memulihkan `orderId` dari sebuah konektor.

## Kode `responseCode`

Daftar lengkap dari definisi backend, disalin ke
`lib/services/response_code.dart`. Terbaca lewat
`ApiException.responseCode`.

| Kode | HTTP | Arti |
|---|---|---|
| `00` | 200 | Success |
| `04` | 404 | Not Found |
| `05` | 400 | Invalid field format |
| `06` | 400 | Invalid Status Transition |
| `07` | 400 | Missing Field |
| `11` | 401 | Invalid Client ID |
| `12` | 401 | Invalid Timestamp |
| `13` | 401 | Invalid Signature |
| `14` | 401 | Unauthorized |
| `15` | 400 | Bad Request Data |
| `16` | 409 | Processing Another Request |
| `21` | 404 | Transaction Not Found |
| `22` | 410 | Transaction Expired |
| `23` | 409 | Transaction already paid |
| `24` | 422 | Transaction failed |
| `25` | 422 | Amount mismatch |
| `31` | 503 | Charging station is not connected |
| `32` | 409 | The charging station rejected the command |
| `33` | 504 | The charging station did not answer in time |
| `34` | 409 | There is no charging session running |
| `35` | 400 | More than one session running; sebutkan konektornya |
| `96` | 502 | Network Error |
| `98` | 503 | Link Down |
| `99` | 500 | Generic Error |

### Koreksi yang dibawa tabel ini

Sebelum tabelnya diketahui, aplikasi menebak tiga kode dan **ketiganya
salah**:

| Dipakai sebagai | Arti sebenarnya | Yang benar |
|---|---|---|
| `12` charger tidak terhubung | Invalid Timestamp | `31` |
| `13` perintah ditolak charger | Invalid Signature | `32` |
| `15` tidak ada sesi berjalan | Bad Request Data | `34` |

Akibatnya tanda tangan yang ditolak — dikonfirmasi lewat pengujian:
`13` "Invalid Signature" — muncul di layar sebagai "Charger menolak
perintah. Pastikan konektor sudah terpasang dengan benar", yang akan
mengirim petugas mengejar hal yang sama sekali salah.

### Cara kode diterjemahkan

Tiap halaman punya penerjemahnya sendiri untuk kode yang relevan dengan
langkah di situ — `startErrorMessage`, `billingErrorMessage`,
`orderErrorMessage`. Yang tidak ditangani jatuh ke
`generalErrorMessage`, yang membedakan dua kelompok:

- **`11`–`14`** berarti aplikasi ini yang ditolak, bukan permintaannya:
  client id, jam perangkat, atau kunci penanda tangan salah. Pesannya
  menunjuk ke konfigurasi kredensial dan menyertakan kodenya, supaya
  petugas tahu ini bukan masalah charger.
- **`96`, `98`, `99`** gangguan sementara di sisi server; pengguna
  diarahkan mencoba lagi.

Sisanya memakai `responseMessage` dari backend apa adanya.

## Penanganan error umum

`ApiException.from()` memetakan kegagalan Dio menjadi `ApiErrorType`
beserta pesan Indonesia:

| `ApiErrorType` | Penyebab |
|---|---|
| `network` | Tidak ada koneksi, DNS gagal, host tidak terjangkau, sertifikat ditolak |
| `timeout` | Melewati `connectTimeout` / `receiveTimeout` / `sendTimeout` |
| `unauthorized` | 401, 403 |
| `notFound` | 404 |
| `badRequest` | 4xx lainnya |
| `server` | 5xx |
| `cancelled` | Permintaan dibatalkan lewat `CancelToken` |
| `unknown` | Sisanya, termasuk body kosong padahal isi diharapkan |

Pesan dari backend didahulukan bila ada, dicari berurutan pada
`responseMessage`, `message`, `error`, lalu `msg`.

## Log

Saat debug, `ApiLogger` mencetak satu baris per panggilan:

```
[API] → POST /start {"chargePointId":"SIM-456","connectorId":1}
[API] ← 200 POST /start (312ms) code=00 Success
[API] ✗ 503 POST /start (118ms) code=12 Charging station SIM-456 is not connected
```

Body dipotong di 400 karakter supaya response `/list` yang panjang tidak
membanjiri konsol. Log otomatis mati di build release; bisa dimatikan
lebih awal lewat `--dart-define=SPKLU_API_LOG=false`.
