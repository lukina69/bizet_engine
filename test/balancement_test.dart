import 'package:test/test.dart';

import 'package:bizet_engine/bizet_engine.dart';

void main() {
  group('Swing', () {
    test('chaque cran balance ce qu\'il annonce', () {
      // Le pivot est la part de la paire laissée à la première note.
      const attendus = {
        Swing.droit: 0.500,
        Swing.leger: 0.580,
        Swing.ternaire: 0.667,
        Swing.pointe: 0.750,
      };

      for (final entree in attendus.entries) {
        expect(Balancement(entree.key).pivot, closeTo(entree.value, 1e-12),
            reason: entree.key.name);
      }
    });

    test('les crans vont en s\'accentuant, sans jamais franchir le suivant',
        () {
      double precedent = 0.0;
      for (final Swing cran in Swing.values) {
        final double pivot = Balancement(cran).pivot;
        expect(pivot, greaterThan(precedent), reason: cran.name);
        expect(pivot, lessThan(1.0), reason: cran.name);
        precedent = pivot;
      }
    });

    test('un nom relu retrouve son cran, un nom inconnu revient au droit', () {
      for (final Swing cran in Swing.values) {
        expect(Swing.depuisNom(cran.name), cran);
      }
      expect(Swing.depuisNom(null), Swing.droit);
      expect(Swing.depuisNom(''), Swing.droit);
      expect(Swing.depuisNom('shuffle'), Swing.droit);
    });
  });

  group('Balancement', () {
    test('au cran droit, rien ne bouge', () {
      const b = Balancement();
      expect(b.swing, Swing.droit);
      expect(b.estDroit, isTrue);
      for (final double t in [0.0, 0.25, 0.5, 0.75, 1.0, 7.5, 12.375]) {
        expect(b.applique(t), t, reason: 't = $t');
      }
    });

    test('les temps ne bougent jamais, quel que soit le cran', () {
      // Si un début de temps se décalait, le morceau entier glisserait.
      for (final Swing cran in Swing.values) {
        final b = Balancement(cran);
        for (final double t in [0.0, 1.0, 2.0, 17.0]) {
          expect(b.applique(t), closeTo(t, 1e-12),
              reason: '${cran.name} à t = $t');
        }
      }
    });

    test('au ternaire, la croche faible tombe aux deux tiers du temps', () {
      const b = Balancement(Swing.ternaire);
      expect(b.applique(0.5), closeTo(0.667, 1e-12));
      expect(b.applique(3.5), closeTo(3.667, 1e-12));
    });

    test('au pointé, la croche faible tombe aux trois quarts', () {
      const b = Balancement(Swing.pointe);
      expect(b.applique(0.5), closeTo(0.75, 1e-12));
    });

    test('les doubles croches suivent le mouvement sans traitement à part', () {
      const b = Balancement(Swing.ternaire);
      // Avant la croche faible, le temps s'étire ; après, il se resserre.
      expect(b.applique(0.25), closeTo(0.667 / 2, 1e-12));
      expect(b.applique(0.75), closeTo(0.667 + (1 - 0.667) / 2, 1e-12));
    });

    test('rien ne franchit jamais le temps suivant', () {
      // Sinon deux notes pourraient se croiser, et l'ordre des événements
      // envoyés au synthétiseur n'aurait plus de sens.
      for (final Swing cran in Swing.values) {
        final b = Balancement(cran);
        double precedent = -1;
        for (int i = 0; i <= 100; i++) {
          final double place = b.applique(i / 100);
          expect(place, greaterThanOrEqualTo(precedent), reason: cran.name);
          expect(place, lessThanOrEqualTo(1.0), reason: cran.name);
          precedent = place;
        }
      }
    });

    test('balancer deux fois le même matériau donne le même résultat', () {
      // Le calcul part de l'instant écrit : rien ne s'accumule d'un appel à
      // l'autre, sans quoi rejouer un morceau le déformerait un peu plus à
      // chaque fois.
      const b = Balancement(Swing.pointe, 1.0);
      final List<double> ecrits = [
        for (int i = 0; i <= 32; i++) i / 4,
      ];

      final List<double> premier = ecrits.map(b.applique).toList();
      final List<double> second = ecrits.map(b.applique).toList();
      expect(second, premier);
    });

    test('le même cran s\'applique à une autre fenêtre', () {
      const b = Balancement(Swing.ternaire);
      final Balancement large = b.surFenetre(2.0);
      expect(large.swing, Swing.ternaire);
      expect(large.applique(1.0), closeTo(2 * 0.667, 1e-12));
    });
  });

  group('Migration du swing enregistré', () {
    test('les anciens pourcentages retrouvent le cran le plus proche', () {
      // L'ancien réglage allait de 0,5 (droit) à 0,667 (ternaire) en droite
      // ligne : le pointé n'était pas atteignable, aucune ancienne valeur n'y
      // mène donc.
      const attendus = {
        0: Swing.droit,
        10: Swing.droit,
        23: Swing.droit,
        24: Swing.leger, // à mi-chemin : le plus balancé l'emporte
        50: Swing.leger,
        74: Swing.leger,
        75: Swing.ternaire,
        100: Swing.ternaire,
      };

      for (final entree in attendus.entries) {
        expect(Swing.depuisPourcentage(entree.key), entree.value,
            reason: '${entree.key} %');
      }
    });

    test('une valeur absente ou hors plage revient au droit', () {
      expect(Swing.depuisPourcentage(null), Swing.droit);
      expect(Swing.depuisPourcentage(-1), Swing.droit);
      expect(Swing.depuisPourcentage(-40), Swing.droit);
      expect(Swing.depuisPourcentage(101), Swing.droit);
      expect(Swing.depuisPourcentage(1000), Swing.droit);
    });
  });
}
