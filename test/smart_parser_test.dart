import 'package:flutter_test/flutter_test.dart';
import 'package:vaulty/data/memory_repository.dart';
import 'package:vaulty/models/memory.dart';
import 'package:vaulty/services/smart_parser.dart';

void main() {
  final parser = SmartParser(now: DateTime(2026, 9, 23));

  String? field(ParsedCapture p, String key) => p.fields.where((f) => f.$1 == key).map((f) => f.$2).firstOrNull;

  test('spec example: car insurance with policy number', () {
    final p = parser.parseText('Car insurance expires Nov 12, Policy #9812');
    expect(p.title, 'Car Insurance');
    expect(p.expiry, DateTime(2026, 11, 12));
    expect(field(p, 'Policy #'), '9812');
    expect(p.category, MemoryCategory.expiryDoc);
  });

  test('month without year rolls to next occurrence', () {
    final p = parser.parseText('Gym membership renews March 3');
    expect(p.expiry, DateTime(2027, 3, 3));
    expect(p.category, MemoryCategory.subscription);
    expect(p.title, 'Gym Membership');
  });

  test('shoe size becomes a measurement', () {
    final p = parser.parseText("Mom's shoe size 7.5 US");
    expect(p.title, "Mom's Shoe Size");
    expect(field(p, 'Size'), '7.5 US');
    expect(p.category, MemoryCategory.measurement);
    expect(p.expiry, isNull);
  });

  test('colon pair with no prefix uses key as title', () {
    final p = parser.parseText('Living room paint: Benjamin Moore Chantilly Lace OC-65');
    expect(p.title, 'Living Room Paint');
    expect(field(p, 'Living Room Paint'), 'Benjamin Moore Chantilly Lace OC-65');
    expect(p.category, MemoryCategory.staticFact);
  });

  test('wifi password is sensitive', () {
    final p = parser.parseText('Home wifi password is sunshine22');
    expect(p.title, 'Home Wifi Password');
    expect(field(p, 'Password'), 'sunshine22');
    expect(p.isSensitive, isTrue);
  });

  test('numeric dates and subscriptions with price', () {
    final p = parser.parseText(r'Netflix $15.49/mo renews on the 5th');
    expect(p.title, 'Netflix');
    expect(field(p, 'Price'), r'$15.49/mo');
    expect(p.expiry, DateTime(2026, 10, 5));
    expect(p.category, MemoryCategory.subscription);
  });

  test('passport with dd/mm/yyyy', () {
    final p = parser.parseText('Passport exp 15/03/2031 no K1234567');
    expect(p.title, 'Passport');
    expect(p.expiry, DateTime(2031, 3, 15));
  });

  test('relative dates', () {
    expect(parser.parseText('Milk expires in 3 days').expiry, DateTime(2026, 9, 26));
    expect(parser.parseText('Renew lease in 2 months').expiry, DateTime(2026, 11, 23));
  });

  test('ocr passport picks future date and doc title', () {
    const ocr =
        'REPUBLIC OF INDIA\nPASSPORT\nPassport No: K1234567\n'
        'Date of Birth 12/05/1998\nDate of Issue 01/02/2021\nDate of Expiry 31/01/2031';
    final p = parser.parseOcr(ocr);
    expect(p.title, 'Passport');
    expect(p.expiry, DateTime(2031, 1, 31));
    expect(p.category, MemoryCategory.expiryDoc);
    expect(p.fields.any((f) => f.$2 == 'K1234567'), isTrue);
  });

  test('card-style MM/YY expiry', () {
    final p = parser.parseText('Visa card Exp: 10/28');
    expect(p.expiry, DateTime(2028, 10, 31));
  });

  test('relationship words become people', () {
    expect(parser.parseText("Mom's shoe size 7.5 US").people, ['Mom']);
    expect(parser.parseText('dad waist 34 in').people, ['Dad']);
  });

  test('possessive names and occasions become people', () {
    expect(parser.parseText("Priya's ring size 6").people, ['Priya']);
    final bday = parser.parseText('Joe Birthday 24th Sept');
    expect(bday.people, ['Joe']);
    expect(bday.expiry, DateTime(2026, 9, 24));
    expect(parser.parseText('Netflix renews on the 5th').people, isEmpty);
  });

  test('known people are matched anywhere', () {
    final p = SmartParser(now: DateTime(2026, 9, 23), knownPeople: ['Joe']);
    expect(p.parseText('gym locker code for joe 4412').people, ['Joe']);
  });

  test('hashtags become tags and leave the title', () {
    final p = parser.parseText('Car insurance expires Nov 12 #car #Renewals, Policy #9812');
    expect(p.tags, ['car', 'renewals']);
    expect(p.title, 'Car Insurance');
    expect(p.fields.where((f) => f.$1 == 'Policy #').single.$2, '9812');
    expect(parser.parseText('Wall paint #F4EFE6').tags, isEmpty);
  });

  test('search terms strip filler', () {
    expect(MemoryRepository.searchTerms("What's Mom's shoe size?"), ['mom', 'shoe', 'size']);
    expect(MemoryRepository.searchTerms('Passport expiry'), ['passport', 'exp']);
  });
}
