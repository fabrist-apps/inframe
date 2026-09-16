import 'dart:async';

import 'package:runnel/src/errors.dart';

/// Owns child resources from the start of acquisition until release or handoff.
///
/// Each acquisition keeps one registration as its cleanup changes from a pending
/// connection attempt to an established connection or session. Closing the owner
/// prevents new acquisitions and starts every registered cleanup immediately.
final class ClientResources {
  final Set<ResourceRegistration> _resources = {};
  bool _closed = false;

  /// Registers ownership before an acquisition can suspend.
  ResourceRegistration register() {
    if (_closed) throw const RunnelClosedError('The Runnel client is closing.');
    final registration = ResourceRegistration._(this);
    _resources.add(registration);
    return registration;
  }

  /// Releases all current children; the ordinary connection drains separately.
  Future<void> close() {
    _closed = true;
    return Future.wait(List.of(_resources).map((resource) => resource.close()));
  }
}

/// One cleanup responsibility, retained across acquisition phases.
final class ResourceRegistration {
  ResourceRegistration._(this._owner);

  final ClientResources _owner;
  Future<void> Function()? _release;
  Future<void>? _closing;
  bool _detached = false;

  /// Rejects a late acquisition after cancellation or owner shutdown.
  void checkOpen() {
    if (_detached || _owner._closed) {
      throw const RunnelClosedError('The resource acquisition was closed.');
    }
  }

  /// Changes cleanup after a synchronous ownership handoff.
  ///
  /// The caller must release its newly acquired resource if this rejects it.
  void replace(Future<void> Function() release) {
    checkOpen();
    _release = release;
  }

  /// Removes a released resource, or transfers it to the ordinary connection.
  void detach() {
    _detached = true;
    _release = null;
    _owner._resources.remove(this);
  }

  /// Releases at most once, sharing in-progress cleanup with concurrent callers.
  Future<void> close() => _closing ??= _close();

  Future<void> _close() async {
    final release = _release;
    detach();
    await release?.call();
  }
}
