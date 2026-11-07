import 'package:flutter_test/flutter_test.dart';
import 'package:fitsync/features/admin/domain/admin_format.dart';

void main() {
  group('formatPhp', () {
    test('whole pesos have no decimals and group thousands', () {
      expect(formatPhp(1788), '₱1,788');
      expect(formatPhp(0), '₱0');
      expect(formatPhp(249), '₱249');
      expect(formatPhp(1000000), '₱1,000,000');
    });

    test('centavos show two decimals', () {
      expect(formatPhp(1788.5), '₱1,788.50');
      expect(formatPhp(0.05), '₱0.05');
    });

    test('a negative amount leads with a real minus sign', () {
      expect(formatPhp(-249), '−₱249');
      expect(formatPhp(-1788.5), '−₱1,788.50');
    });
  });

  test('signedCount', () {
    expect(signedCount(3), '+3');
    expect(signedCount(-2), '−2');
    expect(signedCount(0), '0');
    expect(signedCount(1204), '+1,204');
  });

  test('signedPhp', () {
    expect(signedPhp(747), '+₱747');
    expect(signedPhp(-249), '−₱249');
    expect(signedPhp(0), '₱0');
  });

  test('lastActiveLabel', () {
    expect(lastActiveLabel('2026-11-07', '2026-11-07'), 'active today');
    expect(lastActiveLabel('2026-11-06', '2026-11-07'), 'active 1 d ago');
    expect(lastActiveLabel('2026-10-26', '2026-11-07'), 'active 12 d ago');
    expect(lastActiveLabel(null, '2026-11-07'), 'not active yet');
    // Across a year end.
    expect(lastActiveLabel('2025-12-31', '2026-01-01'), 'active 1 d ago');
  });

  test('monthLabel', () {
    expect(monthLabel('2026-11'), 'November 2026');
    expect(monthLabel('2027-01'), 'January 2027');
  });

  test('joinedLabel', () {
    expect(joinedLabel('2026-11-05'), 'Joined 5 Nov 2026');
    expect(joinedLabel('2026-01-20'), 'Joined 20 Jan 2026');
  });

  test('the nine food types read as plain words, in order', () {
    expect(foodTypeLabels, {
      'home': 'Home-cooked',
      'fruit_veg': 'Fruit & veg',
      'bread_kakanin': 'Bread & kakanin',
      'canned_instant': 'Canned & instant',
      'drink': 'Drink',
      'street': 'Street food',
      'snack_sweet': 'Snack & sweet',
      'fast_food': 'Fast food',
      'condiment': 'Condiment',
    });
    expect(foodTypeLabels.keys.first, 'home');
    expect(foodTypeLabels.keys.last, 'condiment');
  });

  test('mediaUrl joins with exactly one slash', () {
    expect(
      mediaUrl('http://10.0.2.2:3000', '/storage/exercises/1/demo.gif'),
      'http://10.0.2.2:3000/storage/exercises/1/demo.gif',
    );
    expect(
      mediaUrl('http://10.0.2.2:3000', 'storage/exercises/1/demo.gif'),
      'http://10.0.2.2:3000/storage/exercises/1/demo.gif',
    );
  });
}
