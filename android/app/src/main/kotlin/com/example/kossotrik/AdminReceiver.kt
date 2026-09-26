package com.example.kossotrik

import android.app.admin.DeviceAdminReceiver

/// Komponen yang didaftarkan sebagai device owner.
///
/// Tidak ada kebijakan yang perlu diawasi — kelas ini hanya perlu ada
/// supaya `adb shell dpm set-device-owner` punya sasaran dan supaya
/// [MainActivity] punya ComponentName untuk `setLockTaskPackages`.
class AdminReceiver : DeviceAdminReceiver()
