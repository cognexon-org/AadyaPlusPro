import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../providers/doctor_prescriptions_provider.dart';
import 'doctor_ui.dart';

/// Picks the appointment a prescription is written against. The server has
/// no text search on appointments, so recent prescribable ones are loaded
/// once and filtered here by patient name or phone. Returns the appointment
/// map (patient populated), or null if dismissed.
Future<Map<String, dynamic>?> showRxAppointmentPicker(BuildContext context) =>
    showAppSheet<Map<String, dynamic>>(
      context,
      builder: (_) => const _RxAppointmentSheet(),
    );

class _RxAppointmentSheet extends ConsumerStatefulWidget {
  const _RxAppointmentSheet();

  @override
  ConsumerState<_RxAppointmentSheet> createState() =>
      _RxAppointmentSheetState();
}

class _RxAppointmentSheetState extends ConsumerState<_RxAppointmentSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  int _seq = 0;

  List<Map<String, dynamic>> _all = const [];
  String _query = '';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await ref
          .read(doctorPrescriptionsProvider.notifier)
          .searchAppointments();
      if (!mounted || seq != _seq) return;
      setState(() {
        _all = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _error = doctorError(e, fallback: 'Couldn’t load appointments.');
      });
    }
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = v.trim().toLowerCase());
    });
  }

  List<Map<String, dynamic>> get _results {
    if (_query.isEmpty) return _all;
    return _all.where((a) {
      final p = apptPatient(a);
      return '${p['name'] ?? ''}'.toLowerCase().contains(_query) ||
          '${p['phone'] ?? ''}'.contains(_query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose appointment',
            style: AppType.sans(
              fontSize: AppType.title,
              fontWeight: FontWeight.w700,
              color: AppColors.textStrong,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Prescriptions are written against a confirmed or completed visit.',
            style: AppType.sans(
              fontSize: AppType.caption,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          AppSearchField(
            controller: _search,
            hint: 'Search patient name or phone',
            onChanged: _onChanged,
          ),
          const SizedBox(height: 12),
          Flexible(
            child: _loading
                ? const SingleChildScrollView(child: AppListSkeleton(count: 4))
                : _error != null
                ? Align(
                    alignment: Alignment.topCenter,
                    child: AppErrorBanner(message: _error!, onRetry: _load),
                  )
                : results.isEmpty
                ? Align(
                    alignment: Alignment.topCenter,
                    child: AppEmptyState(
                      icon: LucideIcons.calendarSearch,
                      text: _query.isEmpty
                          ? 'No confirmed or completed appointments yet.'
                          : 'No appointments match “${_search.text.trim()}”.',
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: results.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final a = results[i];
                      return DoctorAppointmentCard(
                        key: ValueKey('${a['_id']}'),
                        appointment: a,
                        showDay: true,
                        onTap: () => Navigator.of(context).pop(a),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
