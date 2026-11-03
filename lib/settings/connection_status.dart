import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';

/// Whether the device has a network, for the AI features that call a provider.
///
/// The platform only reports whether Wi-Fi or mobile data is on, not whether
/// the provider can be reached, so a request can still fail while this says
/// online.
class ConnectionStatus extends ChangeNotifier {
  ConnectionStatus({this._online = true});

  /// Follows the platform's connectivity reports.
  factory ConnectionStatus.watchPlatform() {
    final status = ConnectionStatus();
    final connectivity = Connectivity();
    unawaited(connectivity.checkConnectivity().then(status._onResults));
    status._subscription = connectivity.onConnectivityChanged.listen(
      status._onResults,
    );
    return status;
  }

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _online;
  bool _bannerDismissed = false;

  bool get isOnline => _online;

  /// Whether the "You're offline" banner should show. Dismissing it lasts
  /// until the device goes offline again.
  bool get showOfflineBanner => !_online && !_bannerDismissed;

  set isOnline(bool online) {
    if (online == _online) return;
    _online = online;
    if (online) _bannerDismissed = false;
    notifyListeners();
  }

  void dismissOfflineBanner() {
    if (_bannerDismissed) return;
    _bannerDismissed = true;
    notifyListeners();
  }

  void _onResults(List<ConnectivityResult> results) {
    isOnline = results.any((result) => result != ConnectivityResult.none);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// Makes [ConnectionStatus] available to every screen, rebuilding them when
/// it changes.
class ConnectionScope extends InheritedNotifier<ConnectionStatus> {
  const ConnectionScope({
    super.key,
    required ConnectionStatus status,
    required super.child,
  }) : super(notifier: status);

  static ConnectionStatus of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ConnectionScope>()!.notifier!;
}
