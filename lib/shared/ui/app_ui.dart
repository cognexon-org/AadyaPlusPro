/// The app-wide UI kit under neutral names.
///
/// The kit was built for the pharmacy module first, so its classes are still
/// called Pharmacy*. Every module now uses it — with its own accent via
/// [ModuleTheme] — so new code imports this file and uses the App* names.
/// They are aliases of the same classes, not copies: a fix in the kit
/// reaches every module. (A mechanical rename of the originals can replace
/// these aliases later.)
library;

import 'package:flutter/material.dart';

import '../../features/pharmacy/theme/pharmacy_colors.dart';
import '../../features/pharmacy/theme/pharmacy_type.dart';
import '../../features/pharmacy/widgets/pharmacy_nav_bar.dart';
import '../../features/pharmacy/widgets/pharmacy_ui.dart';

export '../../features/pharmacy/widgets/module_accent.dart';

// Tokens
typedef AppColors = PharmacyColors;
typedef AppType = PharmacyType;
typedef AppMotion = PharmacyMotion;

// Layout and surfaces
typedef AppScreenHeader = PharmacyScreenHeader;
typedef AppCard = PharmacyCard;
typedef AppGroup = PharmacyGroup;
typedef AppHairline = PharmacyHairline;
typedef AppSectionTitle = PharmacySectionTitle;
typedef AppMetricTile = PharmacyMetricTile;
typedef AppStatusPill = PharmacyStatusPill;
typedef AppFilterChip = PharmacyFilterChip;
typedef AppIconBadge = PharmacyIconBadge;

// States
typedef AppShimmer = PharmacyShimmer;
typedef AppSkeletonBlock = PharmacySkeletonBlock;
typedef AppListSkeleton = PharmacyListSkeleton;
typedef AppDetailSkeleton = PharmacyDetailSkeleton;
typedef AppFormSkeleton = PharmacyFormSkeleton;
typedef AppLoading = PharmacyLoading;
typedef AppErrorBanner = PharmacyErrorBanner;
typedef AppEmptyState = PharmacyEmptyStateInline;
typedef AppOfflineBanner = PharmacyOfflineBanner;

// Inputs and actions
typedef AppTextField = PharmacyTextField;
typedef AppDropdownField<T> = PharmacyDropdownField<T>;
typedef AppSwitch = PharmacySwitch;
typedef AppSwitchRow = PharmacySwitchRow;
typedef AppPickerField = PharmacyPickerField;
typedef AppSearchField = PharmacySearchField;
typedef AppButton = PharmacyButton;
typedef AppSecondaryButton = PharmacySecondaryButton;
typedef AppFab = PharmacyFab;
typedef AppModal = PharmacyDialog;

// Motion
typedef AppEntrance = PharmacyEntrance;
typedef AppPressable = PharmacyPressable;
typedef AppCountUp = PharmacyCountUp;
typedef AppPulse = PharmacyPulse;
typedef AppGrowBar = PharmacyGrowBar;
typedef AppScrollScope = PharmacyScrollScope;
typedef AppPageRoute<T> = PharmacyPageRoute<T>;

// Navigation
typedef AppNavBar = PharmacyNavBar;
typedef AppNavItem = PharmacyNavItem;

// Helpers
String appRupees(dynamic value) => pharmacyRupees(value);
String appErrorMessage(Object? error, {required String fallback}) =>
    pharmacyErrorMessage(error, fallback: fallback);
void showAppError(BuildContext context, Object? error, {String? fallback}) =>
    showPharmacyError(
      context,
      error,
      fallback: fallback ?? 'Something went wrong. Please try again.',
    );
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) => showPharmacySheet<T>(context, builder: builder);
