import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/ui/app_ui.dart';
import '../../doctor/widgets/availability_save_bar.dart';
import '../providers/physio_profile_provider.dart';
import '../widgets/physio_package_widgets.dart';

/// Treatment packages: a number of sessions sold for one price (e.g. 10
/// sessions for ₹6,000). Patients pay once and each session is counted off
/// the course automatically.
class PhysioPackages extends ConsumerStatefulWidget {
  const PhysioPackages({super.key});

  @override
  ConsumerState<PhysioPackages> createState() => _PhysioPackagesState();
}

class _PhysioPackagesState extends ConsumerState<PhysioPackages> {
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) ref.read(physioPackagesProvider.notifier).load();
    });
  }

  Future<void> _refresh() => ref.read(physioPackagesProvider.notifier).load();

  int get _defaultDuration {
    final v = int.tryParse(
      '${ref.read(physioProfileProvider).profile['slotDurationMinutes'] ?? ''}',
    );
    return v == null || v < 5 ? 45 : v;
  }

  Future<void> _create() async {
    final notifier = ref.read(physioPackagesProvider.notifier);
    final ok = await showPhysioPackageSheet(
      context,
      defaultDuration: _defaultDuration,
      onSave: notifier.create,
    );
    if (ok == true && mounted) doctorToast(context, 'Package created');
  }

  Future<void> _edit(Map<String, dynamic> pkg) async {
    final id = '${pkg['_id'] ?? ''}';
    if (id.isEmpty) return;
    final notifier = ref.read(physioPackagesProvider.notifier);
    final active = pkg['isActive'] != false;
    var toggled = false;
    final ok = await showPhysioPackageSheet(
      context,
      initial: pkg,
      defaultDuration: _defaultDuration,
      onSave: (body) => notifier.update(id, body),
      onArchiveToggle: () async {
        if (active) {
          final confirmed = await AppModal.confirm(
            context,
            title: 'Archive this package?',
            message:
                'Patients won’t be able to buy it any more. Courses already '
                'bought keep running.',
            icon: LucideIcons.archive,
            confirmLabel: 'Archive',
          );
          if (!confirmed) return false;
          await notifier.archive(id);
        } else {
          await notifier.restore(id);
        }
        toggled = true;
        return true;
      },
    );
    if (ok != true || !mounted) return;
    doctorToast(
      context,
      toggled
          ? (active ? 'Package archived' : 'Package restored')
          : 'Package updated',
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(physioPackagesProvider);
    final hasAny = st.packages.isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: doctorSettingsAppBar('Treatment packages'),
      floatingActionButton: hasAny
          ? AppFab(
              label: 'New package',
              icon: LucideIcons.plus,
              onPressed: _create,
            )
          : null,
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: ModuleAccent.of(context).color,
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
            children: _body(st),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(PhysioPackagesState st) {
    if (!st.hasLoaded) {
      if (st.error != null) {
        return [AppErrorBanner(message: st.error!, onRetry: _refresh)];
      }
      return const [AppListSkeleton(count: 4)];
    }
    final active = st.active;
    final archived = st.archived;
    return [
      if (st.error != null) ...[
        AppErrorBanner(message: st.error!, onRetry: _refresh),
        const SizedBox(height: 12),
      ],
      if (st.packages.isEmpty)
        AppEntrance(child: _empty())
      else ...[
        AppSectionTitle(
          active.isEmpty ? 'Active' : 'Active (${active.length})',
        ),
        if (active.isEmpty)
          const AppEmptyState(
            icon: LucideIcons.packageOpen,
            text: 'No active packages. Restore one or create a new one.',
          )
        else
          for (var i = 0; i < active.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: AppEntrance(
                index: i.clamp(0, 6),
                child: PhysioPackageCard(
                  package: active[i],
                  onTap: () => _edit(active[i]),
                ),
              ),
            ),
        if (archived.isNotEmpty) ...[
          const SizedBox(height: 14),
          AppSectionTitle(
            'Archived (${archived.length})',
            action: _showArchived ? 'Hide' : 'Show',
            onAction: () => setState(() => _showArchived = !_showArchived),
          ),
          if (_showArchived)
            for (final p in archived)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: PhysioPackageCard(package: p, onTap: () => _edit(p)),
              ),
        ],
      ],
    ];
  }

  Widget _empty() => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 22),
    decoration: BoxDecoration(
      color: AppColors.panel,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: ModuleAccent.of(context).light,
            shape: BoxShape.circle,
          ),
          child: Icon(
            LucideIcons.packageOpen,
            size: 24,
            color: ModuleAccent.of(context).color,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Sell sessions as a package',
          textAlign: TextAlign.center,
          style: AppType.sans(
            fontSize: AppType.title,
            fontWeight: FontWeight.w700,
            color: AppColors.textStrong,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '10 sessions for ₹6,000 — patients pay once, sessions are counted '
          'automatically.',
          textAlign: TextAlign.center,
          style: AppType.sans(
            fontSize: AppType.small,
            height: 1.45,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 18),
        AppButton(
          label: 'Create a package',
          icon: LucideIcons.plus,
          onPressed: _create,
        ),
      ],
    ),
  );
}
