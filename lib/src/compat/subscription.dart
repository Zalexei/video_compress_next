// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
import 'dart:async';
import 'dart:ui';

/// The progress stream holder of `video_compress`. One listener at a time:
/// call [Subscription.unsubscribe] before subscribing again.
class ObservableBuilder<T> {
  StreamController<T> _observable = StreamController();

  /// True until the first [subscribe].
  bool notSubscribed = true;

  /// Sends [value] to the listener.
  void next(T value) {
    if (!_observable.isClosed) _observable.add(value);
  }

  /// Starts listening; [Subscription.unsubscribe] stops it.
  Subscription subscribe(
    void Function(T event) onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    notSubscribed = false;
    _observable.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
    return Subscription(() {
      _observable.close();
      _observable = StreamController();
    });
  }
}

/// Returned by [ObservableBuilder.subscribe].
class Subscription {
  const Subscription(this.unsubscribe);

  /// Stops the listener and makes the builder ready for a new one.
  final VoidCallback unsubscribe;
}
