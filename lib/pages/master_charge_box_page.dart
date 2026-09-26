import 'package:flutter/material.dart';

import '../data/charge_point_repository.dart';
import '../models/auth_type.dart';
import '../models/charge_box.dart';
import '../models/spklu.dart';
import '../services/api_exception.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../widgets/page_scaffold.dart';
import '../widgets/primary_button.dart';

/// Daftar charge box milik satu SPKLU di CSMS, untuk didaftarkan ke
/// unit ini lewat `POST /master/set-chargerbox-evtap`.
///
/// Petugas mencentang charge box yang dipakai unit ini, mengisi
/// kredensialnya pada kartu yang sama, lalu menekan satu tombol —
/// permintaannya dikirim satu per satu untuk tiap yang dicentang.
class MasterChargeBoxPage extends StatefulWidget {
  const MasterChargeBoxPage({
    super.key,
    required this.spklu,
    required this.repository,
  });

  final Spklu spklu;
  final ChargePointRepository repository;

  @override
  State<MasterChargeBoxPage> createState() => _MasterChargeBoxPageState();
}

class _MasterChargeBoxPageState extends State<MasterChargeBoxPage> {
  late final List<_Entry> _entries = [
    for (final box in widget.spklu.chargeBoxes) _Entry(box),
  ];

  bool _saving = false;

  @override
  void dispose() {
    for (final entry in _entries) {
      entry.dispose();
    }
    super.dispose();
  }

  List<_Entry> get _selected =>
      _entries.where((entry) => entry.selected).toList();

  /// Mengirim satu permintaan untuk tiap charge box yang dicentang.
  ///
  /// Dikirim berurutan, bukan serentak: kalau satu ditolak, yang lain
  /// tetap terkirim dan petugas melihat persis kartu mana yang gagal.
  Future<void> _save() async {
    final selected = _selected;
    if (selected.isEmpty || _saving) return;

    // Kredensial diperiksa lebih dulu supaya tidak ada yang terkirim
    // separuh hanya untuk ditolak backend karena field kosong.
    final incomplete = selected.where((entry) => !entry.isComplete).toList();
    if (incomplete.isNotEmpty) {
      setState(() {
        for (final entry in incomplete) {
          entry.status = _Status.failed;
          entry.message = 'Username dan password wajib diisi.';
        }
      });
      return;
    }

    setState(() {
      _saving = true;
      for (final entry in selected) {
        entry.status = _Status.sending;
        entry.message = '';
      }
    });

    for (final entry in selected) {
      try {
        await widget.repository.setChargeBoxEvtap(
          chargeBoxId: entry.box.id,
          authType: entry.authType,
          idEdgeController: entry.edgeController.text.trim(),
          idSpklu: widget.spklu.id,
          username: entry.username.text.trim(),
          password: entry.password.text,
        );
        if (!mounted) return;
        setState(() {
          entry.status = _Status.saved;
          entry.message = '';
        });
      } on ApiException catch (e) {
        if (!mounted) return;
        setState(() {
          entry.status = _Status.failed;
          entry.message = e.message;
        });
      } on Object catch (e) {
        if (!mounted) return;
        setState(() {
          entry.status = _Status.failed;
          entry.message = 'Gagal disimpan: $e';
        });
      }
    }

    if (!mounted) return;
    setState(() => _saving = false);

    final failed = selected.where((e) => e.status == _Status.failed).length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed == 0
              ? '${selected.length} charge box tersimpan.'
              : '$failed dari ${selected.length} charge box gagal disimpan.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected.length;

    return PageScaffold(
      title: 'Charge Box CSMS',
      subtitle: widget.spklu.nama.isEmpty
          ? 'Pilih charge box yang dipakai unit ini.'
          : '${widget.spklu.nama} — pilih charge box yang dipakai unit ini.',
      backgroundColor: AppColors.pageBackgroundPlain,
      bottomBar: BottomActionBar(
        children: [
          PrimaryButton(
            label: _saving ? 'Menyimpan…' : 'Simpan Info Charge Box',
            trailingAsset: null,
            onPressed: selected == 0 || _saving ? null : _save,
          ),
          SecondaryButton(
            label: 'Kembali',
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
          ),
        ],
      ),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        itemCount: _entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, index) => _ChargeBoxCard(
          entry: _entries[index],
          enabled: !_saving,
          onChanged: () => setState(() {}),
        ),
      ),
    );
  }
}

