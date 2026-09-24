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
    "alamatSpklu": "Jl. Sisingamangaraja No. 1, Kebayoran Baru, Jakarta Selatan",
    "chargeBoxs": [
      {
        "chargeboxId": "CB-SMR-01",
        "merek": "Kempower",
        "daya": "200 kW",
        "isActive": true,
        "namaChargebox": "Kempower Satellite 200 kW",
        "connectorTotal": 2,
        "connectors": [
          {
            "connectorId": "1",
            "chargeboxId": "CB-SMR-01",
            "status": 1,
            "namaKonektor": "Gun 1",
            "typeConnector": "CCS2",
            "connectorTypeCurrent": "DC",
            "estimatimationAvailable": null
          }
        ]
      }
    ]
  }
}
```

Diurai menjadi `Spklu` → `ChargeBox` → `Connector`.

Catatan:

- **Ejaan berubah antar versi backend.** Yang berlaku sekarang:
  `chargeBoxs` (bukan `chargeBoxes`), `chargeboxId`, `namaChargebox`,
  dan `estimatimationAvailable` — dua yang terakhir dengan b kecil dan
  salah ketik. Penguraiannya menerima ejaan lama maupun baru supaya
  versi backend yang berbeda tidak memecahkan aplikasi.
- **`daya` ada di tiap charge box**, bukan lagi `dayaSpklu` di tingkat
  lokasi. Itulah sumber "200 kW" pada keterangan konektor
  "CCS2 - 200 kW DC".
- **`isActive`** menggantikan `status` di tingkat charge box, dan
  inilah yang menentukan kartunya bisa ditekan atau tidak.
- `connectorTotal` dipakai untuk label "2 Konektor" bila daftar
  konektornya ternyata tidak lengkap.
- **Angka `status` pada konektor** menyebut keadaan konektor itu:

  | `status` | Arti | `ConnectorStatus` | Bisa ditekan |
  |---|---|---|---|
  | `0` | Sudah dipesan, belum dibeli | `reserved` | ya |
  | `1` | Tersedia | `available` | ya |
  | `2` | Sedang digunakan | `inUse` | ya |
  | `3` | Menunggu pembayaran | `awaitingPayment` | ya |
  | `4` | Tidak tersedia | `unavailable` | tidak |
  | lainnya | Tidak dikenal | `unavailable` | tidak |

  Seluruh aplikasi menafsirkannya lewat
  `lib/models/connector_status_code.dart` saja, jadi perubahan kosakata
  cukup diikuti di satu tempat.

  **Kosakata ini berbeda dari `statusProcess`.** Angka yang sama berarti
  hal yang berbeda: `3` di sini "menunggu pembayaran", sedangkan pada
  `manage-sessioncode` dan `ongoing-kwh` `3` berarti "sedang mengisi".
  Keduanya sengaja dipisah — `lib/models/backend_status.dart` memegang
  kosakata tahap transaksi.
- **Angka `status` di tingkat charge box tidak dipakai.** Keempat angka
  di atas menggambarkan keadaan sesi pada satu konektor; untuk charge
  box yang menentukan adalah `isActive`.
- **`connectorId` dikirim sebagai teks** (`"1"`). Diurai sekali di
  `Connector.fromJson`, dan dikirim balik sebagai teks juga.
- **Tidak ada objek `session`.** Endpoint ini tidak membawa kemajuan
  sesi yang sedang berjalan; angka kWh selalu datang dari
  `ongoing-kwh`.
- **Tidak satu pun angka itu menjawab "kabelnya sudah tercolok?"** —
  yang melaporkan keadaan fisik konektornya adalah
  `POST /check-status-connector` dengan status OCPP-nya.
- **Nomor charge box tidak dikirim backend.** Urutan tampil (01, 02, …)
  diambil dari posisi di daftar.
- `chargeBoxes` kosong adalah kondisi normal dan menghasilkan daftar
  kosong, bukan error.
- Keterangan lokasi — `namaSpklu`, `alamatSpklu`, `dayaSpklu` — diurai
  ke `Spklu` tetapi belum ditampilkan di layar mana pun.

## `POST /detail-chargerbox`

Isi satu charge box beserta status konektornya saat ini.

```json
{ "chargeboxId": "CB-SMR-01" }
```

```json
{
  "responseCode": "00", "responseMessage": "Success",
  "data": {
    "chargeboxId": "CB-SMR-01", "merek": "Kempower",
    "isActive": true, "namaChargebox": "Kempower Satellite 200 kW",
    "connectorTotal": 2,
    "connectors": [
      { "connectorId": "1", "chargeboxId": "CB-SMR-01", "status": 1,
        "namaKonektor": "Gun 1", "typeConnector": "CCS2",
        "connectorTypeCurrent": "DC", "estimatimationAvailable": null }
    ]
  }
}
```

**Kapan dipanggil.** Sekali, ketika pengguna menekan sebuah charge box
dan bottom sheet daftar konektor terbuka. Status konektor tidak terlihat
dari daftar, dan satu panggilan di sini menggantikan satu panggilan per
konektor — endpoint lama `POST /status-konektor` sudah dihapus backend
(dibalas `04`).

Selama jawabannya belum datang, konektor menampilkan chip "Memeriksa…"
dan belum bisa ditekan: tujuannya ditentukan status, jadi menekannya
lebih awal bisa salah arah.

**Jawabannya tidak membawa `daya`** — hanya daftar yang punya. Aplikasi
menyalin daya dari charge box di daftar untuk keterangan
"CCS2 - 200 kW DC".

Detail yang gagal diambil, atau yang datang tanpa satu pun konektor,
memakai data dari daftar apa adanya. Mengosongkan sheet karena satu
jawaban aneh jauh lebih merugikan daripada menampilkan data yang sedikit
basi.
## `POST /check-status-connector`

Status OCPP satu konektor — inilah yang tahu kabelnya sudah tercolok
atau belum.

```json
{ "chargeBoxId": "CB-SMR-01", "connectorId": "1" }
```

```json
{
  "responseCode": "00", "responseMessage": "Success",
  "data": {
    "chargeBoxId": "CB-SMR-01",
    "chargeboxName": "Kempower Satellite 200 kW",
    "connectorName": "Gun 1",
    "connectorId": "1",
    "connectorStatus": "Available"
  }
}
```

### Kosakata `connectorStatus`

Istilah OCPP 1.6 apa adanya, disalin ke `lib/models/ocpp_status.dart`:

| Status | Arti | Dianggap tercolok |
|---|---|---|
| `Available` | Bebas, kabel belum terpasang | tidak |
| `Preparing` | **Kabel sudah terpasang**, siap dimulai | ya |
| `Charging` | Sedang mengisi | ya |
| `SuspendedEVSE` | Tertahan dari sisi charger | ya |
| `SuspendedEV` | Tertahan dari sisi kendaraan | ya |
| `Finishing` | Sesi selesai, kabel biasanya masih terpasang | ya |
| `Reserved` | Dipesan untuk orang lain | tidak |
| `Unavailable` | Sengaja dimatikan operator | tidak |
| `Faulted` | Charger melaporkan gangguan | tidak |

Status yang **tidak dikenal tidak dianggap tercolok**: menebaknya akan
mengirim perintah start yang pasti ditolak charger.

### Dipakai halaman Hubungkan Konektor

Di-polling tiap detik sampai statusnya `Preparing`. Selama belum,
tombol "Mulai Pengisian" tetap mati. Inilah deteksi kabel tercolok yang
sungguhan — sebelumnya halaman itu menebak dari `statusProcess` milik
`manage-sessioncode`, yang menggambarkan tahap transaksi, bukan keadaan
fisik konektornya.

`Faulted` dan `Unavailable` disebut apa adanya di layar — charger
seperti itu tidak akan pernah melaporkan `Preparing`, jadi menyuruh
pengguna menunggu hanya membuang waktunya.

Kedua field permintaannya wajib; tanpa `connectorId` dibalas
`responseCode` `07` "Missing Field: connectorId". Terbukti saat
pengujian: ACMP_UAT konektor 2 dan 4 membalas `Available`, ACMAX_UAT
konektor 1 membalas `Preparing`.

## `POST /booked-connector`

Memesan konektor atas nama pengguna yang sedang memakai unit ini.
Dipanggil begitu sebuah konektor ditekan di bottom sheet, sebelum alur
pembelian dimulai.

```json
{ "chargeBoxId": "CB-SMR-01", "connectorId": "1" }
```

```json
{
  "responseCode": "00",
  "responseMessage": "Success",
  "data": {
    "chargeBoxId": "CB-SMR-01",
    "chargeboxName": "Kempower Satellite 200 kW",
    "connectorName": "Gun 1",
    "connectorId": "1",
    "connectorStatus": "R0",
    "sessionExpired": "2026-09-23T09:56:04Z",
    "reservationId": "U33tiFAl0Yj5TkCQyoUmU",
    "sessionCode": "05",
    "status": true
  }
}
```

Tiga field jawabannya yang menggerakkan sisa alur:

| Field | Dipakai sebagai |
|---|---|
| `reservationId` | Identitas pemesanan; wajib dibawa `push-order` dan `cancelled-connector` |
| `sessionCode` | Kode yang ditunjukkan di halaman Kode Sesi |
| `sessionExpired` | Batas waktu pemesanan, jadi hitung mundur di halaman itu |

### Tahapnya ditetapkan backend

`connectorStatus` — "R0" saat dipesan, "R1" begitu ordernya dibuat —
**tidak pernah dikirim aplikasi**. Dulu aplikasi memanggil endpoint ini
empat kali untuk menaikkan tahap R0→R1→R2→R3; sekarang endpoint ini
dipanggil **sekali**, dan memanggilnya lagi berarti membuat pemesanan
baru, bukan menaikkan tahap.

### Arti `status`

`status` berarti konektornya **bersedia** (true) atau tidak (false).
False berarti sudah diambil orang lain: alurnya berhenti di situ dan
daftar konektor dimuat ulang, supaya pengguna tidak menghabiskan waktu
memilih nominal dan membayar untuk konektor yang tidak akan ia dapatkan.

### Kode sesi sejak memilih nozzle

Kode sesi dulu datang dari `push-order`, jadi pengguna baru melihatnya
setelah membayar. Sekarang pemesanan yang memberikannya, dan halaman
Kode Sesi muncul tepat setelah endpoint ini berhasil — sebelum nominal
dipilih.

Konektor berstatus `0` ("dipesan") melewati Verifikasi Sesi lebih dulu;
`reservationId` dan `sessionCode` miliknya datang dari
`manage-sessioncode`, bukan dari pemesanan baru.

## `POST /cancelled-connector`

Melepas pemesanan sehingga konektornya bisa diambil orang lain lagi.

```json
{ "chargeBoxId": "CB-SMR-01", "connectorId": "1",
  "reservationId": "U33tiFAl0Yj5TkCQyoUmU" }
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

