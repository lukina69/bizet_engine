import 'package:bizet_engine/bizet_engine.dart';
import 'package:test/test.dart';

void main() {
  group('catalogue', () {
    test('chaque tessiture est à l\'endroit et assez large pour une mélodie',
        () {
      for (final Instrument i in catalogue) {
        expect(i.noteMin, lessThan(i.noteMax), reason: i.nom);
        expect(i.etendue, greaterThanOrEqualTo(12),
            reason: '${i.nom} : moins d\'une octave, aucune mélodie n\'y tient');
      }
    });

    test('un numéro de programme n\'apparaît qu\'une fois', () {
      final Set<int> vus = {};
      for (final Instrument i in catalogue) {
        expect(vus.add(i.programme), isTrue,
            reason: 'programme ${i.programme} en double');
      }
    });

    test('la table est rangée par numéro de programme', () {
      for (int n = 1; n < catalogue.length; n++) {
        expect(catalogue[n].programme, greaterThan(catalogue[n - 1].programme));
      }
    });

    test('l\'accès par programme trouve, ou dit franchement que non', () {
      expect(instrumentParProgramme(40)!.nom, 'Violin');
      expect(instrumentParProgramme(1), isNull,
          reason: 'le piano brillant n\'est pas au catalogue');
    });

    test('le registre découle du centre de la tessiture', () {
      expect(instrumentParProgramme(58)!.registre, Registre.grave,
          reason: 'le tuba');
      expect(instrumentParProgramme(24)!.registre, Registre.medium,
          reason: 'la guitare nylon');
      expect(instrumentParProgramme(10)!.registre, Registre.aigu,
          reason: 'la boîte à musique');
    });
  });
}
