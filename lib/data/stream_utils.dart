/// Tiny stream combinators so repositories can derive one stream from two
/// watched queries without pulling in rxdart.
library;

import 'dart:async';

Stream<C> combine2<A, B, C>(
  Stream<A> a,
  Stream<B> b,
  C Function(A, B) combine,
) {
  late StreamController<C> controller;
  StreamSubscription<A>? subA;
  StreamSubscription<B>? subB;

  A? lastA;
  B? lastB;
  var hasA = false;
  var hasB = false;
  var busy = false;

  void emit() {
    if (busy) return;
    if (!hasA || !hasB) return;
    busy = true;
    controller.add(combine(lastA as A, lastB as B));
    busy = false;
  }

  controller = StreamController<C>(
    onListen: () {
      subA = a.listen(
        (v) {
          lastA = v;
          hasA = true;
          emit();
        },
        onError: controller.addError,
      );
      subB = b.listen(
        (v) {
          lastB = v;
          hasB = true;
          emit();
        },
        onError: controller.addError,
      );
    },
    onPause: () {
      subA?.pause();
      subB?.pause();
    },
    onResume: () {
      subA?.resume();
      subB?.resume();
    },
    onCancel: () async {
      await subA?.cancel();
      await subB?.cancel();
    },
  );

  return controller.stream;
}
