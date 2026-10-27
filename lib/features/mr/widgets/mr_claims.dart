import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../shared/ui/app_ui.dart';
import '../providers/mr_provider.dart';
import 'mr_sheets.dart';
import 'mr_ui.dart';

// ─────────────────────────── Receipts ───────────────────────────

/// Camera, gallery or a PDF; returns the local file path.
Future<String?> pickReceipt(BuildContext context) async {
  final source = await showAppSheet<String>(
    context,
    builder: (ctx) => MrSheetBody(
      children: [
        const MrSheetTitle('Add receipt', subtitle: 'A clear photo of the bill, or a PDF'),
        for (final (key, icon, label) in [
          ('camera', LucideIcons.camera, 'Take a photo'),
          ('gallery', LucideIcons.image, 'Choose from gallery'),
          ('pdf', LucideIcons.fileText, 'Pick a PDF'),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              margin: EdgeInsets.zero,
              padding: const EdgeInsets.all(14),
              onTap: () => Navigator.pop(ctx, key),
              child: Row(
                children: [
                  AppIconBadge(icon: icon, color: ModuleAccent.of(ctx).color),
                  const SizedBox(width: 12),
                  Text(label, style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w700, color: AppColors.textStrong)),
                ],
              ),
            ),
          ),
      ],
    ),
  );
  if (source == null) return null;
  if (source == 'pdf') {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: const ['pdf']);
    return picked?.files.single.path;
  }
  final image = await ImagePicker().pickImage(
    source: source == 'camera' ? ImageSource.camera : ImageSource.gallery,
    maxWidth: 1800,
    imageQuality: 75,
  );
  return image?.path;
}

bool hasReceipt(Map<String, dynamic> expense) => mapOf(expense['receipt'])['uploadedAt'] != null;

/// The receipt on an expense, fetched with the signed-in session. Images
/// show inline (tap for full screen); a PDF opens in the share sheet.
class MrReceiptView extends ConsumerStatefulWidget {
  final Map<String, dynamic> expense;
  const MrReceiptView({super.key, required this.expense});

  @override
  ConsumerState<MrReceiptView> createState() => _MrReceiptViewState();
}

class _MrReceiptViewState extends ConsumerState<MrReceiptView> {
  Future<Uint8List>? _bytes;

  Map<String, dynamic> get _receipt => mapOf(widget.expense['receipt']);
  bool get _isPdf => '${_receipt['mimeType']}'.contains('pdf');

  @override
  void initState() {
    super.initState();
    if (!_isPdf) _bytes = _load();
  }

  @override
  void didUpdateWidget(MrReceiptView old) {
    super.didUpdateWidget(old);
    if (mapOf(old.expense['receipt'])['uploadedAt'] != _receipt['uploadedAt'] && !_isPdf) _bytes = _load();
  }

  Future<Uint8List> _load() async => Uint8List.fromList(await ref.read(mrProvider.notifier).receiptBytes(idOf(widget.expense)));

  Future<void> _openPdf() => mrRun(context, () async {
    final bytes = await _load();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/receipt-${idOf(widget.expense)}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')], subject: 'Expense receipt'));
  });

  @override
  Widget build(BuildContext context) {
    final accent = ModuleAccent.of(context);
    if (_isPdf) {
      return AppCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(12),
        onTap: _openPdf,
        child: Row(
          children: [
            AppIconBadge(icon: LucideIcons.fileText, color: accent.color),
            const SizedBox(width: 12),
            Expanded(
              child: Text('${_receipt['originalName'] ?? 'Receipt.pdf'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w600, color: AppColors.textStrong)),
            ),
            Icon(LucideIcons.externalLink, size: 16, color: AppColors.textTertiary),
          ],
        ),
      );
    }
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snap) {
        final Widget child;
        if (snap.hasData) {
          child = GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  backgroundColor: Colors.black,
                  appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Receipt')),
                  body: InteractiveViewer(maxScale: 5, child: Center(child: Image.memory(snap.data!))),
                ),
              ),
            ),
            child: Image.memory(snap.data!, fit: BoxFit.cover, width: double.infinity, height: 180),
          );
        } else if (snap.hasError) {
          child = Center(child: Text('Couldn’t load the receipt', style: AppType.sans(fontSize: AppType.small, color: AppColors.textSecondary)));
        } else {
          child = Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: accent.color)));
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Container(height: 180, width: double.infinity, color: AppColors.panel, child: child),
        );
      },
    );
  }
}

