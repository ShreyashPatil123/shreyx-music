import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Tab navigation history stack logic', () {
    final history = <int>[0];

    void onTabTapped(int idx) {
      if (history.isNotEmpty && history.last == idx) return;
      history.remove(idx);
      history.add(idx);
    }

    bool onBackPress() {
      if (history.length > 1) {
        history.removeLast();
        return false; // Handled internally
      }
      return true; // Root reached, minimize app
    }

    // Initial state: on Discover (0)
    expect(history.last, equals(0));
    expect(onBackPress(), isTrue); // On root: minimize

    // Navigate to Search (1)
    onTabTapped(1);
    expect(history, equals([0, 1]));

    // Navigate to The Vault (2)
    onTabTapped(2);
    expect(history, equals([0, 1, 2]));

    // Back press 1: returns to Search (1)
    expect(onBackPress(), isFalse);
    expect(history.last, equals(1));

    // Back press 2: returns to Discover (0)
    expect(onBackPress(), isFalse);
    expect(history.last, equals(0));

    // Back press 3: on root! Triggers minimize without exiting
    expect(onBackPress(), isTrue);
  });
}
