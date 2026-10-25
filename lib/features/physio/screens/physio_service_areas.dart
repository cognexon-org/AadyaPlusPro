import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/availability_save_bar.dart';
import '../../doctor/widgets/doctor_ui.dart';
import '../providers/physio_profile_provider.dart';
import '../widgets/physio_profile_widgets.dart';

/// Where the physio makes home visits: pincodes and localities, saved as
/// `servesAreas` on the profile (PUT /physio/me/profile).
class PhysioServiceAreas extends ConsumerStatefulWidget {
  const PhysioServiceAreas({super.key});

  @override
  ConsumerState<PhysioServiceAreas> createState() => _PhysioServiceAreasState();
}

class _PhysioServiceAreasState extends ConsumerState<PhysioServiceAreas> {
  final _input = TextEditingController();

  List<String> _areas = [];
  List<String> _initial = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _inputError;

  bool get _dirty =>
      !_loading && _error == null && _areas.join('|') != _initial.join('|');

  @override
  void initState() {
    super.initState();
    final st = ref.read(physioProfileProvider);
    if (st.profile.isNotEmpty) {
      _apply(st.profile);
      _loading = false;
    } else {
      Future.microtask(_load);
    }
    _input.addListener(_inputChanged);
  }

  @override
  void dispose() {
    _input.removeListener(_inputChanged);
    _input.dispose();
    super.dispose();
  }

  String _lastText = '';

  void _inputChanged() {
    if (!mounted) return;
    // Clear a stale error once the text changes (the controller also fires
    // on cursor moves and focus changes, which must keep the error).
    final text = _input.text;
    final changed = text != _lastText;
    _lastText = text;
    setState(() {
      if (changed) _inputError = null;
    });
  }

  void _apply(Map<String, dynamic> p) {
    _areas = physioStrings(p['servesAreas']);
    _initial = [..._areas];
  }

  Future<void> _load({bool retry = false}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final notifier = ref.read(physioProfileProvider.notifier);
    await (retry ? notifier.load() : notifier.ensureLoaded());
    if (!mounted) return;
    final st = ref.read(physioProfileProvider);
    if (st.profile.isEmpty) {
      // Never offer an empty list to save over areas we couldn't read.
      setState(() {
        _loading = false;
        _error = st.error ?? "Couldn't load your service areas.";
      });
      return;
    }
    setState(() {
      _apply(st.profile);
      _loading = false;
    });
  }

  /// A 6-digit pincode or a locality name; several at once with commas.
  void _add() {
    final parts = _input.text
        .split(',')
        .map((e) => e.trim().replaceAll(RegExp(r'\s+'), ' '))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return;
    final next = [..._areas];
    for (final v in parts) {
      final digits = RegExp(r'^\d+$').hasMatch(v);
      if (digits && v.length != 6) {
        setState(() => _inputError = 'A pincode is 6 digits.');
        return;
      }
      if (!digits && v.length < 2) {
        setState(() => _inputError = 'Enter a pincode or locality name.');
        return;
      }
      if (next.any((e) => e.toLowerCase() == v.toLowerCase())) {
        if (parts.length == 1) {
          setState(() => _inputError = '$v is already in your list.');
          return;
        }
        continue;
      }
      next.add(v);
    }
    _input.clear();
    setState(() {
      _areas = next;
      _inputError = null;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(physioProfileProvider.notifier).updateProfile({
        'servesAreas': _areas,
      });
      if (!mounted) return;
      setState(() {
        _saving = false;
        _initial = [..._areas];
      });
      doctorToast(context, 'Service areas saved');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      doctorToast(
        context,
        doctorError(e, fallback: "Couldn't save your service areas."),
        error: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DoctorDiscardGuard(
      dirty: _dirty,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: doctorSettingsAppBar('Service areas'),
        body: SafeArea(top: false, child: _body()),
        bottomNavigationBar: doctorSaveBar(
          dirty: _dirty,
          saving: _saving,
          onSave: _save,
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: AppFormSkeleton(fields: 3),
      );
    }
    if (_error != null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          AppErrorBanner(message: _error!, onRetry: () => _load(retry: true)),
        ],
      );
    }
    final accent = ModuleAccent.of(context).color;
    final canAdd = _input.text.trim().isNotEmpty;
    final homeOff =
        ref.watch(
          physioProfileProvider.select((s) => s.profile['homeVisitEnabled']),
        ) ==
        false;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
      children: [
        Text(
          'Patients in these pincodes and localities can book you for home '
          'visits.',
          style: AppType.sans(
            fontSize: AppType.small,
            height: 1.45,
            color: AppColors.textSecondary,
          ),
        ),
        if (homeOff) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
            decoration: BoxDecoration(
              color: AppColors.panel,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  LucideIcons.triangleAlert,
                  size: 15,
                  color: AppColors.warning,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Home visits are turned off in practice settings, so '
                    'these areas aren’t used for bookings yet.',
                    style: AppType.sans(
                      fontSize: AppType.caption,
                      height: 1.45,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        AppTextField(
          label: 'Add an area',
          controller: _input,
          icon: LucideIcons.mapPin,
          hint: 'Pincode or locality, e.g. 411001 or Baner',
          dense: true,
          errorText: _inputError,
          margin: EdgeInsets.zero,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _add(),
          trailing: TextButton(
            onPressed: canAdd ? _add : null,
            child: Text(
              'Add',
              style: AppType.sans(
                fontSize: AppType.small,
                fontWeight: FontWeight.w600,
                color: canAdd ? accent : AppColors.textDisabled,
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        AppSectionTitle(
          _areas.isEmpty ? 'Your areas' : 'Your areas (${_areas.length})',
        ),
        if (_areas.isEmpty)
          const AppEmptyState(
            icon: LucideIcons.mapPinned,
            text:
                'No areas yet. Add the pincodes or localities you travel to '
                'for home visits.',
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final a in _areas)
                PhysioRemovableChip(
                  label: a,
                  icon: RegExp(r'^\d{6}$').hasMatch(a)
                      ? LucideIcons.hash
                      : LucideIcons.mapPin,
                  onRemove: () =>
                      setState(() => _areas = [..._areas]..remove(a)),
                ),
            ],
          ),
      ],
    );
  }
}
