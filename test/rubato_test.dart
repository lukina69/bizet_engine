import 'package:test/test.dart';

import 'package:bizet_engine/bizet_engine.dart';

/// Une suite de notes à la file, sans silence : durées données en temps.
List<({double debut, double fin, int hauteur})> _suite(List<double> durees) {
  final List<({double debut, double fin, int hauteur})> notes = [];
  double t = 0.0;
  for (final double d in durees) {
    notes.add((debut: t, fin: t + d, hauteur: 60));
    t += d;
  }
  return notes;
}

/// La même chose, mais avec un silence après la note d'index [apres].
List<({double debut, double fin, int hauteur})> _suiteAvecSilence(
  List<double> durees,
  int apres,
) {
  final List<({double debut, double fin, int hauteur})> notes = [];
  double t = 0.0;
  for (int i = 0; i < durees.length; i++) {
    notes.add((debut: t, fin: t + durees[i], hauteur: 60));
    t += durees[i];
    if (i == apres) t += 1.0; // un temps de silence
  }
  return notes;
}

double _sommeAllongements(List<({double debut, double fin})> ecarts) =>
    ecarts.isEmpty ? 0.0 : ecarts.last.fin;

void main() {
  group('Rubato', () {
    test('mécanique ne dévie rien du tout', () {
      final ecarts = calculerRubato(
        _suiteAvecSilence([1.0, 0.5, 2.0, 0.5, 1.0], 1),
        intensite: Rubato.mecanique,
        graine: 7,
        indexCycle: 0,
      );

      for (final e in ecarts) {
        expect(e.debut, 0.0);
        expect(e.fin, 0.0);
      }
    });

    test('les crans vont en s\'accentuant', () {
      double amplitude(Rubato r) {
        final ecarts = calculerRubato(_suiteAvecSilence([1.0, 0.5, 2.0, 0.5], 1),
            intensite: r, graine: 3, indexCycle: 0);
        return ecarts.fold(0.0, (s, e) => s + e.debut.abs() + e.fin.abs());
      }

      expect(amplitude(Rubato.leger), greaterThan(amplitude(Rubato.mecanique)));
      expect(amplitude(Rubato.modere), greaterThan(amplitude(Rubato.leger)));
      expect(amplitude(Rubato.expressif), greaterThan(amplitude(Rubato.modere)));
    });

    test('le temps emprunté est rendu avant la fin de la boucle', () {
      // C'est la contrainte qui compte le plus : si la boucle s'allongeait, le
      // point de raccord se déplacerait à chaque tour et s'entendrait aussitôt.
      final profils = [
        _suite([1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]),
        _suiteAvecSilence([0.5, 0.5, 2.0, 0.5, 0.5, 1.0, 3.0], 2),
        _suiteAvecSilence([1.0, 0.25, 0.25, 0.5, 4.0, 0.5, 0.5, 0.5], 4),
      ];

      for (final Rubato intensite in Rubato.values) {
        for (int profil = 0; profil < profils.length; profil++) {
          for (int cycle = 0; cycle < 4; cycle++) {
            final ecarts = calculerRubato(profils[profil],
                intensite: intensite, graine: 12345, indexCycle: cycle);
            expect(_sommeAllongements(ecarts), closeTo(0.0, 1e-9),
                reason: '${intensite.name}, profil $profil, cycle $cycle');
          }
        }
      }
    });

    test('même graine et même cycle : exactement le même jeu', () {
      final notes = _suiteAvecSilence([1.0, 0.5, 2.0, 0.5, 1.0], 2);
      final a = calculerRubato(notes,
          intensite: Rubato.expressif, graine: 42, indexCycle: 3);
      final b = calculerRubato(notes,
          intensite: Rubato.expressif, graine: 42, indexCycle: 3);

      expect(b.map((e) => e.debut).toList(), a.map((e) => e.debut).toList());
      expect(b.map((e) => e.fin).toList(), a.map((e) => e.fin).toList());
    });

    test('des cycles différents ne jouent pas tous pareil', () {
      final notes = _suiteAvecSilence([1.0, 0.5, 2.0, 0.5, 1.0, 0.5], 2);
      final List<String> jeux = [
        for (int cycle = 0; cycle < 4; cycle++)
          calculerRubato(notes,
                  intensite: Rubato.expressif, graine: 8, indexCycle: cycle)
              .map((e) => '${e.debut.toStringAsFixed(6)}/'
                  '${e.fin.toStringAsFixed(6)}')
              .join(),
      ];

      expect(jeux.toSet().length, greaterThan(1),
          reason: 'quatre tours de boucle, pas quatre fois le même');
    });

    test('l\'ampleur générale marche à petits pas, sans jamais sortir', () {
      // Une marche bornée, pas un tirage indépendant : le jeu évolue d'un tour
      // à l'autre au lieu de sauter.
      double precedente = ampleurDuCycle(graine: 99, indexCycle: 0);
      expect(precedente, inInclusiveRange(0.6, 1.0));

      for (int cycle = 1; cycle < 200; cycle++) {
        final double courante = ampleurDuCycle(graine: 99, indexCycle: cycle);
        expect(courante, inInclusiveRange(0.6, 1.0), reason: 'cycle $cycle');
        expect((courante - precedente).abs(), lessThanOrEqualTo(0.2 + 1e-12),
            reason: 'cycle $cycle : un pas, pas un saut');
        precedente = courante;
      }
    });

    test('l\'ampleur bouge vraiment au fil des tours', () {
      final valeurs = {
        for (int cycle = 0; cycle < 20; cycle++)
          ampleurDuCycle(graine: 99, indexCycle: cycle),
      };
      expect(valeurs.length, greaterThan(5), reason: 'une marche, pas un plat');
    });

    test('les écarts sont proportionnels aux durées', () {
      // Rien n'est exprimé en millisecondes : le même morceau joué deux fois
      // plus vite doit respirer deux fois moins longtemps, pas autant.
      final court = _suiteAvecSilence([0.5, 0.25, 1.0, 0.25], 1);
      final long = _suiteAvecSilence([1.0, 0.5, 2.0, 0.5], 1);

      final a = calculerRubato(court,
          intensite: Rubato.expressif, graine: 5, indexCycle: 0);
      final b = calculerRubato(long,
          intensite: Rubato.expressif, graine: 5, indexCycle: 0);

      for (int i = 0; i < a.length; i++) {
        expect(b[i].debut, closeTo(a[i].debut * 2, 1e-9), reason: 'note $i');
        expect(b[i].fin, closeTo(a[i].fin * 2, 1e-9), reason: 'note $i');
      }
    });

    test('un morceau sans respiration ni note longue ne dévie pas', () {
      final plat = _suite([1.0, 1.0, 1.0, 1.0]);
      expect(rubatoAudible(plat), isFalse);

      final ecarts = calculerRubato(plat,
          intensite: Rubato.expressif, graine: 1, indexCycle: 0);
      // Une seule candidate possible — la dernière note de la boucle — et son
      // allongement est aussitôt rendu : la boucle sonne comme elle est écrite.
      expect(_sommeAllongements(ecarts), closeTo(0.0, 1e-9));
    });

    test('le prédicat suit ce que le morceau offre', () {
      expect(rubatoAudible(_suite([1.0, 1.0, 1.0])), isFalse,
          reason: 'ni silence ni note longue');
      expect(rubatoAudible(_suiteAvecSilence([1.0, 1.0, 1.0], 0)), isTrue,
          reason: 'un silence');
      expect(rubatoAudible(_suite([1.0, 1.0, 4.0, 1.0])), isTrue,
          reason: 'une note nettement plus longue');
      expect(rubatoAudible(_suite([1.0])), isFalse, reason: 'une seule note');
      expect(rubatoAudible(const []), isFalse, reason: 'rien du tout');
    });

    test('un balancement marqué bride le rubato', () {
      // Les deux déplacent le temps : à ampleur comparable, ils se détruisent.
      for (final Swing cran in [Swing.droit, Swing.leger]) {
        expect(Rubato.expressif.bridePar(Balancement(cran)), Rubato.expressif,
            reason: cran.name);
      }
      for (final Swing cran in [Swing.ternaire, Swing.pointe]) {
        expect(Rubato.expressif.bridePar(Balancement(cran)), Rubato.leger,
            reason: cran.name);
        expect(Rubato.modere.bridePar(Balancement(cran)), Rubato.leger,
            reason: cran.name);
        // Ce qui est déjà en deçà n'est pas relevé pour autant.
        expect(Rubato.mecanique.bridePar(Balancement(cran)), Rubato.mecanique,
            reason: cran.name);
      }
    });

    test('un nom relu retrouve son cran, un nom inconnu le défaut', () {
      for (final Rubato cran in Rubato.values) {
        expect(Rubato.depuisNom(cran.name), cran);
      }
      expect(Rubato.depuisNom(null), Rubato.leger);
      expect(Rubato.depuisNom('libre'), Rubato.leger);
    });
  });

  group('Rubato dans le rendu', () {
    Melodie morceau() => Melodie(
          titre: '',
          source: '',
          tempo: 120,
          instrumentMidi: 0,
          mesures: [
            Mesure(
              notes: [
                Note(hauteur: 60, duree: 1.0, position: 0.0),
                Note(hauteur: 62, duree: 1.0, position: 1.0),
                Note(hauteur: 64, duree: 2.0, position: 2.0),
              ],
              duree: 4.0,
            ),
            Mesure(
              notes: [Note(hauteur: 65, duree: 1.0, position: 0.0)],
              duree: 4.0, // trois temps de silence : une vraie respiration
            ),
          ],
        );

    test('sans rubato, le rythme est exactement celui qui est écrit', () {
      final sonnantes = const Reglages().notesSonnantes(morceau());
      expect(sonnantes.map((s) => s.debut), [0.0, 1.0, 2.0, 4.0]);
      expect(sonnantes.map((s) => s.fin), [1.0, 2.0, 4.0, 5.0]);
    });

    test('avec rubato, le rythme bouge mais la boucle garde sa longueur', () {
      final Melodie m = morceau();
      final sonnantes =
          const Reglages(rubato: Rubato.expressif, graine: 4).notesSonnantes(m);
      final droites = const Reglages().notesSonnantes(m);

      expect(sonnantes.map((s) => s.debut).toList(),
          isNot(droites.map((s) => s.debut).toList()));
      expect(sonnantes.last.fin, closeTo(droites.last.fin, 1e-9),
          reason: 'la dernière note finit là où elle finissait');
    });

    test('le piqué se prend sur la durée réellement jouée', () {
      final Melodie m = morceau();
      final piquees = const Reglages(rubato: Rubato.expressif, graine: 4,
              articulation: 0.5)
          .notesSonnantes(m);
      final tenues =
          const Reglages(rubato: Rubato.expressif, graine: 4).notesSonnantes(m);

      for (int i = 0; i < piquees.length; i++) {
        expect(piquees[i].debut, closeTo(tenues[i].debut, 1e-9),
            reason: 'le rythme ne change pas avec le piqué');
        expect(piquees[i].fin - piquees[i].debut,
            closeTo((tenues[i].fin - tenues[i].debut) * 0.5, 1e-9),
            reason: 'note $i');
      }
    });
  });
}
