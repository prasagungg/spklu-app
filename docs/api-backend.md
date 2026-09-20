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