// ─────────────────────────── Expense detail ───────────────────────────

/// One expense: amount, receipt, where it stands. The rep attaches a
/// receipt and sends it; the manager reviews it and later marks it paid.
Future<void> expenseDetail(BuildContext context, String expenseId) =>
    showAppSheet<void>(context, builder: (_) => _ExpenseDetail(expenseId: expenseId));

class _ExpenseDetail extends ConsumerWidget {
  final String expenseId;
  const _ExpenseDetail({required this.expenseId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(mrProvider);
    final n = ref.read(mrProvider.notifier);
    final e = s.expenses.firstWhere((x) => idOf(x) == expenseId, orElse: () => const <String, dynamic>{});
    if (e.isEmpty) return const MrSheetBody(children: [MrSheetTitle('Expense not found')]);
    final mine = s.isMine(e['profileId']);
    final status = '${e['status']}';
    final editable = mine && (status == 'draft' || status == 'rejected');
    final date = mrDate(e['expenseDate']);
    final paidAt = mrDate(e['paidAt']);
    return MrSheetBody(
      children: [
        MrSheetTitle(
          expenseCategories[e['category']]?.$1 ?? '${e['category']}',
          subtitle: [if (!mine) repName(e['profileId']), if (date != null) DateFormat('EEE, d MMM y').format(date)].join(' · '),
        ),
        Row(
          children: [
            Text(appRupees(e['amount']), style: AppType.sans(fontSize: AppType.figure, fontWeight: FontWeight.w800, color: AppColors.textStrong)),
            const Spacer(),
            MrStatusPill(status),
          ],
        ),
        if ('${e['description'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('${e['description']}', style: AppType.sans(fontSize: AppType.body, color: AppColors.textPrimary)),
        ],
        if ('${e['managerComment'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('${status == 'rejected' ? 'Sent back' : 'Manager'}: ${e['managerComment']}', style: AppType.sans(fontSize: AppType.small, color: status == 'rejected' ? AppColors.error : AppColors.textSecondary)),
        ],
        if (status == 'paid') ...[
          const SizedBox(height: 10),
          Text(
            ['Paid${paidAt == null ? '' : ' on ${DateFormat('d MMM y').format(paidAt)}'}', if ('${e['paymentReference'] ?? ''}'.isNotEmpty) 'ref ${e['paymentReference']}'].join(' · '),
            style: AppType.sans(fontSize: AppType.small, fontWeight: FontWeight.w600, color: AppColors.success),
          ),
        ],
        const SizedBox(height: 16),
        Text('Receipt', style: AppType.sans(fontSize: AppType.small, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        if (hasReceipt(e))
          MrReceiptView(expense: e)
        else
          Text(mine ? 'No receipt yet. Claims with a receipt get approved faster.' : 'No receipt attached.', style: AppType.sans(fontSize: AppType.small, color: AppColors.textTertiary)),
        if (editable) ...[
          const SizedBox(height: 10),
          AppSecondaryButton(
            label: hasReceipt(e) ? 'Replace receipt' : 'Add receipt',
            icon: LucideIcons.paperclip,
            onPressed: () async {
              final path = await pickReceipt(context);
              if (path == null || !context.mounted) return;
              await mrRun(context, () => n.uploadReceipt(expenseId, path), done: 'Receipt attached');
            },
          ),
          const SizedBox(height: 8),
          AppButton(
            label: 'Send for approval',
            icon: LucideIcons.send,
            onPressed: () async {
              final ok = await mrRun(context, () => n.submitExpense(expenseId), done: 'Sent for approval');
              if (ok && context.mounted) Navigator.pop(context);
            },
          ),
        ],
        if (!mine && status == 'submitted') ...[
          const SizedBox(height: 16),
          AppButton(
            label: 'Review',
            icon: LucideIcons.clipboardCheck,
            onPressed: () async {
              final r = await reviewSheet(context, title: 'Review expense', subtitle: '${repName(e['profileId'])} · ${appRupees(e['amount'])}');
              if (r == null || !context.mounted) return;
              await mrRun(context, () => n.reviewExpense(expenseId, r.$1, comment: r.$2), done: r.$1 == 'approve' ? 'Approved' : 'Sent back');
            },
          ),
        ],
        if (!mine && status == 'approved') ...[
          const SizedBox(height: 16),
          AppButton(label: 'Mark paid', icon: LucideIcons.badgeIndianRupee, onPressed: () => markPaid(context, ref, e)),
        ],
      ],
    );
  }
}

Future<void> markPaid(BuildContext context, WidgetRef ref, Map<String, dynamic> e) async {
  final reference = await showAppSheet<String>(context, builder: (_) => _PaySheet(expense: e));
  if (reference == null || !context.mounted) return;
  await mrRun(context, () => ref.read(mrProvider.notifier).payExpense(idOf(e), reference: reference), done: 'Marked paid');
}

class _PaySheet extends StatefulWidget {
  final Map<String, dynamic> expense;
  const _PaySheet({required this.expense});

  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> {
  final _ref = TextEditingController();

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MrSheetBody(
    children: [
      MrSheetTitle('Mark ${appRupees(widget.expense['amount'])} paid', subtitle: repName(widget.expense['profileId'])),
      AppTextField(label: 'Payment reference', hint: 'UTR or voucher number (optional)', controller: _ref),
      AppButton(label: 'Mark paid', icon: LucideIcons.check, onPressed: () => Navigator.pop(context, _ref.text.trim())),
    ],
  );
}

// ─────────────────────────── Leave ───────────────────────────

String leaveDates(Map<String, dynamic> l) {
  final from = DateTime.tryParse('${l['fromDate']}');
  final to = DateTime.tryParse('${l['toDate']}');
  if (from == null) return '';
  if (to == null || to == from) return DateFormat('EEE, d MMM').format(from);
  final sameMonth = from.month == to.month && from.year == to.year;
  return '${DateFormat(sameMonth ? 'd' : 'd MMM').format(from)} – ${DateFormat('d MMM').format(to)}';
}

String leaveDays(Map<String, dynamic> l) {
  final d = (l['days'] as num?) ?? 0;
  if (d == 0.5) return 'Half day';
  final n = d == d.roundToDouble() ? d.toInt() : d;
  return '$n day${n == 1 ? '' : 's'}';
}

class MrLeaveCard extends StatelessWidget {
  final Map<String, dynamic> leave;
  final bool showRep;
  final Widget? trailing;
  const MrLeaveCard({super.key, required this.leave, this.showRep = false, this.trailing});

  @override
  Widget build(BuildContext context) {
    final l = leave;
    final status = '${l['status']}';
    final declined = status == 'rejected';
    return AppCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (showRep) ...[MrAvatar(name: repName(l['profileId']), size: 38), const SizedBox(width: 10)] else ...[
                AppIconBadge(icon: l['leaveType'] == 'sick' ? LucideIcons.thermometer : LucideIcons.palmtree, color: ModuleAccent.of(context).color),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      showRep ? repName(l['profileId']) : leaveDates(l),
                      style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w700, color: AppColors.textStrong),
                    ),
                    Text(
                      [if (showRep) leaveDates(l), '${leaveTypes[l['leaveType']] ?? 'Casual'} leave', leaveDays(l)].join(' · '),
                      style: AppType.sans(fontSize: AppType.caption, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              if (status == 'cancelled')
                AppStatusPill(text: 'Cancelled', color: AppColors.textSecondary, background: AppColors.panel)
              else if (declined)
                AppStatusPill(text: 'Declined', color: AppColors.error, background: Color.alphaBlend(AppColors.error.withValues(alpha: 0.1), Colors.white))
              else
                MrStatusPill(status),
            ],
          ),
          if ('${l['reason'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('${l['reason']}', style: AppType.sans(fontSize: AppType.small, color: AppColors.textPrimary)),
          ],
          if ('${l['managerComment'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Manager: ${l['managerComment']}', style: AppType.sans(fontSize: AppType.caption, color: declined ? AppColors.error : AppColors.textSecondary)),
          ],
          if (trailing != null) ...[const SizedBox(height: 10), trailing!],
        ],
      ),
    );
  }
}

