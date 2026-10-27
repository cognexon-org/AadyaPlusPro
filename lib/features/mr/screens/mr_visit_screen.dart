import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/ui/app_ui.dart';
import '../providers/mr_provider.dart';
import '../widgets/mr_sheets.dart';
import '../widgets/mr_ui.dart';

/// One call, start to finish: check in at the customer (GPS), write the
/// call report on the way out, submit it, and — for a manager — approve
/// it or send it back.
class MrVisitScreen extends ConsumerStatefulWidget {
  final String visitId;
  const MrVisitScreen({super.key, required this.visitId});

  @override
  ConsumerState<MrVisitScreen> createState() => _MrVisitScreenState();
}

class _MrVisitScreenState extends ConsumerState<MrVisitScreen> {
  bool _busy = false;

  Map<String, dynamic>? _visit(MrState s) {
    for (final v in s.visits) {
      if (idOf(v) == widget.visitId) return v;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (_visit(ref.read(mrProvider)) == null) ref.read(mrProvider.notifier).loadVisits();
    });
  }

  Future<void> _do(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    await mrRun(context, action, done: done);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _directions(Map<String, dynamic> account) async {
    final loc = mapOf(account['location']);
    final address = mapOf(account['address']);
    final q = loc['lat'] != null
        ? '${loc['lat']},${loc['lng']}'
        : [account['name'], address['line1'], address['city']].where((e) => e != null && '$e'.isNotEmpty).join(', ');
    await launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(q)}'), mode: LaunchMode.externalApplication);
  }

  Future<void> _writeReport(Map<String, dynamic> v) async {
    final saved = await showAppSheet<bool>(context, builder: (_) => _ReportSheet(visit: v));
    if (saved == true && mounted) mrToast(context, 'Report saved — submit it when you’re ready');
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(mrProvider);
    final v = _visit(s);
    final accent = ModuleAccent.of(context);
    if (v == null) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(title: const Text('Call')),
        body: s.isLoading ? const AppDetailSkeleton() : const Center(child: AppEmptyState(icon: LucideIcons.searchX, text: 'This call isn’t in this month’s list.')),
      );
    }
    final account = mapOf(v['accountId']);
    final kind = accountKind(account['type']?.toString());
    final status = '${v['status']}';
    final mine = s.isMine(v['profileId']);
    final when = mrDate(v['visitDate']);
    final notifier = ref.read(mrProvider.notifier);
    final address = mapOf(account['address']);
    final place = [address['line1'], address['area'], address['city']].where((e) => e != null && '$e'.isNotEmpty).join(', ');

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 12, 0),
              child: Row(
                children: [
                  IconButton(tooltip: 'Back', icon: const Icon(LucideIcons.arrowLeft, size: 22), onPressed: () => Navigator.of(context).maybePop()),
                  Expanded(child: Text(mine ? 'Your call' : 'Call by ${repName(v['profileId'])}', style: AppType.sans(fontSize: AppType.title, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                  MrStatusPill(status, icon: true),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: accent.color,
                onRefresh: () => notifier.loadVisits(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: [
                    AppEntrance(
                      child: Row(
                        children: [
                          MrAvatar(name: '${account['name'] ?? ''}', icon: kind.icon, size: 56),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${account['name'] ?? 'Customer'}', style: AppType.sans(fontSize: AppType.heading + 2, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
                                Text(
                                  [kind.label, account['specialty'], if ('${account['classification'] ?? ''}'.length == 1) 'Class ${account['classification']}']
                                      .where((e) => e != null && '$e'.isNotEmpty)
                                      .join(' · '),
                                  style: AppType.sans(fontSize: AppType.small, color: accent.color, fontWeight: FontWeight.w600),
                                ),
                                if (when != null)
                                  Text('${dayLabel(when)} · ${timeLabel(when)}', style: AppType.sans(fontSize: AppType.small, color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (place.isNotEmpty || mapOf(account['location']).isNotEmpty) ...[
                      const SizedBox(height: 12),
                      AppCard(
                        margin: EdgeInsets.zero,
                        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                        child: Row(
                          children: [
                            Icon(LucideIcons.mapPin, size: 17, color: accent.color),
                            const SizedBox(width: 10),
                            Expanded(child: Text(place.isEmpty ? 'Location saved' : place, style: AppType.sans(fontSize: AppType.small, color: AppColors.textPrimary))),
                            TextButton.icon(
                              onPressed: () => _directions(account),
                              icon: const Icon(LucideIcons.navigation, size: 15),
                              label: const Text('Directions'),
                              style: TextButton.styleFrom(foregroundColor: accent.color),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    AppEntrance(index: 1, child: _Stepper(status: status)),
                    const SizedBox(height: 18),
                    if (v['checkIn'] is Map) ...[
                      _GeoNote(visit: v),
                      const SizedBox(height: 12),
                    ],
                    if (status == 'rejected' && '${v['managerComment'] ?? ''}'.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: AppColors.errorBg, borderRadius: BorderRadius.circular(14)),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(LucideIcons.messageSquareWarning, size: 18, color: AppColors.error),
                            const SizedBox(width: 10),
                            Expanded(child: Text('Sent back: ${v['managerComment']}', style: AppType.sans(fontSize: AppType.small, color: AppColors.textPrimary))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (const {'completed', 'submitted', 'approved', 'rejected'}.contains(status)) _Report(visit: v),
                    const SizedBox(height: 18),
                    // The one next step for this call.
                    if (mine && status == 'planned')
                      AppButton(label: 'Check in here', icon: LucideIcons.mapPinCheck, loading: _busy, onPressed: () => _do(() => notifier.checkInVisit(widget.visitId), 'Checked in'))
                    else if (mine && status == 'checked_in')
                      AppButton(label: 'Write call report', icon: LucideIcons.filePen, onPressed: () => _writeReport(v))
                    else if (mine && (status == 'completed' || status == 'rejected'))
                      AppButton(label: 'Submit report', icon: LucideIcons.send, loading: _busy, onPressed: () => _do(() => notifier.submitVisit(widget.visitId), 'Report sent to your manager'))
                    else if (!mine && s.isManager && status == 'submitted')
                      AppButton(
                        label: 'Review report',
                        icon: LucideIcons.clipboardCheck,
                        loading: _busy,
                        onPressed: () async {
                          final r = await reviewSheet(context, title: 'Review call report', subtitle: '${repName(v['profileId'])} · ${account['name'] ?? ''}');
                          if (r == null || !mounted) return;
                          _do(() => notifier.reviewVisit(widget.visitId, r.$1, comment: r.$2), r.$1 == 'approve' ? 'Approved' : 'Sent back');
                        },
                      ),
                    if (mine && status == 'planned' && account['type'] != 'doctor') ...[
                      const SizedBox(height: 10),
                      AppSecondaryButton(label: 'Book an order', icon: LucideIcons.shoppingCart, onPressed: () => newOrder(context, ref, account: account)),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  final String status;
  const _Stepper({required this.status});

  static const _steps = [('Planned', LucideIcons.calendarClock), ('Checked in', LucideIcons.mapPinCheck), ('Reported', LucideIcons.filePen), ('Submitted', LucideIcons.send), ('Approved', LucideIcons.circleCheck)];

  int get _at => switch (status) {
    'checked_in' => 1,
    'completed' || 'rejected' => 2,
    'submitted' => 3,
    'approved' => 4,
    _ => 0,
  };

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    final at = _at;
    return Row(
      children: [
        for (var i = 0; i < _steps.length; i++) ...[
          Column(
            children: [
              AnimatedContainer(
                duration: AppMotion.medium,
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: i <= at ? (status == 'rejected' && i == 2 ? AppColors.error : accent.color) : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: i <= at ? (status == 'rejected' && i == 2 ? AppColors.error : accent.color) : AppColors.borderStrong, width: 1.5),
                ),
                child: Icon(_steps[i].$2, size: 14, color: i <= at ? Colors.white : AppColors.textTertiary),
              ),
              const SizedBox(height: 4),
              Text(_steps[i].$1, style: AppType.sans(fontSize: AppType.micro, fontWeight: i == at ? FontWeight.w800 : FontWeight.w500, color: i <= at ? AppColors.textStrong : AppColors.textTertiary)),
            ],
          ),
          if (i < _steps.length - 1)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: i < at ? 1 : 0),
                  duration: const Duration(milliseconds: 600),
                  builder: (_, t, _) => LinearProgressIndicator(value: t, minHeight: 2.5, backgroundColor: AppColors.borderStrong, color: accent.color),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _GeoNote extends StatelessWidget {
  final Map<String, dynamic> visit;
  const _GeoNote({required this.visit});

  @override
  Widget build(BuildContext context) {
    final at = mrDate(mapOf(visit['checkIn'])['capturedAt']) ?? mrDate(mapOf(visit['checkIn'])['at']);
    final d = (visit['checkInDistanceMeters'] as num?)?.round();
    final status = '${visit['geofenceStatus'] ?? 'unknown'}';
    final (icon, color, text) = switch (status) {
      'inside' => (LucideIcons.mapPinCheck, AppColors.success, 'Checked in at the customer${d != null ? ' · $d m away' : ''}'),
      'outside' => (LucideIcons.mapPinOff, AppColors.warning, 'Checked in ${d != null ? '$d m' : 'far'} from the customer’s location'),
      _ => (LucideIcons.mapPin, AppColors.textSecondary, 'Checked in — the customer has no saved location to compare'),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Color.alphaBlend(color.withValues(alpha: 0.08), Colors.white), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppType.sans(fontSize: AppType.small, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
          if (at != null) Text(timeLabel(at), style: AppType.sans(fontSize: AppType.caption, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _Report extends StatelessWidget {
  final Map<String, dynamic> visit;
  const _Report({required this.visit});

  @override
  Widget build(BuildContext context) {
    final v = visit;
    final products = listOf(v['productsDiscussed']).map((p) => '${p['productName'] ?? ''}').where((p) => p.isNotEmpty).toList();
    final samples = listOf(v['samples']);
    final gifts = listOf(v['gifts']);
    final next = mrDate(v['nextVisitDate']);
    final pob = (v['pobAmount'] as num?) ?? 0;
    Widget row(IconData icon, String label, Widget value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: ModuleAccent.of(context).color),
          const SizedBox(width: 10),
          SizedBox(width: 92, child: Text(label, style: AppType.sans(fontSize: AppType.small, color: AppColors.textSecondary))),
          Expanded(child: value),
        ],
      ),
    );
    Text t(String s) => Text(s, style: AppType.sans(fontSize: AppType.body, color: AppColors.textStrong));
    return AppCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Call report', style: AppType.sans(fontSize: AppType.title, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
          const SizedBox(height: 4),
          if (products.isNotEmpty)
            row(LucideIcons.presentation, 'Discussed', Wrap(spacing: 6, runSpacing: 6, children: [for (final p in products) AppStatusPill(text: p, color: AppColors.textPrimary, background: AppColors.panel)])),
          if (samples.isNotEmpty) row(LucideIcons.package, 'Samples', t(samples.map((x) => '${x['productName']} × ${x['quantity']}').join('\n'))),
          if (gifts.isNotEmpty) row(LucideIcons.gift, 'Gifts', t(gifts.map((x) => '${x['itemName']} × ${x['quantity']}').join('\n'))),
          if ('${v['doctorFeedback'] ?? ''}'.isNotEmpty) row(LucideIcons.messageCircle, 'Feedback', t('${v['doctorFeedback']}')),
          if ('${v['discussionNotes'] ?? ''}'.isNotEmpty) row(LucideIcons.notebookPen, 'Notes', t('${v['discussionNotes']}')),
          if (pob > 0) row(LucideIcons.shoppingCart, 'Order value', t(appRupees(pob))),
          if (next != null) row(LucideIcons.calendarClock, 'Next visit', t(DateFormat('EEE d MMM').format(next))),
          if (products.isEmpty && samples.isEmpty && gifts.isEmpty && '${v['doctorFeedback'] ?? ''}'.isEmpty && '${v['discussionNotes'] ?? ''}'.isEmpty)
            Text('No details were recorded.', style: AppType.sans(fontSize: AppType.small, color: AppColors.textTertiary)),
        ],
      ),
    );
  }
}

/// The call report written on check-out.
class _ReportSheet extends ConsumerStatefulWidget {
  final Map<String, dynamic> visit;
  const _ReportSheet({required this.visit});

  @override
  ConsumerState<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<_ReportSheet> {
  final _product = TextEditingController();
  final _products = <String>[];
  final _samples = <String, int>{}; // productName → qty
  final _gifts = <String, int>{};
  final _feedback = TextEditingController();
  final _notes = TextEditingController();
  final _pob = TextEditingController();
  DateTime? _next;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_product, _feedback, _notes, _pob]) {
      c.dispose();
    }
    super.dispose();
  }

  void _addProduct([String? name]) {
    final p = (name ?? _product.text).trim();
    if (p.isEmpty || _products.contains(p)) return;
    HapticFeedback.selectionClick();
    setState(() {
      _products.add(p);
      _product.clear();
    });
  }

  Future<void> _save() async {
    if (_products.isEmpty && _feedback.text.trim().isEmpty && _notes.text.trim().isEmpty) {
      setState(() => _error = 'Add what you discussed or a note');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(mrProvider.notifier).checkOutVisit(
        idOf(widget.visit),
        products: _products,
        samples: [for (final e in _samples.entries) if (e.value > 0) (name: e.key, qty: e.value)],
        gifts: [for (final e in _gifts.entries) if (e.value > 0) (name: e.key, qty: e.value)],
        doctorFeedback: _feedback.text,
        discussionNotes: _notes.text,
        nextVisitDate: _next,
        pobAmount: num.tryParse(_pob.text.trim()),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  Widget _stock(String title, String type, Map<String, int> picked) {
    final balances = ref.watch(mrProvider).sampleBalances.where((b) => b['itemType'] == type && ((b['balance'] as num?) ?? 0) > 0 && ref.read(mrProvider).isMine(b['profileId'])).toList();
    if (balances.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Text(title, style: AppType.sans(fontSize: AppType.small, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        ),
        for (final b in balances)
          Builder(
            builder: (_) {
              final name = '${b['productName']}';
              final have = (b['balance'] as num).toInt();
              final q = picked[name] ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(TextSpan(children: [
                        TextSpan(text: name, style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w600, color: AppColors.textStrong)),
                        TextSpan(text: '  $have in hand', style: AppType.sans(fontSize: AppType.caption, color: AppColors.textTertiary)),
                      ])),
                    ),
                    IconButton(onPressed: q > 0 ? () => setState(() => picked[name] = q - 1) : null, icon: const Icon(LucideIcons.minus, size: 16)),
                    SizedBox(width: 22, child: Text('$q', textAlign: TextAlign.center, style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w800))),
                    IconButton(onPressed: q < have ? () => setState(() => picked[name] = q + 1) : null, icon: const Icon(LucideIcons.plus, size: 16)),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = mapOf(widget.visit['accountId']);
    final suggestions = {
      for (final b in ref.watch(mrProvider).sampleBalances)
        if (b['itemType'] == 'sample') '${b['productName']}',
    }.where((p) => !_products.contains(p)).take(8).toList();
    return MrSheetBody(
      children: [
        MrSheetTitle('Call report', subtitle: '${account['name'] ?? ''} · checking out saves your location'),
        Row(
          children: [
            Expanded(child: AppTextField(label: 'Products discussed', controller: _product, hint: 'Type and press enter', textCapitalization: TextCapitalization.words, onSubmitted: (_) => _addProduct(), margin: EdgeInsets.zero)),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 18),
              child: IconButton.filledTonal(onPressed: _addProduct, icon: const Icon(LucideIcons.plus, size: 18)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in _products)
              InputChip(label: Text(p), onDeleted: () => setState(() => _products.remove(p))),
            for (final p in suggestions)
              ActionChip(avatar: const Icon(LucideIcons.plus, size: 14), label: Text(p), onPressed: () => _addProduct(p)),
          ],
        ),
        const SizedBox(height: 8),
        _stock('Samples given', 'sample', _samples),
        _stock('Gifts given', 'gift', _gifts),
        const SizedBox(height: 8),
        AppTextField(label: 'Customer feedback', controller: _feedback, maxLines: 2, textCapitalization: TextCapitalization.sentences),
        AppTextField(label: 'Notes', controller: _notes, maxLines: 2, textCapitalization: TextCapitalization.sentences),
        Row(
          children: [
            Expanded(
              child: AppPickerField(
                label: 'Next visit',
                valueText: _next == null ? 'Not set' : DateFormat('d MMM').format(_next!),
                onTap: () async {
                  final d = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 14)), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 120)));
                  if (d != null) setState(() => _next = d);
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: AppTextField(label: 'Order value ₹', controller: _pob, isDecimal: true)),
          ],
        ),
        if (_error != null)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: AppType.sans(fontSize: AppType.small, color: AppColors.error))),
        AppButton(label: 'Check out and save', icon: LucideIcons.logOut, loading: _busy, onPressed: _save),
      ],
    );
  }
}