- `reservationId` **wajib ada** — tanpa itu dibalas `responseCode` `07`,
  "Missing Field". Yang dilepas adalah pemesanan itu, bukan konektornya
  secara umum.
- Melepas pemesanan **dari tahap mana pun**, termasuk yang sudah punya
  order.
- Konektor yang tidak dikenal dibalas 404.

### Kapan dipanggil

Saat pengguna kembali ke halaman Pilih Charge Box sementara masih
memegang pemesanan — entah lewat "Kembali", "Batalkan Transaksi" di
halaman Kode Sesi, tombol Home, atau tombol kembali perangkat. Satu
tempat, `didPopNext()` di `ChargeBoxPage`, menangkap semua jalan keluar
itu sekaligus.

Mundur dari Pilih Nominal ke Kode Sesi **tidak** membatalkan apa pun:
pemesanannya masih dipegang pengguna yang sama.

Pemesanan **dilupakan tanpa dibatalkan** begitu
`POST /transaction/charging/start` berhasil: sejak saat itu konektornya
sedang dipakai, bukan sekadar dipesan, jadi pulangnya pengguna ke daftar
tidak boleh melepasnya.

Kegagalan pembatalan hanya dicatat ke log. Pengguna sudah pergi dari
alur itu; memunculkan error atas sesuatu yang tidak ia minta hanya
membingungkan.

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
hanya membingungkan. Yang ditampilkan adalah tarif per kWh, PBJT-TL,
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

