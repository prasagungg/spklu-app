import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/api_config.dart';
import '../services/api_log_store.dart';
import '../theme/app_colors.dart';

/// Inspektur jaringan: daftar panggilan REST yang sudah ditembak
/// aplikasi, beserta isinya.
///
/// Dibuat karena `ApiLogger` hanya mencetak ke konsol — tidak terlihat
/// saat aplikasi dipakai dari APK di perangkat. Halaman ini membuat
/// lalu lintasnya bisa diperiksa langsung di lokasi.
///
/// Dibuka dengan menekan lama logo di header halaman mana pun, dan
/// hanya bila [Env.enableDebugPanel] menyala. Tampilannya sengaja polos
/// dan padat, bukan mengikuti desain Figma: ini alat kerja, bukan layar
/// yang dilihat pengguna.
class ApiLogPage extends StatefulWidget {
  const ApiLogPage({super.key, this.store});

  /// Disuntik di test; produksi memakai riwayat bersama.
  final ApiLogStore? store;

  /// Kolom penyaring, dipakai test.
  static const filterKey = Key('log-api-filter');

  static Future<void> open(BuildContext context, {ApiLogStore? store}) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => ApiLogPage(store: store)));
  }

  @override
  State<ApiLogPage> createState() => _ApiLogPageState();
}

class _ApiLogPageState extends State<ApiLogPage> {
  final TextEditingController _filter = TextEditingController();

  ApiLogStore get _store => widget.store ?? ApiLogStore.instance;

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  /// Menyaring seperti kolom filter di tab Network: cocok bila katanya
  /// ada di method, path, status, atau kode amplop.
  List<ApiLogEntry> _visible(List<ApiLogEntry> entries) {
    final keyword = _filter.text.trim().toLowerCase();
    if (keyword.isEmpty) return entries;

    return [
      for (final entry in entries)
        if ('${entry.title} ${entry.statusLabel} ${entry.responseCode ?? ''}'
            .toLowerCase()
            .contains(keyword))
          entry,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackgroundPlain,
      appBar: AppBar(
        title: const Text('Log API'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.title,
        actions: [
          IconButton(
            tooltip: 'Hapus riwayat',
            onPressed: _store.clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          _BaseUrlBar(),
          _FilterField(controller: _filter, onChanged: (_) => setState(() {})),
          Expanded(
            child: ListenableBuilder(
              listenable: _store,
              builder: (context, _) {
                final entries = _visible(_store.entries);

                if (entries.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        _store.isEmpty
                            ? 'Belum ada panggilan yang tercatat.\n'
                                  'Riwayat terisi begitu aplikasi menembak '
                                  'backend.'
                            : 'Tidak ada yang cocok dengan penyaring.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.description),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) =>
                      _EntryTile(entry: entries[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Alamat backend yang sedang dipakai — pertanyaan pertama saat sesuatu
/// tidak jalan biasanya "ini nembak ke mana?".
class _BaseUrlBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.infoTileBg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        ApiConfig.baseUrl,
        style: const TextStyle(
          fontSize: 12,
          fontFamily: 'monospace',
          color: AppColors.description,
        ),
      ),
    );
  }
}

/// Kolom penyaring, sepadan dengan kotak filter di tab Network.
class _FilterField extends StatelessWidget {
  const _FilterField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: TextField(
        key: ApiLogPage.filterKey,
        controller: controller,
        onChanged: onChanged,
        autocorrect: false,
        style: const TextStyle(fontSize: 13, color: AppColors.title),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Saring: path, method, status, kode…',
          hintStyle: const TextStyle(fontSize: 13, color: AppColors.mutedLabel),
          prefixIcon: const Icon(Icons.search, size: 18),
          prefixIconConstraints: const BoxConstraints(minWidth: 36),
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: AppColors.borderAlt),
          ),
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final ApiLogEntry entry;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: _StatusBadge(entry: entry),
      title: Text(
        entry.title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
          color: AppColors.title,
        ),
      ),
      subtitle: Text(
        '${entry.timeLabel} · ${entry.elapsedLabel}'
        '${entry.responseCode == null ? '' : ' · kode ${entry.responseCode}'}',
        style: const TextStyle(fontSize: 11, color: AppColors.description),
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => _EntryDetailPage(entry: entry)),
      ),
    );
  }
}

/// Kotak status berwarna: hijau berhasil, merah gagal, abu masih jalan.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.entry});

  final ApiLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (entry) {
      _ when entry.isPending => (AppColors.infoTileBg, AppColors.description),
      _ when entry.isFailure => (
        AppColors.unavailableBg,
        AppColors.unavailableFg,
      ),
      _ => (AppColors.availableBg, AppColors.availableFg),
    };

    return Container(
      width: 46,
      padding: const EdgeInsets.symmetric(vertical: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        entry.statusLabel,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }
}

class _EntryDetailPage extends StatelessWidget {
  const _EntryDetailPage({required this.entry});

  final ApiLogEntry entry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.pageBackgroundPlain,
      appBar: AppBar(
        title: Text(entry.title),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.title,
        actions: [
          IconButton(
            tooltip: 'Salin',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: entry.toShareableText()),
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Log disalin')));
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(title: 'Alamat', body: entry.url),
          _Section(
            title: 'Ringkasan',
            body:
                'waktu   : ${entry.timeLabel}\n'
                'durasi  : ${entry.elapsedLabel}\n'
                'status  : ${entry.statusLabel}'
                '${entry.responseCode == null ? '' : '\n'
                          'kode    : ${entry.responseCode} '
                          '${entry.responseMessage ?? ''}'}',
          ),
          if (entry.error != null)
            _Section(title: 'Error', body: entry.error!, danger: true),
          _Section(
            title: 'Header',
            body: entry.requestHeaders.entries
                .map((e) => '${e.key}: ${e.value}')
                .join('\n'),
          ),
          if (entry.requestBody != null)
            _Section(title: 'Request', body: entry.requestBody!),
          if (entry.responseBody != null)
            _Section(title: 'Response', body: entry.responseBody!),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.body,
    this.danger = false,
  });

  final String title;
  final String body;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: AppColors.description,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: danger ? AppColors.unavailableBg : AppColors.surface,
              border: Border.all(color: AppColors.borderAlt),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              body.isEmpty ? '—' : body,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.5,
                color: danger ? AppColors.unavailableFg : AppColors.title,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
