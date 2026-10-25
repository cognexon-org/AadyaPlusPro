import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/notifications/professional_notification_navigation_service.dart';
import '../../auth/models/user_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../screens/order_details_screen.dart';
import '../theme/pharmacy_colors.dart';
import '../theme/pharmacy_type.dart';
import 'pharmacy_ui.dart';

/// Orders announced but not yet dismissed by the user, newest first.
///
/// An order leaves only when the user dismisses it (✕) or it stops waiting
/// on the store (accepted, rejected, cancelled). Tapping the banner opens the
/// order but leaves it here, and opening the Orders tab or time passing
/// don't clear it either: an order a pharmacist never consciously saw is exactly
/// the one that gets missed.
///
/// Doctors and physiotherapists use the same stack for appointment requests:
/// those entries are added with [addAppointment] and carry their own wording.
class PharmacyOrderBannerNotifier
    extends StateNotifier<List<Map<String, dynamic>>> {
  PharmacyOrderBannerNotifier() : super(const []);

  void add(Map<String, dynamic> order) {
    final id = '${order['_id']}';
    state = [order, ...state.where((o) => '${o['_id']}' != id)];
  }

  /// An appointment request, with its banner lines already worded by the
  /// caller (the doctor and physio modules own that wording).
  /// [kind] is 'appointment' (doctor/physio) or 'labtest' (a lab booking);
  /// it decides which screen a tap opens.
  void addAppointment(
    Map<String, dynamic> appointment, {
    required String title,
    required String subtitle,
    String kind = 'appointment',
  }) => add({
    ...appointment,
    _bannerKey: {'kind': kind, 'title': title, 'subtitle': subtitle},
  });

  /// The user's ✕ on the top card: that order leaves the stack.
  void remove(String id) =>
      state = state.where((o) => '${o['_id']}' != id).toList();

  /// Drops orders that no longer need the store — accepted, rejected,
  /// cancelled or timed out. Acting on an order is the user dealing with it,
  /// so its card goes; anything still waiting stays until ✕.
  void retainOnly(Set<String> waitingIds) {
    final kept = state.where((o) => waitingIds.contains('${o['_id']}'));
    if (kept.length != state.length) state = kept.toList();
  }

  /// Clears everything — used on logout only.
  void dismiss() => state = const [];
}

/// Where an entry's own banner wording lives (appointment requests only).
const _bannerKey = '_banner';

final pharmacyOrderBannerProvider =
    StateNotifierProvider<
      PharmacyOrderBannerNotifier,
      List<Map<String, dynamic>>
    >((ref) => PharmacyOrderBannerNotifier());

/// Tracks the route on top of the app navigator, so the banner knows whether
/// the dashboard (with its nav bar) is showing, a pushed page is, or a
/// sheet/dialog is open over either.
class PharmacyRouteTracker extends NavigatorObserver {
  PharmacyRouteTracker._();
  static final instance = PharmacyRouteTracker._();

  /// Name of the topmost full-page route.
  final page = ValueNotifier<String?>(null);

  /// A bottom sheet, dialog or menu is open on top.
  final popupOpen = ValueNotifier<bool>(false);

  final _stack = <Route<dynamic>>[];

  void _sync() {
    final pages = _stack.whereType<PageRoute>();
    page.value = pages.isEmpty ? null : pages.last.settings.name ?? '';
    popupOpen.value = _stack.isNotEmpty && _stack.last is PopupRoute;
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    _stack.add(route);
    _sync();
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    _stack.remove(route);
    _sync();
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    _stack.remove(route);
    _sync();
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    final i = oldRoute == null ? -1 : _stack.indexOf(oldRoute);
    if (i >= 0 && newRoute != null) {
      _stack[i] = newRoute;
    } else if (newRoute != null) {
      _stack.add(newRoute);
    }
    _sync();
  }
}

/// Height of the dashboard's bottom bar (nav bar plus the offline strip when
/// shown), reported by [PharmacyBottomBarReporter] so the floating banner
/// sits exactly above it.
final pharmacyBottomBarHeight = ValueNotifier<double>(0);

/// Wraps the dashboard's bottom bar and publishes its height.
class PharmacyBottomBarReporter extends StatefulWidget {
  final Widget child;
  const PharmacyBottomBarReporter({super.key, required this.child});

  @override
  State<PharmacyBottomBarReporter> createState() =>
      _PharmacyBottomBarReporterState();
}

class _PharmacyBottomBarReporterState extends State<PharmacyBottomBarReporter> {
  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final h = context.size?.height;
      if (h != null && h != pharmacyBottomBarHeight.value) {
        pharmacyBottomBarHeight.value = h;
      }
    });
    return widget.child;
  }
}

/// Puts the new-order banner above every screen of the app. Installed once,
/// in `MaterialApp.builder`, around the navigator.
///
/// On the dashboard it floats above the nav bar. On a pushed page it docks
/// at the bottom and the page shrinks to make room, so it never covers that
/// page's own buttons (Accept, Approve…). It steps aside while the keyboard
/// or a sheet/dialog is up, and comes back after.
class PharmacyNewOrderOverlay extends ConsumerWidget {
  final Widget child;
  const PharmacyNewOrderOverlay({super.key, required this.child});

  static const _dashboard = '/dashboard';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(pharmacyOrderBannerProvider);
    final user = ref.watch(authProvider.select((s) => s.user));
    final tracker = PharmacyRouteTracker.instance;

    const roles = {
      UserRole.pharmacy,
      UserRole.doctor,
      UserRole.physiotherapist,
      UserRole.pathology,
    };
    if (orders.isEmpty || !roles.contains(user?.role)) return child;

