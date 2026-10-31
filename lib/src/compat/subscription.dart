// Copyright 2026 Alexei Zalogin. Use of this source code is governed by the MIT license in the LICENSE file.
import 'dart:async';
import 'dart:ui';

/// The progress stream holder of `video_compress`. One listener at a time:
/// call [Subscription.unsubscribe] before subscribing again.
class ObservableBuilder<T> {
  StreamController<T> _observable = StreamController();
  bool notSubscribed = true;

  void next(T value) {
    if (!_observable.isClosed) _observable.add(value);
  }

  Subscription subscribe(
    void Function(T event) onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    notSubscribed = false;
    _observable.stream.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
    return Subscription(() {
      _observable.close();
      _observable = StreamController();
    });
  }
}

class Subscription {
  const Subscription(this.unsubscribe);

  final VoidCallback unsubscribe;
}
