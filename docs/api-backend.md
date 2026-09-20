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

## `GET /progress`

Kemajuan sesi pada satu konektor.

```
GET /progress?chargePointId=SIM-456&connectorId=2
```

Kedua parameter **wajib** dikirim aplikasi. Backend sebenarnya menerima
permintaan tanpa `connectorId` dan mengembalikan konektor aktif mana
pun, juga mengabaikan salah ejaan seperti `connecterId` tanpa error.
Dua-duanya gagal secara senyap, jadi `fetchProgress()` memaksa
pemanggil menyebut konektornya.

Isi `data`:

```json
{
  "chargePointId": "SIM-456",
  "connectorId": 2,
  "transactionId": 1789648926,
  "idTag": "REMOTE",
  "state": "charging",
  "connectorStatus": "Charging",
  "percent": 20.1,
  "energyWh": 24,
  "powerW": 12330,
  "durationSeconds": 6,
  "stoppedAt": null,
  "updatedAt": "2026-09-17T20:13:51.943093729+07:00"
}
```

Setelah sesi berhenti, `powerW` menjadi null dan muncul `stopReason`:

```json
{
  "state": "finished",
  "connectorStatus": "Preparing",
  "percent": 55.5,
  "energyWh": 207,
  "powerW": null,
  "durationSeconds": 59,
  "stopReason": "Remote",
  "stoppedAt": "2026-09-17T20:58:35.135618667+07:00"
}
```

`data` yang tidak ada mengembalikan null, bukan error — itu terjadi bila
belum pernah ada sesi pada konektor tersebut.

Tentang energi: backend mengirim `energyWh` dan kadang `energyKwh`
sekaligus. `energyKwh` dipakai apa adanya bila ada; kalau tidak,
dihitung dari `energyWh`.

## `POST /start`

Meminta charger memulai sesi.

```json
{ "chargePointId": "SIM-456", "connectorId": 1, "targetKwh": 19.5 }
```

`targetKwh` adalah kWh yang dibeli pengguna — batas energi yang boleh
disalurkan sesi ini. Field-nya dihilangkan dari body bila tidak
diketahui, misalnya pada sesi yang dilanjutkan tanpa data pembelian.

Hanya `chargePointId` yang wajib; tanpa itu backend membalas kode `07`.

Response:

```json
{ "chargePointId": "SIM-456", "connectorId": 1, "state": "starting" }
```

`state` bernilai `"starting"`, bukan `"charging"`. Controller baru
meneruskan perintah ke charger; konfirmasi bahwa pengisian berjalan
datang dari `session` pada `/list` atau dari `/progress`.

## `POST /stop`

Menghentikan sesi yang sedang berjalan.

```json
{ "chargePointId": "SIM-456", "connectorId": 1 }
```

`connectorId` disertakan agar perintahnya mengenai konektor yang tepat
pada charger dengan lebih dari satu konektor.

Response menyertakan `transactionId` sesi yang dihentikan:

```json
{ "chargePointId": "SIM-456", "connectorId": 1,
  "transactionId": 1789648927, "state": "stopping" }
```

Sama seperti `/start`, `"stopping"` berarti perintah diteruskan — bukan
bahwa daya sudah berhenti mengalir. Karena itu energi akhir dibaca ulang
lewat `/progress`.

## Kode error bisnis

Didefinisikan di `ChargeErrorCode`. Terbaca lewat
`ApiException.responseCode`.

| Kode | HTTP | Arti | Ditangani di |
|---|---|---|---|
| `04` | 404 | Endpoint tidak ditemukan | Pesan bawaan `ApiException` |
| `07` | 400 | `Missing Field: chargePointId` | Pesan "Data charge box tidak lengkap" |
| `12` | 503 | Charger tidak terhubung ke controller | Pesan menyarankan pilih charge box lain |
| `13` | 409 | Charger menolak perintah | Pesan menyarankan periksa konektor |
| `15` | 409 | Tidak ada sesi berjalan pada charger itu | Pesan asli backend |

Penerjemahannya ada di `startErrorMessage()` di
`lib/pages/connect_connector_page.dart`. Kode yang tidak dikenal memakai
pesan asli dari backend.

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
