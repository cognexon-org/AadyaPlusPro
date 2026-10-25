import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/network/api_service.dart';
import '../theme/pharmacy_colors.dart';
import '../theme/pharmacy_type.dart';
import '../widgets/pharmacy_ui.dart';

/// The Schedule H / H1 / X register, read-only. Entries are written by the
/// server when an online order containing a scheduled drug is accepted, so
/// this screen is what a store shows a drug inspector.
class ScheduleRegisterScreen extends StatefulWidget {
  const ScheduleRegisterScreen({super.key});

  @override
  State<ScheduleRegisterScreen> createState() => _ScheduleRegisterScreenState();
}

class _ScheduleRegisterScreenState extends State<ScheduleRegisterScreen> {
  static const _filters = [
    (null, 'All'),
    ('Schedule H1', 'H1'),
    ('Schedule X', 'X'),
    ('Schedule H', 'H'),
  ];

  String? _schedule;
  List<Map<String, dynamic>> _entries = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _entries.isEmpty;
      _error = null;
    });
    try {
      final res = await ApiService().getScheduleRegister(
        queryParams: {
          'limit': 200,
          if (_schedule != null) 'schedule': _schedule,
        },
      );
      final list = res.data is Map ? (res.data as Map)['entries'] : null;
      if (!mounted) return;
      setState(() {
        _entries = list is List
            ? list
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
            : const [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = pharmacyErrorMessage(
          e,
          fallback: "Couldn't load the register.",
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PharmacyColors.bg,
      appBar: AppBar(
        backgroundColor: PharmacyColors.bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: PharmacyColors.textPrimary),
        title: Text(
          'Schedule H register',
          style: PharmacyType.sans(
            fontSize: PharmacyType.title,
            fontWeight: FontWeight.w600,
            color: PharmacyColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: PharmacyColors.green,
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (value, label) in _filters)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: PharmacyFilterChip(
                          label: label,
                          selected: _schedule == value,
                          onTap: () {
                            if (_schedule == value) return;
                            setState(() {
                              _schedule = value;
                              _entries = const [];
                            });
                            _load();
                          },
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (_error != null)
                PharmacyErrorBanner(message: _error!, onRetry: _load)
              else if (_loading)
                const PharmacyListSkeleton(count: 4)
              else if (_entries.isEmpty)
                const PharmacyEmptyStateInline(
                  icon: LucideIcons.bookLock,
                  text:
                      'Nothing recorded yet. Scheduled medicines are added here automatically when you accept an online order.',
                )
              else
                for (final (i, e) in _entries.indexed)
                  PharmacyEntrance(
                    index: i.clamp(0, 8),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _EntryCard(entry: e),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  final Map<String, dynamic> entry;
  const _EntryCard({required this.entry});

  String _s(String key) => '${entry[key] ?? ''}'.trim();

  @override
  Widget build(BuildContext context) {
    final when = DateTime.tryParse(_s('dispensedAt'))?.toLocal();
    final rxDate = DateTime.tryParse(_s('prescriptionDate'))?.toLocal();
    final schedule = _s('schedule').replaceFirst('Schedule ', '');
    final batches = ((entry['batches'] as List?) ?? const [])
        .whereType<Map>()
        .map((b) {
          final exp = DateTime.tryParse('${b['expiryDate'] ?? ''}');
          return [
            '${b['batchNumber'] ?? '—'} × ${b['quantity'] ?? ''}',
            if (exp != null) 'exp ${DateFormat('MM/yy').format(exp)}',
          ].join(' ');
        })
        .join(', ');

    Widget line(String label, String value) => value.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 82,
                  child: Text(
                    label,
                    style: PharmacyType.sans(
                      fontSize: PharmacyType.caption,
                      color: PharmacyColors.textTertiary,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    value,
                    style: PharmacyType.sans(
                      fontSize: PharmacyType.caption,
                      color: PharmacyColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: PharmacyColors.panel,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  [
                    _s('medicineName'),
                    // "Azithral 500" already says 500; don't repeat it.
                    if (!_s('medicineName').contains(
                      _s('strength').replaceAll(RegExp(r'[a-zA-Z\s]'), ''),
                    ))
                      _s('strength'),
                  ].where((e) => e.isNotEmpty).join(' '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PharmacyType.sans(
                    fontSize: PharmacyType.body,
                    fontWeight: FontWeight.w700,
                    color: PharmacyColors.textStrong,
                  ),
                ),
              ),
              Text(
                schedule,
                style: PharmacyType.sans(
                  fontSize: PharmacyType.caption,
                  fontWeight: FontWeight.w700,
                  color: schedule == 'H'
                      ? PharmacyColors.textSecondary
                      : PharmacyColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            [
              'Qty ${_s('quantity')}',
              if (when != null) DateFormat('d MMM yyyy, h:mm a').format(when),
              _s('orderNumber'),
            ].where((e) => e.isNotEmpty).join(' · '),
            style: PharmacyType.sans(
              fontSize: PharmacyType.micro,
              color: PharmacyColors.textTertiary,
            ),
          ),
          const SizedBox(height: 4),
          line(
            'Patient',
            [
              _s('patientName'),
              _s('patientPhone'),
            ].where((e) => e.isNotEmpty).join(' · '),
          ),
          line('Address', _s('patientAddress')),
          line(
            'Prescriber',
            [
              _s('prescriberName'),
              if (_s('prescriberRegistration').isNotEmpty)
                'Reg. ${_s('prescriberRegistration')}',
            ].where((e) => e.isNotEmpty).join(' · '),
          ),
          line(
            'Rx date',
            rxDate == null ? '' : DateFormat('d MMM yyyy').format(rxDate),
          ),
          line('Batch', batches),
        ],
      ),
    );
  }
}
