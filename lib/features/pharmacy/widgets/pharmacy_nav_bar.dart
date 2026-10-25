import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/pharmacy_colors.dart';
import '../theme/pharmacy_type.dart';
import 'module_accent.dart';
import 'pharmacy_motion.dart';

class PharmacyNavItem {
  final IconData icon;
  final String label;
  final int badge;

  const PharmacyNavItem(this.icon, this.label, {this.badge = 0});
}

/// The dashboard's bottom bar (pharmacy, and any module passing [items]).
///
/// The active tab grows into a tinted pill carrying its label; the others
/// stay icon-only. The pill's width and colour animate between tabs, so the
/// selection visibly travels instead of jumping. The Orders tab carries a
/// live count of orders waiting on the store.
class PharmacyNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final int awaitingOrders;

  /// Tabs for another module; the pharmacy's tabs when null.
  final List<PharmacyNavItem>? items;

  const PharmacyNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.awaitingOrders = 0,
    this.items,
  });

  List<PharmacyNavItem> get _items =>
      items ??
      [
        const PharmacyNavItem(LucideIcons.house, 'Home'),
        PharmacyNavItem(
          LucideIcons.clipboardList,
          'Orders',
          badge: awaitingOrders,
        ),
        const PharmacyNavItem(LucideIcons.pill, 'Medicines'),
        const PharmacyNavItem(LucideIcons.wallet, 'Earnings'),
        const PharmacyNavItem(LucideIcons.circleUserRound, 'Profile'),
      ];

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Container(
      decoration: const BoxDecoration(
        color: PharmacyColors.bg,
        border: Border(top: BorderSide(color: PharmacyColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          // A fixed height is required: a Scaffold lets its bottom bar be as
          // tall as the screen, and each button centres itself, so without
          // this the bar filled the whole screen and hid every tab's page.
          child: SizedBox(
            height: 46,
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    // The active item takes more room so its label fits.
                    flex: i == currentIndex ? 2 : 1,
                    child: _NavButton(
                      item: items[i],
                      selected: i == currentIndex,
                      onTap: () => onTap(i),
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

class _NavButton extends StatelessWidget {
  final PharmacyNavItem item;
  final bool selected;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? ModuleAccent.of(context).color
        : PharmacyColors.textTertiary;
    return PharmacyPressable(
      scale: 0.92,
      onTap: onTap,
      semanticLabel: item.badge > 0
          ? '${item.label}, ${item.badge} waiting'
          : item.label,
      child: Center(
        child: AnimatedContainer(
          duration: PharmacyMotion.medium,
          curve: PharmacyMotion.enter,
          height: 42,
          padding: EdgeInsets.symmetric(horizontal: selected ? 12 : 0),
          decoration: BoxDecoration(
            color: selected
                ? ModuleAccent.of(context).veryLight
                : Colors.transparent,
            borderRadius: BorderRadius.circular(21),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _badged(
                AnimatedScale(
                  scale: selected ? 1.08 : 1,
                  duration: PharmacyMotion.medium,
                  curve: PharmacyMotion.settle,
                  child: Icon(item.icon, size: 21, color: color),
                ),
              ),
              // Label slides open on the active tab only. Flexible so that on a
              // narrow phone a long label ("Medicines") shrinks and fades
              // instead of overflowing its slot.
              Flexible(
                child: AnimatedSize(
                  duration: PharmacyMotion.medium,
                  curve: PharmacyMotion.enter,
                  child: selected
                      ? Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Text(
                            item.label,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: PharmacyType.sans(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: ModuleAccent.of(context).color,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _badged(Widget icon) {
    if (item.badge <= 0) return icon;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -8,
          top: -6,
          child: TweenAnimationBuilder<double>(
            // Pops in when the count first appears or changes.
            key: ValueKey(item.badge),
            tween: Tween(begin: 0.4, end: 1),
            duration: PharmacyMotion.medium,
            curve: PharmacyMotion.settle,
            builder: (_, s, child) => Transform.scale(scale: s, child: child),
            child: Container(
              constraints: const BoxConstraints(minWidth: 17),
              height: 17,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: PharmacyColors.error,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: PharmacyColors.bg, width: 1.5),
              ),
              child: Text(
                item.badge > 99 ? '99+' : '${item.badge}',
                style: PharmacyType.number(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