    return ListenableBuilder(
      listenable: Listenable.merge([
        tracker.page,
        tracker.popupOpen,
        pharmacyBottomBarHeight,
      ]),
      builder: (context, _) {
        final media = MediaQuery.of(context);
        final hidden = tracker.popupOpen.value || media.viewInsets.bottom > 0;
        final onDashboard = tracker.page.value == _dashboard;
        final banner = _BannerStack(orders: orders);

        if (onDashboard || hidden) {
          return Stack(
            children: [
              child,
              Positioned(
                left: 12,
                right: 12,
                bottom: pharmacyBottomBarHeight.value + 8,
                child: IgnorePointer(
                  ignoring: hidden,
                  child: AnimatedOpacity(
                    opacity: hidden ? 0 : 1,
                    duration: PharmacyMotion.fast,
                    child: onDashboard ? banner : const SizedBox.shrink(),
                  ),
                ),
              ),
            ],
          );
        }

        // Docked: the page gives up the space instead of being covered.
        return ColoredBox(
          color: PharmacyColors.bg,
          child: Column(
            children: [
              Expanded(
                child: MediaQuery.removePadding(
                  context: context,
                  removeBottom: true,
                  child: child,
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  12,
                  6,
                  12,
                  media.viewPadding.bottom + 8,
                ),
                child: banner,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Newest order on top; up to two older ones peek out behind it as the
/// edges of a card stack, so "there are more" is visible at a glance.
class _BannerStack extends StatelessWidget {
  final List<Map<String, dynamic>> orders;
  const _BannerStack({required this.orders});

  static const _peek = 7.0;

  @override
  Widget build(BuildContext context) {
    final behind = (orders.length - 1).clamp(0, 2);
    final fill = _bannerFill(context);
    return AnimatedSize(
      duration: PharmacyMotion.medium,
      curve: PharmacyMotion.enter,
      alignment: Alignment.bottomCenter,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Back cards: narrower and paler the further back they sit.
          for (var i = behind; i >= 1; i--)
            Positioned(
              left: 10.0 * i,
              right: 10.0 * i,
              top: _peek * (behind - i),
              bottom: _peek * i,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color.lerp(fill, Colors.white, 0.22 * i),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 6),
                  ],
                ),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(top: _peek * behind),
            child: AnimatedSwitcher(
              duration: PharmacyMotion.medium,
              switchInCurve: PharmacyMotion.enter,
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(
                    begin: const Offset(0, -0.15),
                    end: Offset.zero,
                  ).animate(a),
                  child: child,
                ),
              ),
              child: _Banner(
                key: ValueKey('${orders.first['_id']}'),
                order: orders.first,
                total: orders.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The banner's colour: the pharmacy's deep green, or the module accent
/// deepened a little so white text reads on it.
Color _bannerFill(BuildContext context) {
  final accent = ModuleAccent.of(context).color;
  return accent == PharmacyColors.green
      ? PharmacyColors.greenDark
      : Color.lerp(accent, Colors.black, 0.18)!;
}

class _Banner extends ConsumerWidget {
  final Map<String, dynamic> order;

  /// How many orders are in the stack, this one included.
  final int total;
  const _Banner({super.key, required this.order, required this.total});

  Map? get _appointment =>
      order[_bannerKey] is Map ? order[_bannerKey] as Map : null;

  /// Opens this order or appointment. The banner stays — only the cross
  /// removes it.
  void _open() {
    final navigator =
        ProfessionalNotificationNavigationService.navigatorKey.currentState;
    if (_appointment != null) {
      final screen = _appointment!['kind'] == 'labtest'
          ? ProfessionalNotificationNavigationService.labOrderScreen
          : ProfessionalNotificationNavigationService.appointmentScreen;
      if (screen == null) return;
      navigator?.push(
        PharmacyPageRoute(builder: (_) => screen('${order['_id']}')),
      );
      return;
    }
    navigator?.push(
      PharmacyPageRoute(builder: (_) => OrderDetailsScreen(order: order)),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final patient = order['patientId'];
    final name = patient is Map ? '${patient['name'] ?? ''}'.trim() : '';
    final rx = '${order['orderStatus']}' == 'prescription_review';
    final more = total - 1;
    final appointment = _appointment;
    final title = appointment != null
        ? '${appointment['title']}'
        : rx
        ? 'New order · prescription to review'
        : 'New order received';
    final subtitle = appointment != null
        ? '${appointment['subtitle']}'
        : [
            if (name.isNotEmpty) name,
            pharmacyRupees(order['totalAmount']),
          ].join(' · ');

    return Semantics(
      liveRegion: true,
      child: Material(
        color: _bannerFill(context),
        elevation: 3,
        shadowColor: Colors.black12,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _open,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
            child: Row(
              children: [
                const Icon(LucideIcons.bellRing, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: PharmacyType.sans(
                                fontSize: PharmacyType.body,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          if (more > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '+$more more',
                                style: PharmacyType.sans(
                                  fontSize: PharmacyType.micro,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PharmacyType.sans(
                          fontSize: PharmacyType.caption,
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'View',
                  style: PharmacyType.sans(
                    fontSize: PharmacyType.small,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                // No IconButton: its tooltip needs an Overlay, and this
                // banner sits above the navigator where there is none.
                Semantics(
                  button: true,
                  label: 'Dismiss',
                  child: InkResponse(
                    radius: 22,
                    onTap: () => ref
                        .read(pharmacyOrderBannerProvider.notifier)
                        .remove('${order['_id']}'),
                    child: const SizedBox(
                      width: 44,
                      height: 44,
                      child: Icon(LucideIcons.x, size: 18, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
