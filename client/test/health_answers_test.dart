import 'package:flutter_test/flutter_test.dart';

import 'package:fitsync/features/health/domain/health_answers.dart';

HealthAnswers _allNo(HealthAnswers a) => a
    .answer('chestPain', false)
    .answer('dizziness', false)
    .answer('supervisedOnly', false);

void main() {
  test('the wire values are pinned, in card order', () {
    expect([for (final c in healthConditions) c.value], [
      'high_blood_pressure',
      'heart_condition',
      'diabetes',
      'asthma',
      'pregnancy',
      'recent_surgery',
      'other',
    ]);
    expect([for (final q in healthQuestions) q.field], [
      'chestPain',
      'dizziness',
      'supervisedOnly',
    ]);
  });

  test('None of these clears the conditions, and a condition clears None', () {
    var a = const HealthAnswers().toggle('asthma').toggle('diabetes');
    expect(a.conditions, ['diabetes', 'asthma'], reason: 'card order');
    a = a.toggleNone();
    expect(a.conditions, isEmpty);
    expect(a.noneOfThese, isTrue);
    a = a.toggle('other');
    expect(a.noneOfThese, isFalse);
    expect(a.conditions, ['other']);
    expect(a.toggle('other').conditions, isEmpty, reason: 'toggles off');
  });

  test('incomplete answers are not valid', () {
    expect(const HealthAnswers().isValid, isFalse);
    expect(_allNo(const HealthAnswers()).isValid, isFalse,
        reason: 'no checklist choice yet');
    expect(const HealthAnswers().toggleNone().answer('chestPain', false).isValid,
        isFalse, reason: 'two questions unanswered');
  });

  test('a clear check is valid without the boxes', () {
    final a = _allNo(const HealthAnswers().toggleNone());
    expect(a.isPositive, isFalse);
    expect(a.isValid, isTrue);
  });

  test('a condition or any Yes is positive', () {
    expect(_allNo(const HealthAnswers().toggle('asthma')).isPositive, isTrue);
    final yes = _allNo(const HealthAnswers().toggleNone()).answer('dizziness', true);
    expect(yes.isPositive, isTrue);
    expect(yes.hasWarning, isTrue);
  });

  test('a positive check needs both boxes, or the opt-out', () {
    final a = _allNo(const HealthAnswers().toggle('asthma'));
    expect(a.isValid, isFalse);
    expect(a.withAcknowledged(true).isValid, isFalse);
    expect(a.withConsent(true).isValid, isFalse);
    expect(a.withAcknowledged(true).withConsent(true).isValid, isTrue);
    expect(a.withOptedOut(true).isValid, isTrue);
  });

  test('toJson sends the answers and both boxes', () {
    final a = _allNo(const HealthAnswers().toggle('asthma'))
        .answer('chestPain', true)
        .withAcknowledged(true)
        .withConsent(true);
    expect(a.toJson(), {
      'conditions': ['asthma'],
      'chestPain': true,
      'dizziness': false,
      'supervisedOnly': false,
      'consent': true,
      'acknowledged': true,
    });
  });

  test('fromJson reads a stored check back', () {
    final a = HealthAnswers.fromJson({
      'conditions': ['diabetes', 'high_blood_pressure'],
      'chestPain': false,
      'dizziness': true,
      'supervisedOnly': false,
      'consentedAt': '2026-10-07T01:00:00.000Z',
      'acknowledgedAt': '2026-10-07T01:00:00.000Z',
    });
    expect(a.conditions, ['high_blood_pressure', 'diabetes']);
    expect(a.noneOfThese, isFalse);
    expect(a.dizziness, isTrue);
    expect(a.acknowledged, isTrue);
    expect(a.consent, isTrue);
    expect(a.isValid, isTrue);

    final clear = HealthAnswers.fromJson({
      'conditions': <String>[],
      'chestPain': false,
      'dizziness': false,
      'supervisedOnly': false,
      'consentedAt': null,
      'acknowledgedAt': null,
    });
    expect(clear.noneOfThese, isTrue, reason: 'stored and empty means None');
    expect(clear.isValid, isTrue);
  });
}
