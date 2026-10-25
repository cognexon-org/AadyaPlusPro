import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../doctor/widgets/doctor_ui.dart';

/// The `physio` object out of a GET/PUT /physio/me/profile response.
Map<String, dynamic> physioFromResponse(dynamic body) {
  if (body is! Map) return const {};
  final raw = body['physio'] ?? body['data'] ?? body['profile'];
  return raw is Map ? Map<String, dynamic>.from(raw) : const {};
}

/// The signed-in physiotherapist's own profile (GET/PUT /physio/me/profile),
/// shared by the Profile tab and its settings screens so one save is seen
/// everywhere. Unlike the doctor side there is no GET availability endpoint:
/// the weekly hours live in `profile['availability']`.
class PhysioProfileState {
  final Map<String, dynamic> profile;
  final bool isLoading;
  final bool isRefreshing;
  final String? error;
  final DateTime? loadedAt;
  final bool isSaving;

  const PhysioProfileState({
    this.profile = const {},
    this.isLoading = false,
    this.isRefreshing = false,
    this.error,
    this.loadedAt,
    this.isSaving = false,
  });

  bool get hasLoaded => loadedAt != null;

  String? get physioId {
    final id = profile['_id'];
    return id == null || '$id'.isEmpty ? null : '$id';
  }

  /// The raw `availability` list, or null when the profile isn't loaded.
  List<dynamic>? get availability {
    if (!hasLoaded) return null;
    final a = profile['availability'];
    return a is List ? a : const [];
  }

  PhysioProfileState copyWith({
    Map<String, dynamic>? profile,
    bool? isLoading,
    bool? isRefreshing,
    String? error,
    bool clearError = false,
    DateTime? loadedAt,
    bool? isSaving,
  }) => PhysioProfileState(
    profile: profile ?? this.profile,
    isLoading: isLoading ?? this.isLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    error: clearError ? null : (error ?? this.error),
    loadedAt: loadedAt ?? this.loadedAt,
    isSaving: isSaving ?? this.isSaving,
  );
}

class PhysioProfileNotifier extends StateNotifier<PhysioProfileState> {
  PhysioProfileNotifier() : super(const PhysioProfileState());

  final _api = ApiService();
  int _seq = 0;
  Future<void>? _inFlight;

  String? get physioId => state.physioId;

  /// Fetches the profile. Shows the skeleton only on the very first load;
  /// afterwards (or when [silent]) it refreshes behind the current data.
  Future<void> load({bool silent = false}) {
    final f = _load(silent: silent);
    _inFlight = f;
    return f.whenComplete(() {
      if (identical(_inFlight, f)) _inFlight = null;
    });
  }

  Future<void> _load({required bool silent}) async {
    final seq = ++_seq;
    state = state.hasLoaded || silent
        ? state.copyWith(isRefreshing: true, clearError: true)
        : state.copyWith(isLoading: true, clearError: true);
    try {
      final res = await _api.getPhysioProfile();
      if (seq != _seq || !mounted) return;
      final p = physioFromResponse(res.data);
      if (p.isEmpty) throw StateError('empty profile');
      state = state.copyWith(
        profile: p,
        isLoading: false,
        isRefreshing: false,
        loadedAt: DateTime.now(),
      );
    } catch (e) {
      if (seq != _seq || !mounted) return;
      state = state.copyWith(
        isLoading: false,
        isRefreshing: false,
        error: doctorError(e, fallback: 'Couldn’t load your profile.'),
      );
    }
  }

  /// Loads the profile unless it already has been (joins a load in flight).
  Future<void> ensureLoaded() {
    if (state.hasLoaded) return Future.value();
    return _inFlight ?? load();
  }

  /// The physio's profile id, loading the profile first if needed.
  Future<String> physioIdOrLoad() async {
    if (physioId == null) await ensureLoaded();
    final id = physioId;
    if (id == null) {
      throw StateError(state.error ?? 'Couldn’t load your profile.');
    }
    return id;
  }

  /// Saves [body] with PUT /physio/me/profile and returns the fresh profile.
  /// Errors are rethrown for the screen to show.
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> body) async {
    state = state.copyWith(isSaving: true);
    try {
      final res = await _api.updatePhysioProfile(body);
      final fresh = physioFromResponse(res.data);
      if (fresh.isNotEmpty) {
        if (mounted) {
          // Drop any older GET still in flight so it can't undo the save.
          _seq++;
          state = state.copyWith(
            profile: {...state.profile, ...fresh},
            isRefreshing: false,
            clearError: true,
            loadedAt: DateTime.now(),
          );
        }
        // The PUT response carries the raw flags; GET resolves missing
        // home/video flags from the fees, so re-read quietly.
        if (mounted) load(silent: true);
      } else {
        await load(silent: true);
      }
      return mounted ? state.profile : fresh;
    } finally {
      if (mounted) state = state.copyWith(isSaving: false);
    }
  }

  /// Saves the whole week with PUT /physio/me/availability. Errors are
  /// rethrown.
  Future<void> saveAvailability(List<dynamic> availabilityJson) async {
    state = state.copyWith(isSaving: true);
    try {
      final res = await _api.updatePhysioAvailability({
        'availability': availabilityJson,
      });
      if (!mounted) return;
      final data = res.data;
      final saved = data is Map && data['availability'] is List
          ? data['availability'] as List
          : availabilityJson;
      _seq++;
      state = state.copyWith(
        profile: {...state.profile, 'availability': saved},
        isRefreshing: false,
      );
    } finally {
      if (mounted) state = state.copyWith(isSaving: false);
    }
  }
}