Future<void> applyLeave(BuildContext context, {DateTime? from}) =>
    showAppSheet<void>(context, builder: (_) => _LeaveSheet(from: from));

class _LeaveSheet extends ConsumerStatefulWidget {
  final DateTime? from;
  const _LeaveSheet({this.from});

  @override
  ConsumerState<_LeaveSheet> createState() => _LeaveSheetState();
}

class _LeaveSheetState extends ConsumerState<_LeaveSheet> {
  late DateTime _from = _day(widget.from ?? DateTime.now().add(const Duration(days: 1)));
  late DateTime _to = _from;
  String _type = 'casual';
  bool _half = false;
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  int get _workingDays {
    var n = 0;
    for (var d = _from; !d.isAfter(_to); d = d.add(const Duration(days: 1))) {
      if (d.weekday != DateTime.sunday) n++;
    }
    return n;
  }

  Future<DateTime?> _pick(DateTime initial, DateTime first) => showDatePicker(
    context: context,
    initialDate: initial.isBefore(first) ? first : initial,
    firstDate: first,
    lastDate: DateTime.now().add(const Duration(days: 180)),
  );

  Future<void> _send() async {
    if (_workingDays == 0) {
      setState(() => _error = 'Those dates fall on a Sunday');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(mrProvider.notifier).applyLeave(from: _from, to: _to, leaveType: _type, halfDay: _half && _from == _to, reason: _reason.text);
      if (!mounted) return;
      Navigator.pop(context);
      mrToast(context, 'Leave request sent to your manager');
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final earliest = _day(DateTime.now().subtract(const Duration(days: 7)));
    final single = _from == _to;
    return MrSheetBody(
      children: [
        const MrSheetTitle('Apply for leave', subtitle: 'Your manager approves it; the days show as leave on your attendance'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in leaveTypes.entries)
              AppFilterChip(label: t.value, selected: _type == t.key, onTap: () => setState(() => _type = t.key)),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: AppPickerField(
                label: 'From',
                valueText: DateFormat('EEE, d MMM').format(_from),
                icon: LucideIcons.calendar,
                onTap: () async {
                  final d = await _pick(_from, earliest);
                  if (d == null) return;
                  setState(() {
                    _from = _day(d);
                    if (_to.isBefore(_from)) _to = _from;
                  });
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AppPickerField(
                label: 'To',
                valueText: DateFormat('EEE, d MMM').format(_to),
                icon: LucideIcons.calendar,
                onTap: () async {
                  final d = await _pick(_to, _from);
                  if (d != null) setState(() => _to = _day(d));
                },
              ),
            ),
          ],
        ),
        if (single)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(child: Text('Half day', style: AppType.sans(fontSize: AppType.body, fontWeight: FontWeight.w600, color: AppColors.textStrong))),
                Switch.adaptive(value: _half, activeTrackColor: ModuleAccent.of(context).color, onChanged: (v) => setState(() => _half = v)),
              ],
            ),
          ),
        Text(
          single && _half ? 'Half a day' : '$_workingDays working day${_workingDays == 1 ? '' : 's'}${_to.difference(_from).inDays + 1 > _workingDays ? ' · Sundays not counted' : ''}',
          style: AppType.sans(fontSize: AppType.small, fontWeight: FontWeight.w600, color: ModuleAccent.of(context).color),
        ),
        const SizedBox(height: 12),
        AppTextField(label: 'Reason', hint: 'A line for your manager', controller: _reason, maxLines: 2, textCapitalization: TextCapitalization.sentences),
        if (_error != null)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: AppType.sans(fontSize: AppType.small, color: AppColors.error))),
        AppButton(label: 'Send request', icon: LucideIcons.send, loading: _busy, onPressed: _send),
      ],
    );
  }
}