/// Keadaan satu kartu: pilihan, isian, dan hasil pengirimannya.
class _Entry {
  _Entry(this.box)
    : username = TextEditingController(text: box.id),
      edgeController = TextEditingController(),
      password = TextEditingController();

  final ChargeBox box;

  final TextEditingController edgeController;
  final TextEditingController username;
  final TextEditingController password;

  bool selected = false;
  String authType = AuthType.basic;
  _Status status = _Status.idle;
  String message = '';

  /// Backend menolak username/password kosong kecuali untuk NONE.
  bool get isComplete =>
      authType == AuthType.none ||
      (username.text.trim().isNotEmpty && password.text.isNotEmpty);

  void dispose() {
    edgeController.dispose();
    username.dispose();
    password.dispose();
  }
}

enum _Status { idle, sending, saved, failed }

class _ChargeBoxCard extends StatelessWidget {
  const _ChargeBoxCard({
    required this.entry,
    required this.enabled,
    required this.onChanged,
  });

  final _Entry entry;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final box = entry.box;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(
          color: entry.selected ? AppColors.primary : AppColors.borderAlt,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: AppColors.cardShadow,
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: entry.selected,
                onChanged: enabled
                    ? (value) {
                        entry.selected = value ?? false;
                        onChanged();
                      }
                    : null,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      box.displayName?.isNotEmpty == true
                          ? box.displayName!
                          : box.id,
                      style: AppTheme.rowValue,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      [
                        box.id,
                        if (box.merek.isNotEmpty) box.merek,
                        if (box.daya.isNotEmpty) box.daya,
                        '${box.connectorTotal ?? box.connectors.length} konektor',
                      ].join(' • '),
                      style: AppTheme.pageSubtitle,
                    ),
                  ],
                ),
              ),
              _StatusLabel(status: entry.status),
            ],
          ),
          if (entry.selected) ...[
            const SizedBox(height: 12),
            _Field(
              label: 'ID Edge Controller',
              hint: 'EC-00001-1',
              controller: entry.edgeController,
              enabled: enabled,
              onChanged: onChanged,
            ),
            const SizedBox(height: 8),
            _AuthTypeField(
              entry: entry,
              enabled: enabled,
              onChanged: onChanged,
            ),
            if (entry.authType != AuthType.none) ...[
              const SizedBox(height: 8),
              _Field(
                label: 'Username',
                hint: box.id,
                controller: entry.username,
                enabled: enabled,
                onChanged: onChanged,
              ),
              const SizedBox(height: 8),
              _Field(
                label: 'Password',
                hint: '••••••',
                controller: entry.password,
                enabled: enabled,
                obscure: true,
                onChanged: onChanged,
              ),
            ],
          ],
          if (entry.message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              entry.message,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.unavailableFg,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AuthTypeField extends StatelessWidget {
  const _AuthTypeField({
    required this.entry,
    required this.enabled,
    required this.onChanged,
  });

  final _Entry entry;
  final bool enabled;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: entry.authType,
      decoration: InputDecoration(
        labelText: 'Auth Type',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        isDense: true,
      ),
      items: [
        for (final value in AuthType.values)
          DropdownMenuItem(value: value, child: Text(AuthType.label(value))),
      ],
      onChanged: enabled
          ? (value) {
              entry.authType = value ?? AuthType.basic;
              onChanged();
            }
          : null,
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    required this.enabled,
    required this.onChanged,
    this.obscure = false,
  });

  final String label;
  final String hint;
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onChanged: (_) => onChanged(),
    );
  }
}

class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.status});

  final _Status status;

  @override
  Widget build(BuildContext context) => switch (status) {
    _Status.idle => const SizedBox.shrink(),
    _Status.sending => const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
    _Status.saved => const Text(
      'Tersimpan',
      style: TextStyle(fontSize: 12, color: AppColors.availableFg),
    ),
    _Status.failed => const Text(
      'Gagal',
      style: TextStyle(fontSize: 12, color: AppColors.unavailableFg),
    ),
  };
}