/// Global so the profile survives tab switches; rebuilt when the signed-in
/// user changes so one physio never sees another's cached profile.
final physioProfileProvider =
    StateNotifierProvider<PhysioProfileNotifier, PhysioProfileState>((ref) {
      ref.watch(authProvider.select((s) => s.user?.id));
      return PhysioProfileNotifier();
    });

// ─────────────────────────── Treatment packages ───────────────────────────

/// The physio's treatment packages (GET /physio-care/me/packages with
/// archived ones included), newest first.
class PhysioPackagesState {
  final List<Map<String, dynamic>> packages;
  final bool isLoading;
  final String? error;
  final DateTime? loadedAt;

  const PhysioPackagesState({
    this.packages = const [],
    this.isLoading = false,
    this.error,
    this.loadedAt,
  });

  bool get hasLoaded => loadedAt != null;

  static bool isActive(Map<String, dynamic> p) => p['isActive'] != false;

  List<Map<String, dynamic>> get active =>
      packages.where(isActive).toList(growable: false);
  List<Map<String, dynamic>> get archived =>
      packages.where((p) => !isActive(p)).toList(growable: false);
}

class PhysioPackagesNotifier extends StateNotifier<PhysioPackagesState> {
  PhysioPackagesNotifier() : super(const PhysioPackagesState());

  final _api = ApiService();
  int _seq = 0;

  static Map<String, dynamic> _one(dynamic body) {
    if (body is! Map) return const {};
    final raw = body['package'] ?? body['data'];
    return raw is Map ? Map<String, dynamic>.from(raw) : const {};
  }

  Future<void> load() async {
    final seq = ++_seq;
    state = PhysioPackagesState(
      packages: state.packages,
      isLoading: true,
      loadedAt: state.loadedAt,
    );
    try {
      final res = await _api.getPhysioPackages(includeInactive: true);
      if (seq != _seq || !mounted) return;
      final body = res.data;
      final raw = body is Map ? (body['packages'] ?? body['data']) : body;
      final list = raw is List
          ? [
              for (final e in raw)
                if (e is Map) Map<String, dynamic>.from(e),
            ]
          : <Map<String, dynamic>>[];
      state = PhysioPackagesState(packages: list, loadedAt: DateTime.now());
    } catch (e) {
      if (seq != _seq || !mounted) return;
      state = PhysioPackagesState(
        packages: state.packages,
        loadedAt: state.loadedAt,
        error: doctorError(e, fallback: 'Couldn’t load your packages.'),
      );
    }
  }

  void _put(Map<String, dynamic> pkg, {String? id}) {
    if (!mounted || pkg.isEmpty) return;
    final key = id ?? '${pkg['_id']}';
    final list = [...state.packages];
    final i = list.indexWhere((p) => '${p['_id']}' == key);
    if (i >= 0) {
      list[i] = {...list[i], ...pkg};
    } else {
      list.insert(0, pkg);
    }
    _seq++;
    state = PhysioPackagesState(
      packages: list,
      loadedAt: state.loadedAt ?? DateTime.now(),
    );
  }

  /// Errors are rethrown for the sheet to show.
  Future<void> create(Map<String, dynamic> body) async {
    final res = await _api.createPhysioPackage(body);
    final pkg = _one(res.data);
    if (pkg.isEmpty) {
      await load();
    } else {
      _put(pkg);
    }
  }

  Future<void> update(String id, Map<String, dynamic> body) async {
    final res = await _api.updatePhysioPackage(id, body);
    final pkg = _one(res.data);
    _put(pkg.isEmpty ? {...body, '_id': id} : pkg, id: id);
  }

  /// Hides the package from patients; courses already sold keep running.
  Future<void> archive(String id) async {
    await _api.archivePhysioPackage(id);
    _put({'_id': id, 'isActive': false}, id: id);
  }

  Future<void> restore(String id) => update(id, {'isActive': true});
}

final physioPackagesProvider =
    StateNotifierProvider<PhysioPackagesNotifier, PhysioPackagesState>((ref) {
      ref.watch(authProvider.select((s) => s.user?.id));
      return PhysioPackagesNotifier();
    });
