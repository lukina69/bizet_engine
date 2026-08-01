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
}
