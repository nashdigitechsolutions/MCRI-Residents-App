import 'package:flutter_test/flutter_test.dart';
import 'package:mcri_residents_app/utils/linkify.dart';

void main() {
  List<String> links(String t) =>
      linkify(t).where((s) => s.isLink).map((s) => s.uri.toString()).toList();

  test('web links, with and without scheme, trailing punctuation dropped', () {
    expect(links('see https://mcriresidents.online/polls.'), ['https://mcriresidents.online/polls']);
    expect(links('menu at www.example.com/menu, thanks'), ['https://www.example.com/menu']);
    expect(links('(https://x.co/a)'), ['https://x.co/a']);
  });

  test('emails and phone numbers', () {
    expect(links('mail admin@mcri.co.zw now'), ['mailto:admin@mcri.co.zw']);
    expect(links('call +263 77 123 4567 or 077-123-4567'), ['tel:+263771234567', 'tel:0771234567']);
  });

  test('dates, times and amounts are not phone numbers', () {
    expect(links('on 2026-11-07 at 18:30, R 1500000'), isEmpty);
  });

  test('segments rebuild the original text exactly', () {
    const t = 'Hi! https://a.io and b@c.com, ok';
    expect(linkify(t).map((s) => s.text).join(), t);
  });
}
