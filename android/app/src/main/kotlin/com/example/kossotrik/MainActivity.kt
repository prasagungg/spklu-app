package com.example.kossotrik

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.util.Log
import io.flutter.embedding.android.FlutterActivity

/// Mengunci perangkat ke aplikasi ini bila APK-nya dipasang sebagai
/// device owner.
///
/// Penguncian sengaja tidak dinyalakan lewat flag build: keberadaan
/// device owner itu sendiri yang menjadi penandanya. Di perangkat
/// pengembangan yang tidak pernah di-provision, tidak ada yang berubah —
/// tidak ada dialog screen pinning yang mengganggu — sementara tablet
/// SPKLU yang sudah di-provision langsung terkunci tanpa konfigurasi
/// tambahan.
class MainActivity : FlutterActivity() {

    override fun onResume() {
        super.onResume()
        enterKioskIfOwner()
    }

    /// Dipanggil di setiap onResume, bukan sekali di onCreate: keluar
    /// dari lock task bisa terjadi di luar kendali aplikasi (pembaruan
    /// sistem, dialog izin), dan kembali ke layar ini harus mengunci
    /// ulang. Memanggilnya saat sudah terkunci tidak berefek apa-apa.
    private fun enterKioskIfOwner() {
        val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager

        // Bukan device owner berarti perangkat ini bukan kiosk.
        // startLockTask() di sini hanya akan memunculkan dialog screen
        // pinning yang bisa dibatalkan pengguna — tidak berguna, jadi
        // dilewati sama sekali.
        if (!dpm.isDeviceOwnerApp(packageName)) return

        try {
            // Whitelist dipasang aplikasi sendiri; sebagai device owner
            // ia berhak melakukannya, dan tanpa ini startLockTask()
            // menolak dengan IllegalArgumentException.
            dpm.setLockTaskPackages(
                ComponentName(this, AdminReceiver::class.java),
                arrayOf(packageName),
            )
            startLockTask()
        } catch (e: Exception) {
            // Kegagalan mengunci tidak boleh menahan aplikasi:
            // pengisian kendaraan lebih penting daripada kiosknya.
            Log.e("SPKLU", "Lock task gagal dinyalakan", e)
        }
    }
}
