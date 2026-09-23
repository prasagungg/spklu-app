# Dokumentasi kossotrik

Dokumen di folder ini menjelaskan bagaimana aplikasi disusun dan
mengapa, bukan mengulang apa yang sudah jelas dari kode. Kode sendiri
sudah banyak berkomentar; yang di sini adalah gambaran yang tidak muat
dalam satu berkas.

| Dokumen | Baca bila ingin tahu |
|---|---|
| [arsitektur.md](arsitektur.md) | Lapisan aplikasi, aliran data, dan jebakan yang sudah pernah ditemui |
| [alur-layar.md](alur-layar.md) | Layar apa muncul setelah apa, dan apa yang menentukannya |
| [api-backend.md](api-backend.md) | Endpoint edge controller, bentuk response, kode error |
| [konfigurasi.md](konfigurasi.md) | Cara mengatur alamat server, `--dart-define`, HTTP dan TLS |
| [pengujian.md](pengujian.md) | Apa yang sudah diuji dan cara menambah test |

## Kosakata

| Istilah | Arti di sini |
|---|---|
| **Edge controller** | Server yang dipanggil aplikasi. Ia yang berbicara OCPP ke charger. |
| **Charge point / charge box** | Satu unit charger, punya id seperti `SIM-456`. |
| **Konektor** | Satu colokan pada charge box. Satu charge box bisa punya beberapa. |
| **Pemesanan** | Kunci atas satu konektor, punya `reservationId`. Dibuat saat nozzle dipilih, dilepas saat alurnya ditinggalkan. |
| **Order** | Pembelian sejumlah kWh pada pemesanan itu, punya `orderId`. Semua perintah pengisian berkunci order. |
| **Kode sesi** | Angka pendek dari pemesanan, dipegang pengguna untuk kembali ke sesinya dan mengakhirinya. |
| **OCPP** | Protokol antara controller dan charger. Aplikasi tidak bicara OCPP langsung, tetapi status konektornya memakai istilah OCPP 1.6. |