Membuat order untuk kWh yang dipilih pada pemesanan yang sudah ada.
Dipanggil saat "Lanjutkan" ditekan di halaman Pilih Nominal.

```json
{ "chargeboxId": "CB-SMR-01", "connectorId": "1",
  "reservationId": "U33tiFAl0Yj5TkCQyoUmU", "kwh": 10 }
```

```json
{
  "responseCode": "00",
  "responseMessage": "Success",
  "data": {
    "orderId": "VB4LY6CAI8Z8C25QHMY4MIRJUC",
    "chargeboxId": "ACMP_UAT", "chargeboxName": "ACMP UAT",
    "connectorName": "DCCT 200 kW", "connectorId": "3",
    "partnerReference": "81067", "sessionCode": "65",
    "reservationId": "GiutWg7co_CaODPntGi3c",
    "connectorStatus": "R1",
    "createdDate": "2026-09-24T02:38:44Z",
    "sessionExpired": "2026-09-24T02:43:44Z",
    "kwh": 10, "rpPerKwh": 0, "rpPpj": 0, "rpPpn": 0,
    "rpTotal": 2000, "rpMaterai": 0, "rpKwh": 0,
    "idleFee": 0, "serviceFee": 2000
  }
}
```

Jawabannya **mengeja `chargeboxId` dan `chargeboxName` dengan b kecil**,
dan menamai batas waktunya `sessionExpired` — sebelumnya
`sessionExpiredTime`. `Order.fromJson` menerima kedua ejaan itu: yang
salah eja tidak memunculkan error, hanya diam-diam kosong.

