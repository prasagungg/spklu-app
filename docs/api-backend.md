# API edge controller

Semua endpoint relatif terhadap base URL yang diatur di halaman
Konfigurasi Server. Base URL sudah memuat prefiks path-nya — misalnya
`https://contoh.id/api` membuat `/list` menjadi
`https://contoh.id/api/list`.

Implementasinya ada di `lib/data/charge_point_repository.dart`.

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

## `GET /list`

Daftar charge point yang sedang terhubung ke controller.

```json
{
  "responseCode": "00",
  "responseMessage": "Success",
  "data": {
    "chargePoints": [
      {
        "id": "SIM-456",
        "vendor": "Icon Digital",
        "model": "OCPP Simulator",
        "serialNumber": "…",
        "firmwareVersion": "…",
        "connectedAt": "2026-09-17T20:00:00+07:00",
        "lastHeartbeat": "2026-09-17T20:13:50+07:00",
        "connectors": [
          { "id": 1, "status": "Available", "errorCode": "NoError" },
          { "id": 2, "status": "Charging", "errorCode": "NoError",
            "session": { } }
        ]
      }
    ]
  }
}
```

Catatan:

- **Nomor charge box tidak dikirim backend.** Urutan tampil (01, 02, …)
  diambil dari posisi di daftar.
- **Nama tampilan dan tipe konektor juga tidak ada.** Model jatuh ke
  `id` charge point dan "Konektor 1" untuk konektor.
- `chargePoints` kosong adalah kondisi normal — tidak ada charger yang
  terhubung — dan menghasilkan daftar kosong, bukan error.
- `session` hanya muncul pada konektor yang sedang punya sesi.

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

Isi `data` sama bentuknya dengan `session` pada `/list`:

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
