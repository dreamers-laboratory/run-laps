import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:laps/phone.dart';

void main() {
  test('the bell is 2.2 s, starts and ends silent, and never clips', () {
    final s = bell.buffer.asInt16List();
    expect(s.length, 97020);
    expect(s.first, 0);
    expect(s.last.abs(), lessThan(5));
    expect(s.map((v) => v.abs()).reduce((a, b) => a > b ? a : b), lessThan(32000));
    // no click: the strike rises over 12 ms, so the first millisecond is near silent
    expect(Int16List.sublistView(s, 0, 44).map((v) => v.abs()).reduce((a, b) => a > b ? a : b), lessThan(1000));
  });
}