Dua hal pada permintaannya yang mudah terlewat:

- **`chargeboxId` dengan b kecil.** Hanya endpoint ini dan
  `detail-chargerbox` yang mengejanya begitu; sisanya `chargeBoxId`.
- **`reservationId` wajib.** Tanpa itu dibalas `07` "Missing Field":
  order selalu melekat pada pemesanan yang dibuat lebih dulu.

Jawabannya memberi dua hal yang sebelumnya **dikarang aplikasi**:

| Field | Dipakai sebagai |
|---|---|
| `orderId` | Identitas order, disimpan di `ChargingSession.orderId` |
| `partnerReference` | "No Reference" pada Detail Transaksi |

`sessionCode` di sini sama dengan yang sudah ditunjukkan halaman Kode
Sesi sejak pemesanan; yang dipakai aplikasi adalah kode dari pemesanan.

Rinciannya juga lebih lengkap daripada `/count-kwh`: ada **`rpKwh`**,
biaya energi sebagai angka tersendiri, jadi baris "Biaya Listrik" muncul
di halaman Konfirmasi tanpa aplikasi perlu menghitungnya. Angkanya
konsisten — 24.660 + 740 = 25.400.

### Yang diamati saat pengujian

- **Hanya satu order tertunda per konektor.** Push kedua dibalas
  `responseCode` `16` "Processing Another Request" (HTTP 409). Order
  yang ditinggalkan mengunci konektornya sampai kedaluwarsa —
  membatalkan pemesanannya tidak melepas ordernya.
- **Batas waktunya hanya lima menit** pada playground: `createdDate`
  02:38:44 dengan `sessionExpired` 02:43:44. Lewat dari itu tagihannya
  **tetap bisa ditanyakan dengan nominal yang sama** — yang hilang
  lebih dulu adalah pemesanannya, yang dibalas `26` "Reservation Not
  Found" saat dibatalkan.
- `orderId` baru setiap order; `partnerReference` tetap pada playground.
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

### Nomor kartu dibaca dari kartunya bila bisa

