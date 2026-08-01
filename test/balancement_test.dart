import 'package:test/test.dart';

import 'package:bizet_engine/bizet_engine.dart';

void main() {
  group('Balancement', () {
    test('à 0 %, rien ne bouge', () {
      const b = Balancement();
      expect(b.estDroit, isTrue);
      for (final double t in [0.0, 0.25, 0.5, 0.75, 1.0, 7.5, 12.375]) {
        expect(b.applique(t), t, reason: 't = $t');
      }
    });

    test('les temps ne bougent jamais, quel que soit le réglage', () {
      // Si un début de temps se décalait, le morceau entier glisserait.
      for (final int pourcentage in [10, 50, 100]) {
        final b = Balancement(pourcentage);
        for (final double t in [0.0, 1.0, 2.0, 17.0]) {
          expect(b.applique(t), closeTo(t, 1e-12),
              reason: '$pourcentage % à t = $t');
        }
      }
    });

    test('à fond, la croche faible tombe aux deux tiers du temps', () {
      const b = Balancement(Balancement.maximum);
      expect(b.pivot, closeTo(2 / 3, 1e-12));
      expect(b.applique(0.5), closeTo(2 / 3, 1e-12));
      expect(b.applique(3.5), closeTo(3 + 2 / 3, 1e-12));
    });

    test('le retard est proportionnel au réglage', () {
      // La moitié du balancement doit donner la moitié du retard.
      const complet = Balancement(100);
      const moitie = Balancement(50);
      expect(moitie.applique(0.5) - 0.5,
          closeTo((complet.applique(0.5) - 0.5) / 2, 1e-12));
    });

    test('les doubles croches suivent le mouvement sans traitement à part', () {
      const b = Balancement(Balancement.maximum);
      // Avant la croche faible, le temps s'étire ; après, il se resserre.
      expect(b.applique(0.25), closeTo(1 / 3, 1e-12));
      expect(b.applique(0.75), closeTo(5 / 6, 1e-12));
    });

    test('rien ne franchit jamais le temps suivant', () {
      // Sinon deux notes pourraient se croiser, et l'ordre des événements
      // envoyés au synthétiseur n'aurait plus de sens.
      const b = Balancement(Balancement.maximum);
      double precedent = -1;
      for (int i = 0; i <= 100; i++) {
        final double t = i / 100;
        final double place = b.applique(t);
        expect(place, greaterThanOrEqualTo(precedent));
        expect(place, lessThanOrEqualTo(1.0));
        precedent = place;
      }
    });
  });
}
