import 'package:test/test.dart';

import 'package:bizet_engine/bizet_engine.dart';

Melodie _melodieExemple() => Melodie(
      titre: 'Test',
      source: 'Mutopia: exemple',
      tempo: 120,
      instrumentMidi: 0,
      mesures: [
        Mesure(
          notes: [Note(hauteur: 60, duree: 1.0, position: 0.0)],
          selectionnee: true,
        ),
        Mesure(
          notes: [Note(hauteur: 62, duree: 1.0, position: 0.0)],
          selectionnee: false,
        ),
        Mesure(
          notes: [Note(hauteur: 64, duree: 1.0, position: 0.0)],
          selectionnee: true,
        ),
      ],
    );

void main() {
  group('Melodie', () {
    test('transposee transpose toutes les mesures, garde les métadonnées', () {
      final m = _melodieExemple().transposee(12);
      expect(m.titre, 'Test');
      expect(m.tempo, 120);
      expect(m.mesures[0].notes.first.hauteur, 72);
      expect(m.mesures[1].notes.first.hauteur, 74);
    });

    test('decoupee ne garde que les mesures sélectionnées', () {
      final d = _melodieExemple().decoupee();
      expect(d.mesures.length, 2);
      expect(d.mesures.map((m) => m.notes.first.hauteur), [60, 64]);
    });

    test('decoupee ne modifie pas la mélodie originale', () {
      final original = _melodieExemple();
      original.decoupee();
      expect(original.mesures.length, 3);
    });

    test('aller-retour JSON conserve tout, sélection comprise (option B)', () {
      final copie = Melodie.fromJson(_melodieExemple().toJson());
      expect(copie.titre, 'Test');
      expect(copie.source, 'Mutopia: exemple');
      expect(copie.tempo, 120);
      expect(copie.instrumentMidi, 0);
      expect(copie.mesures.length, 3);
      expect(copie.mesures.map((m) => m.selectionnee), [true, false, true]);
    });
  });

  group('pulsation', () {
    Melodie surRythme(double duree, int combien) => Melodie(
          titre: '',
          source: '',
          tempo: 120,
          instrumentMidi: 0,
          mesures: [
            Mesure(
              notes: [
                for (int i = 0; i < combien; i++)
                  Note(hauteur: 60, duree: duree, position: i * duree),
              ],
              duree: duree * combien,
            ),
          ],
        );

    test('suit ce que l\'oreille entend, pas la mesure écrite', () {
      expect(surRythme(1.0, 8).pulsation, 1.0, reason: 'des noires');
      expect(surRythme(0.5, 8).pulsation, 0.5, reason: 'des croches');
      expect(surRythme(0.25, 8).pulsation, 0.25, reason: 'des doubles');
    });

    test('l\'écart le plus fréquent l\'emporte sur les exceptions', () {
      // Une blanche isolée au milieu d'un morceau en croches ne doit pas
      // décider du rythme de tout le morceau.
      final m = surRythme(0.5, 8);
      m.mesures.add(Mesure(
        notes: [Note(hauteur: 60, duree: 2.0, position: 0.0)],
        duree: 2.0,
      ));

      expect(m.pulsation, 0.5);
    });

    test('un morceau sans notes ne fait pas échouer le calcul', () {
      expect(surRythme(1.0, 0).pulsation, 1.0);
      expect(surRythme(1.0, 1).pulsation, 1.0, reason: 'aucun écart à mesurer');
    });

    test('les notes simultanées ne comptent pas pour un écart nul', () {
      // Un accord partage un même instant : sans précaution, l'écart le plus
      // fréquent serait zéro.
      final m = Melodie(
        titre: '',
        source: '',
        tempo: 120,
        instrumentMidi: 0,
        mesures: [
          Mesure(
            notes: [
              Note(hauteur: 60, duree: 1.0, position: 0.0),
              Note(hauteur: 64, duree: 1.0, position: 0.0),
              Note(hauteur: 67, duree: 1.0, position: 0.0),
              Note(hauteur: 62, duree: 1.0, position: 1.0),
              Note(hauteur: 65, duree: 1.0, position: 1.0),
            ],
            duree: 2.0,
          ),
        ],
      );

      expect(m.pulsation, 1.0);
    });
  });

  group('deroule', () {
    Melodie surHauteurs(List<int> hauteurs) => Melodie(
          titre: '',
          source: '',
          tempo: 120,
          instrumentMidi: 0,
          mesures: [
            for (final h in hauteurs)
              Mesure(
                notes: [Note(hauteur: h, duree: 1.0, position: 0.0)],
                duree: 1.0,
              ),
          ],
        );

    test('les mesures s\'enchaînent sur leur durée déclarée', () {
      final suite = surHauteurs([60, 62, 64]).deroule();
      expect(suite.map((s) => s.debut), [0.0, 1.0, 2.0]);
      expect(suite.map((s) => s.fin), [1.0, 2.0, 3.0]);
      expect(suite.map((s) => s.hauteur), [60, 62, 64]);
    });

    test('le piqué raccourcit le son sans toucher au rythme', () {
      final suite = surHauteurs([60, 62]).deroule(articulation: 0.25);
      expect(suite.map((s) => s.debut), [0.0, 1.0], reason: 'le rythme tient');
      expect(suite.map((s) => s.fin), [0.25, 1.25]);
    });

    test('le lié fait déborder chaque note sur la suivante', () {
      final suite = surHauteurs([60, 62]).deroule(articulation: 1.05);
      expect(suite.first.fin, closeTo(1.05, 1e-12));
      expect(suite.first.fin, greaterThan(suite.last.debut));
    });

    test('deux fois la même hauteur : la première laisse une respiration', () {
      // D'abord parce que sa fin éteindrait la seconde, qui vient de
      // démarrer ; ensuite parce que deux frappes collées se fondent en une
      // seule note tenue — les répétitions du Danube ont disparu comme ça.
      final suite = surHauteurs([60, 60, 62]).deroule(articulation: 1.05);
      expect(suite[0].fin, closeTo(0.9, 1e-12),
          reason: 'coupée un dixième de temps avant la suivante');
      expect(suite[1].fin, closeTo(2.05, 1e-12), reason: 'hauteur différente');
    });

    test('même sans lié, une répétition ne se colle pas bord à bord', () {
      // C'est le cas du Danube : les notes répétées sont écrites l'une
      // contre l'autre, et l'articulation n'y change rien.
      final suite = surHauteurs([60, 60]).deroule();
      expect(suite[0].fin, closeTo(0.9, 1e-12));
      expect(suite[1].fin, 2.0, reason: 'la dernière va au bout');
    });

    test('la respiration est plafonnée : une ronde n\'y perd qu\'un souffle',
        () {
      final m = Melodie(
        titre: '',
        source: '',
        tempo: 120,
        instrumentMidi: 0,
        mesures: [
          for (int i = 0; i < 2; i++)
            Mesure(
              notes: [Note(hauteur: 60, duree: 4.0, position: 0.0)],
              duree: 4.0,
            ),
        ],
      );
      final suite = m.deroule();
      expect(suite[0].fin, closeTo(3.9, 1e-12),
          reason: 'un dixième de temps, pas un dixième de la ronde');
    });

    test('la garde ne raccourcit rien quand la respiration existe déjà', () {
      final suite = surHauteurs([60, 60]).deroule(articulation: 0.9);
      expect(suite[0].fin, closeTo(0.9, 1e-12));
    });

    test('la garde voit aussi les répétitions séparées par d\'autres notes',
        () {
      // Voix fusionnées : la mélodie tient un do pendant que l'accompagnement
      // s'intercale, puis refrappe le même do. Les deux frappes ne sont pas
      // voisines dans la liste — c'est le cas du Danube, cent neuf fois.
      final m = Melodie(
        titre: '',
        source: '',
        tempo: 120,
        instrumentMidi: 0,
        mesures: [
          Mesure(
            notes: [
              Note(hauteur: 60, duree: 2.0, position: 0.0),
              Note(hauteur: 64, duree: 1.0, position: 1.0),
              Note(hauteur: 60, duree: 1.0, position: 2.0),
            ],
            duree: 3.0,
          ),
        ],
      );

      final suite = m.deroule(articulation: 1.05);
      expect(suite[0].fin, closeTo(1.9, 1e-12),
          reason: 'le premier do respire avant le second, mi entre eux ou pas');
      expect(suite[1].fin, closeTo(2.05, 1e-12),
          reason: 'le mi, seul de sa hauteur, garde son lié');
    });

    test('la partition écrite se lit sans la respiration', () {
      // C'est elle que lit le calcul du rubato : une coupure technique n'est
      // ni un silence ni une fin de phrase, le jeu ne doit pas se mettre à
      // respirer après chaque note répétée.
      final suite = surHauteurs([60, 60]).deroule(respiration: false);
      expect(suite[0].fin, 1.0, reason: 'bord à bord, comme écrit');
    });

    test('la durée sonore n\'est jamais nulle, même au plus piqué', () {
      final suite = surHauteurs([60, 60]).deroule(articulation: 0.25);
      for (final s in suite) {
        expect(s.fin, greaterThan(s.debut));
      }
    });
  });
}