Kartu yang menjawab perintah EMV — Flazz keluaran baru dan kartu
ISO-DEP lain — nomornya dibaca langsung dari kartu dan itulah yang
dikirim. Kartu MIFARE Classic seperti e-Money, TapCash, dan Brizzi
mengunci nomornya di sektor milik penerbit, dan untuk kartu itu yang
dikirim tetap `Env.cardNumber`
(`--dart-define=SPKLU_CARD_NUMBER=…`). Lihat
[arsitektur.md](arsitektur.md#pembayaran-kartu).

**Nomor asli belum diterima backend.** Tabel penerbitnya baru mengenal
empat prefiks percobaan; BIN sungguhan dibalas `05`. Terbukti saat
pengujian:

| Nomor | Jawaban |
|---|---|
| `0123…` | `21` — prefiksnya lolos, ordernya yang tidak ada |
| `6019 21…` (Flazz) | `05` E-Money Provider Is Not Supported |
| `6032 98…` (e-Money) | `05` |
| `6013 50…` (TapCash) | `05` |

Jadi selama tabel itu belum diisi BIN asli, kartu yang nomornya
berhasil dibaca justru akan ditolak saat menagih.

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
- **Nominal nol berarti tarif konektornya belum diatur.** Bukan soal
  kedaluwarsa: order pada konektor tanpa tarif dibalas `00` dengan
  `amount` dan `totalAmount` `0`, dan `POST /count-kwh` untuk konektor
  itu pun sudah mengembalikan `rpTotal: 0` sejak halaman Pilih Nominal.
  Terbukti di playground: ACMP_UAT konektor 4 dihargai `0`, konektor 2
  dihargai `667` untuk 5 kWh yang sama.
- **`sessionCode` dan `reservationId` ikut dikirim.** Kode sesinya sama
  dengan milik pemesanan; aplikasi tidak menimpanya dengan nilai dari
  sini.

Kegagalan menahan alur: pengguna tidak dibiarkan maju ke "Pembayaran
Berhasil" untuk tagihan yang tidak pernah terverifikasi. Sesi NFC dibuka
lagi supaya kartu bisa ditempelkan ulang.

## `POST /transaction/payment-billing`

Membayar tagihan yang sudah ditanyakan. Dipanggil tepat setelah
inquiry, dalam rangkaian yang sama saat kartu terdeteksi.

```json
{ "orderId": "F3YYZCWLRC4FPR1YDZ7F1A30ID", "amount": 145670,
  "cardNumber": "0123456789012345",
  "bankLog": "1231408098812345678100500",
  "merchantId": "000000000000001", "terminalId": "00000001" }
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

### `amount` nol dibalas "Missing Field: amount"

Nilai `0` dianggap tidak ada, dan balasannya `07` "Missing Field:
amount" — pesan yang menyesatkan, karena fieldnya jelas terkirim.
Penyebab sebenarnya ada jauh sebelumnya: konektor yang tarifnya belum
diatur membuat `count-kwh`, order, dan inquiry sama-sama bernilai nol.

Aplikasi karena itu berhenti **dua kali**. Halaman Pilih Nominal
mematikan "Lanjutkan" untuk total nol dan mengatakan alasannya, dan
`CardPaymentPage` tetap memeriksa `totalAmount` sekali lagi sebelum
menagih — sisi pengaman kalau tarifnya berubah di tengah alur.

### `merchantId` dan `terminalId`

Menyebut mesin mana yang menagih. Keduanya **masih nilai sementara** —
mesin kartunya belum ada, jadi belum ada sumber yang sebenarnya, sama
seperti `cardNumber` dan `bankLog`. Diganti lewat
`--dart-define=SPKLU_MERCHANT_ID=…` dan `SPKLU_TERMINAL_ID=…` begitu
nomor aslinya diketahui.

Backend menerimanya tanpa keberatan: permintaan dengan kedua field itu
dan order karangan dibalas `21` "Transaction Not Found" — gagal karena
ordernya, bukan karena bentuk bodynya.

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

## `GET /transaction/history-transaction`

Transaksi yang pernah tercatat, terbaru lebih dulu. Dipanggil saat
tombol riwayat di header halaman Pilih Charge Box ditekan.

**Tanpa body dan tanpa query.** Seperti GET lainnya, tanda tangannya
dihitung dengan body kosong:

```sh
curl --location 'localhost:8080/transaction/history-transaction' \
  --header 'client-id: edge' \
  --header 'timestamp: 2026-09-24T05:31:00Z' \
  --header 'signature: dd2ca39f…'
```

```json
{
  "responseCode": "00", "responseMessage": "Success",
  "data": { "list": [
    { "pspId": "EM-BNI", "cardNumber": "0123456789012345",
      "orderId": "8XWS0G9RULEYBLHS48ULF6OFH7",
      "totalAmount": 12700, "createdDate": "2026-09-23T09:28:44Z" }
  ] }
}
```

### Dulu POST per konektor

Endpoint ini sebelumnya sebuah POST yang melayani **satu konektor**
sekali panggil dan mewajibkan `chargeBoxId` serta `connectorId` —
tanpa salah satunya dibalas `07` "Missing Field". Tidak ada endpoint
yang mengembalikan riwayat satu lokasi sekaligus, jadi halaman riwayat
menanyakan tiap konektor yang sedang ditampilkan daftar, berbarengan,
lalu menggabungkan jawabannya.

Sekarang satu panggilan mengembalikan semuanya, dan penggabungan itu
hilang: yang tersisa di halaman riwayat hanya mengurutkan terbaru
lebih dulu.

### Asal tiap entri

Karena permintaannya tidak lagi menyebut charge box dan konektor,
**asal tiap entri harus datang dari entrinya sendiri**.
`TransactionHistoryEntry` membaca `chargeboxId`, `chargeboxName`,
`connectorId`, dan `connectorName` — kedua ejaan b besar/kecil
diterima, dan `connectorId` diterima sebagai angka maupun teks, seperti
di `detail-history-transaction`.

Nomor urut ("01", "02") dan daya charge box tidak ada di jawaban ini —
keduanya hanya dikirim `POST /list-chargerbox`. Halaman riwayat karena
itu mencocokkan `chargeboxId` entri ke daftar charge box yang sedang
ditampilkan, dan memakai nama dari entrinya sendiri bila tidak
ditemukan — riwayat charge box yang sudah dilepas dari lokasi tetap
terlihat, hanya tanpa nomor urut.

`pspId` dan `cardNumber` bisa kosong: order yang tidak pernah sampai
dibayar tetap tercatat. Nomor kartunya **tidak pernah ditampilkan
utuh** — `TransactionHistoryEntry.maskedCard` menyisakan empat digit
pertama dan terakhir, "6012 **** **** 7890".

## `POST /transaction/detail-history-transaction`

Rincian satu transaksi di riwayat.

```json
{ "orderId": "U33UHB2TQQ4LV274UCXTEX6IVS", "sessionCode": "30" }
```

```json
{
  "response_code": "00",
  "response_message": "Success",
  "data": {
    "chargeboxId": "ACMP_UAT", "chargeboxName": "ACMP UAT",
    "connectorId": 2, "connectorName": "AC 22 kW",
    "orderId": "U33UHB2TQQ4LV274UCXTEX6IVS",
    "namaSpklu": "SPKLU PLN PUSAT",
    "pspId": "EM-BNI", "cardNumber": "012••••••••••345",
    "status": 0, "tglCatat": "2026-09-24T04:08:39Z",
    "kwhPesan": 10, "kwhPakai": 0, "sisaKwh": null,
    "rpPesan": 18775, "rpPakai": 0, "rpSisa": null,
    "hargaKwh": 1710, "rpLayanan": 1332.2, "idleFee": 0
  }
}
```

### Amplopnya snake_case — tapi hanya saat berhasil

Satu-satunya endpoint yang membalas `response_code`/`response_message`;
sisanya camelCase. Yang membingungkan, **kegagalannya tetap
camelCase**: kode sesi yang salah dibalas
`{"responseCode":"21","responseMessage":"Transaction Not Found"}`.

`_unwrap` di repository karena itu menerima kedua ejaan. Kalau tidak,
jawaban sukses endpoint ini akan terbaca sebagai amplop tanpa kode dan
ditolak aplikasi sendiri.

### `sessionCode` wajib

Tanpa itu dibalas `07` "Missing Field: sessionCode", dan kode yang tidak
cocok dibalas `21`. Inilah yang membedakan daftar riwayat dari
rinciannya: daftarnya boleh dilihat siapa saja yang berdiri di depan
unit — isinya hanya waktu, nominal, dan nomor kartu yang disamarkan —
sedangkan rinciannya hanya untuk pemegang kode sesi.

### Yang diamati saat pengujian

- **Nomor kartunya sudah disamarkan backend**: "012••••••••••345",
  dengan titik tengah, bukan bintang. Ditampilkan apa adanya.
- `connectorId` di sini berupa **angka** (`2`), bukan teks seperti di
  endpoint lain.
- Banyak field bernilai null pada transaksi yang tidak sampai selesai —
  `sisaKwh`, `rpSisa`, `chargeDuration`, `rpAdmin`, `rpMaterai`,
  `firstSoc`. Penguraiannya karena itu longgar dan menganggapnya nol.

## `POST /manage-sessioncode`

```json
{ "chargeboxId": "CB-SMR-01", "connectorId": "1", "sessionCode": "29" }
```

Endpoint ini mengeja `chargeboxId` dengan b kecil. Playground menerima
kedua ejaan — terbukti saat pengujian, keduanya dibalas `00` untuk kode
yang sama — tetapi yang dikirim mengikuti spesifikasinya.

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
diperiksa di sini. Kode sesi melekat pada pemesanan, jadi aplikasi tidak
bisa — dan tidak boleh — memutuskannya sendiri. Sebelum endpoint ini
ada, verifikasi membandingkan dengan `SPKLU_SESSION_PIN` yang tetap,
sehingga kode yang ditunjukkan di layar sebenarnya tidak membuka apa-apa.

### Tahap transaksi

`statusProcess` menyebut tahap transaksinya: `0` baru dipesan dan
ordernya belum ada, `1` belum bayar, `2` menunggu konektor dihubungkan,
`3` sedang mengisi, `4` selesai. Terbukti saat pengujian: pemesanan yang
baru dibuat dibalas `statusProcess: 0` dengan `orderId: null`.

**Angkanya bukan kosakata yang sama dengan `status` milik konektor** di
daftar dan detail charge box — lihat tabel di `POST /list-chargerbox`.
Dan bukan pula keadaan fisik konektornya: yang tahu kabel sudah tercolok
atau belum adalah `POST /check-status-connector`.

### Ejaan `chargeBoxId`

Endpoint ini sempat mengeja `chargeboxId` dengan b kecil sebelum
dirapikan. Penguraiannya menerima kedua ejaan, supaya versi backend
yang berbeda tidak memecahkan aplikasi.

### `orderId` dan `reservationId` menutup alurnya

Jawabannya menyertakan `orderId`, sehingga sesi yang dibuka kembali bisa
dipantau dan dihentikan — semua perintah pengisian berkunci order,
sedangkan daftar charge box tidak membawanya. Bila ada,
`reservationId`-nya juga dipakai: sesi berstatus `0` yang belum sampai
membayar melanjutkan pemesanan itu, bukan membuat yang baru.

Terkonfirmasi lewat pengujian: `sessionCode` wajib (`07` tanpa itu),
kode yang tidak cocok dibalas `21`, dan kode yang benar mengembalikan
order beserta `statusProcess`.

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
    "orderId": "U33UHB2TQQ4LV274UCXTEX6IVS",
    "reservationId": "k4sTm8G-CuHinqgkFsZDY", "sessionCode": "30",
    "chargeboxId": "ACMP_UAT", "chargeboxName": "ACMP UAT",
    "connectorName": "AC 22 kW",
    "orderKwh": 10, "charged": 0, "remaining": 10,
    "status": 2, "last_soc": null, "first_soc": null,
    "power": 0, "chargeDurationS": 0, "chargeDurationM": 0,
    "estRemainingTime": 0, "power_active_import": 0,
    "estimated_charged": 0
  }
}
```

### Ejaannya campur

Empat field memakai snake_case — `first_soc`, `last_soc`,
`power_active_import`, `estimated_charged` — sedangkan sisanya
camelCase, dan charge box-nya dieja `chargeboxId` dengan b kecil.
Ejaannya pernah seluruhnya camelCase; `ChargingProgress.fromJson`
sekarang menerima keduanya. Field yang salah eja tidak memunculkan
error, hanya diam-diam bernilai nol — persis gejala "angkanya tidak
nambah-nambah".

`connectorId` sudah tidak dikirim endpoint ini.

Dua hal yang berbeda dari `GET /progress` yang dipakai sebelum backend
ini:

- **`charged` sudah dalam kWh**, bukan Wh. Angkanya dipakai apa adanya,
  tidak dibagi seribu.
- **`status` memakai kosakata angka yang sama dengan konektor** — lihat
  tabel di `POST /list-chargerbox`. Order yang sudah dibayar tetapi
  belum mulai membalas `2`; `3` berarti sedang mengisi dan `4` berarti
  selesai. Halaman status berpindah ke rincian akhir saat melihat `4`.

`firstSoc` dan `lastSoc` adalah daya baterai kendaraan dalam persen,
dan bisa null bila charger tidak melaporkannya.

### `charged` nol bukan berarti salah baca

Order yang sudah dibayar tetapi pengisiannya belum benar-benar jalan
membalas `status: 2` dengan `charged: 0`, dan angkanya memang tidak
bergerak. Terbukti saat pengujian: `POST /transaction/charging/start`
untuk charge box yang tidak terhubung dibalas `31` "Charging station
ACMP_UAT is not connected", sehingga sesinya tidak pernah mulai
menyalurkan energi.

Jadi sebelum menuduh penguraian, periksa `status` pada jawaban yang sama:
`3` berarti benar-benar sedang mengisi.

### Sesi tanpa order belum bisa dipantau

Ketiga endpoint ini berkunci `orderId`. Sesi yang dilanjutkan dari
daftar charge box — konektor berstatus 2, 3, atau 4 milik orang lain —
tidak membawa orderId kecuali `manage-sessioncode` menyebutkannya, jadi
kemajuannya tidak bisa ditanyakan dan pengisiannya tidak bisa
dihentikan lewat aplikasi. Halaman status jatuh ke simulasi lokal untuk
sesi seperti itu.

## `POST /transaction/charging/detail`

Rincian akhir satu order — sumber angka halaman "Pengisian Selesai".

```json
{ "orderId": "U33UHB2TQQ4LV274UCXTEX6IVS" }
```

```json
{
  "responseCode": "00", "responseMessage": "Success",
  "data": {
    "orderId": "U33UHB2TQQ4LV274UCXTEX6IVS",
    "chargeboxId": "ACMP_UAT", "chargeboxName": "ACMP UAT",
    "connectorName": "AC 22 kW", "connectorId": "2",
    "status": 2, "kwhPesan": 10, "kwhPakai": 0, "sisaKwh": 10,
    "rpPesan": 18775, "rpPakai": 0, "rpSisa": 18775,
    "hargaKwh": 1710, "rpPpjPesan": 342, "rpPpjPakai": 0,
    "chargeDuration": "0", "chargeDurationInMinutes": "0",
    "rpAdmin": 0, "rpLayanan": 1332.2, "rpMaterai": null,
    "firstSoc": null, "lastSoc": null, "power": null,
    "idleFee": 0, "serviceFee": 1332.2,
    "namaSpklu": "SPKLU PLN PUSAT",
    "alamatSpklu": "Jl. M.I. Ridwan Rais No.1, Gambir",
    "tglCatat": "2026-09-24T04:08:39Z"
  }
}
```

Empat angka yang dipakai layar penutup:

| Field | Ditampilkan sebagai |
|---|---|
| `kwhPakai` | Energi Tersalur |
| `rpPesan` | Pembayaran Awal |
| `rpPakai` | Total Pemakaian |
| `rpSisa` | Sisa Pembayaran |

Sebelumnya ketiga angka rupiah itu **dihitung aplikasi** dari nominal
yang dibayar dan energi yang tersalur, dengan pembulatan ke bawah per
seribu rupiah. Hitungan seperti itu tidak pernah bisa dijamin sama
dengan pembukuan backend, jadi sekarang angkanya diambil apa adanya.

### Penguraiannya sengaja longgar

`chargeDuration` dan `chargeDurationInMinutes` dikirim sebagai **teks**
("0"), dan `rpMaterai`, `rpDiskon`, `firstSoc`, `lastSoc`, `power`,
`rpJaminan` bisa **null**. Charge box-nya juga dieja dengan b kecil.
Semuanya dibaca lewat satu jalan yang menerima angka maupun teks.

Amplop tanpa `data` terurai menjadi nol semua; halaman penutup
mengabaikannya dan tetap menampilkan angka dari layar pemantauan,
supaya satu jawaban aneh tidak menghapus angka yang sudah benar.

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
[API] → POST /booked-connector {"chargeBoxId":"CB-SMR-01","connectorId":"1"}
[API] ← 200 POST /booked-connector (312ms) code=00 Success
[API] ✗ 503 POST /transaction/charging/start (118ms) code=31 Charging station CB-SMR-01 is not connected
```

Body dipotong di 1.200 karakter supaya response `/list-chargerbox` yang
panjang tidak membanjiri konsol — cukup untuk memuat jawaban
`ongoing-kwh` utuh. Batasnya dulu 400, dan justru memotong tepat di
angka yang paling ingin dilihat saat menelusuri pengisian. Inspektur di
dalam aplikasi menyimpan sampai 20.000 karakter, jadi jawaban panjang
tetap bisa dibaca lengkap di sana. Log otomatis mati di build release;
bisa dimatikan lebih awal lewat `--dart-define=SPKLU_API_LOG=false`.

Seluruhnya juga tercatat di dalam aplikasi — lihat
[Inspector API](arsitektur.md#inspector-api).
