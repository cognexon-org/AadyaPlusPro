import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../widgets/availability_save_bar.dart';
import '../widgets/doctor_ui.dart';

/// The signed-in doctor's own profile (GET/PUT /doctor/me/profile) and
/// weekly hours (GET/PUT /doctor/me/availability), shared by the Profile tab
/// and its settings screens so one save is seen everywhere.
class DoctorProfileState {
  final Map<String, dynamic> profile;

  /// The raw GET /doctor/me/availability body (availability, consultation
  /// types, slot length…), or null until fetched.
  final Map<String, dynamic>? availability;
  final bool isLoading;
  final bool isRefreshing;
  final String? error;
  final DateTime? loadedAt;
  final bool availabilityLoading;
  final String? availabilityError;
  final bool isSaving;

  const DoctorProfileState({
    this.profile = const {},
    this.availability,
    this.isLoading = false,
    this.isRefreshing = false,
    this.error,
    this.loadedAt,
    this.availabilityLoading = false,
    this.availabilityError,
    this.isSaving = false,
  });

  bool get hasLoaded => loadedAt != null;

  String? get doctorId {
    final id = profile['_id'];
    return id == null || '$id'.isEmpty ? null : '$id';
  }

  DoctorProfileState copyWith({
    Map<String, dynamic>? profile,
    Map<String, dynamic>? availability,
    bool clearAvailability = false,
    bool? isLoading,
    bool? isRefreshing,
    String? error,
    bool clearError = false,
    DateTime? loadedAt,
    bool? availabilityLoading,
    String? availabilityError,
    bool clearAvailabilityError = false,
    bool? isSaving,
  }) => DoctorProfileState(
    profile: profile ?? this.profile,
    availability: clearAvailability
        ? null
        : (availability ?? this.availability),
    isLoading: isLoading ?? this.isLoading,
    isRefreshing: isRefreshing ?? this.isRefreshing,
    error: clearError ? null : (error ?? this.error),
    loadedAt: loadedAt ?? this.loadedAt,
    availabilityLoading: availabilityLoading ?? this.availabilityLoading,
    availabilityError: clearAvailabilityError
        ? null
        : (availabilityError ?? this.availabilityError),
    isSaving: isSaving ?? this.isSaving,
  );
}

class DoctorProfileNotifier extends StateNotifier<DoctorProfileState> {
  DoctorProfileNotifier() : super(const DoctorProfileState());

  final _api = ApiService();
  int _seq = 0;
  int _availabilitySeq = 0;
  Future<void>? _inFlight;

  String? get doctorId => state.doctorId;

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
      final res = await _api.getDoctorProfile();
      if (seq != _seq || !mounted) return;
      final p = doctorFromResponse(res.data);
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

  /// The doctor's profile id, loading the profile first if needed.
  Future<String> doctorIdOrLoad() async {
    if (doctorId == null) await ensureLoaded();
    final id = doctorId;
    if (id == null) {
      throw StateError(state.error ?? 'Couldn’t load your profile.');
    }
    return id;
  }

  /// Saves [body] with PUT /doctor/me/profile and returns the fresh
  /// profile. Errors are rethrown for the screen to show.
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> body) async {
    state = state.copyWith(isSaving: true);
    try {
      final res = await _api.updateDoctorProfile(body);
      final fresh = doctorFromResponse(res.data);
      // Fees, visit types and slot length feed the availability body too.
      if (mounted) state = state.copyWith(clearAvailability: true);
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
      } else {
        await load(silent: true);
      }
      return mounted ? state.profile : fresh;
    } finally {
      if (mounted) state = state.copyWith(isSaving: false);
    }
  }

  /// The GET /doctor/me/availability body. Served from memory unless
  /// [force] or not fetched yet. Errors are rethrown.
  Future<Map<String, dynamic>> loadAvailability({bool force = false}) async {
    final cached = state.availability;
    if (!force && cached != null) return cached;
    final seq = ++_availabilitySeq;
    state = state.copyWith(
      availabilityLoading: true,
      clearAvailabilityError: true,
    );
    try {
      final res = await _api.getMyDoctorAvailability();
      final body = res.data;
      final map = body is Map
          ? Map<String, dynamic>.from(body)
          : <String, dynamic>{};
      if (seq == _availabilitySeq && mounted) {
        state = state.copyWith(availability: map, availabilityLoading: false);
      }
      return map;
    } catch (e) {
      if (seq == _availabilitySeq && mounted) {
        state = state.copyWith(
          availabilityLoading: false,
          availabilityError: doctorError(
            e,
            fallback: 'Couldn’t load your hours.',
          ),
        );
      }
      rethrow;
    }
  }

  /// Saves the whole week with PUT /doctor/me/availability. Errors are
  /// rethrown.
  Future<void> saveAvailability(List<dynamic> availabilityJson) async {
    state = state.copyWith(isSaving: true);
    try {
      final res = await _api.updateDoctorAvailability({
        'availability': availabilityJson,
      });
      if (!mounted) return;
      final data = res.data;
      final saved = data is Map && data['availability'] is List
          ? data['availability']
          : availabilityJson;
      _availabilitySeq++;
      state = state.copyWith(
        availability: {...?state.availability, 'availability': saved},
        availabilityLoading: false,
        clearAvailabilityError: true,
      );
    } finally {
      if (mounted) state = state.copyWith(isSaving: false);
    }
  }
}

/// Global so the profile survives tab switches; rebuilt when the signed-in
/// user changes so one doctor never sees another's cached profile.
final doctorProfileProvider =
    StateNotifierProvider<DoctorProfileNotifier, DoctorProfileState>((ref) {
      ref.watch(authProvider.select((s) => s.user?.id));
      return DoctorProfileNotifier();
    });
