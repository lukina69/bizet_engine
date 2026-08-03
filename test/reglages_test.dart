import 'package:test/test.dart';

import 'package:bizet_engine/bizet_engine.dart';

/// Deux mesures en do majeur : do-mi-sol, puis la ronde du do.
Melodie _partition({Armure? armure}) => Melodie(
      titre: 'Essai',
      source: '',
      tempo: 90,
      instrumentMidi: 40,
      mesures: [
        Mesure(
          notes: [
            Note(hauteur: 60, duree: 1.0, position: 0.0),
            Note(hauteur: 64, duree: 1.0, position: 1.0),
            Note(hauteur: 67, duree: 2.0, position: 2.0),
          ],
          duree: 4.0,
        ),
        Mesure(
          notes: [Note(hauteur: 72, duree: 4.0, position: 0.0)],
          duree: 4.0,
        ),
      ],
      armure: armure,
    );

List<int> _hauteurs(Melodie m) =>
    m.mesures.expand((mes) => mes.notes).map((n) => n.hauteur).toList();

void main() {
  group('Reglages', () {
    test('sans rien régler, la partition sonne comme elle est écrite', () {
      // C'est tout l'intérêt des réglages nuls : jouer un morceau sans y
      // toucher ne doit pas lui imposer un tempo ni une sonorité d'emprunt.
      final Melodie jouee = const Reglages().applique(_partition());

      expect(jouee.tempo, 90);
      expect(jouee.instrumentMidi, 40);
      expect(_hauteurs(jouee), [60, 64, 67, 72]);
    });

    test('le tempo et la sonorité choisis prennent le dessus', () {
      final Melodie jouee =
          const Reglages(tempo: 160, instrument: 73).applique(_partition());

      expect(jouee.tempo, 160);
      expect(jouee.instrumentMidi, 73);
    });

    test('l\'octave déplace tout le morceau, sans rien d\'autre', () {
      final Melodie jouee = const Reglages(octave: -1).applique(_partition());

      expect(_hauteurs(jouee), [48, 52, 55, 60]);
      expect(jouee.tempo, 90, reason: 'le reste ne bouge pas');
    });

    test('le mode bascule quand la partition dit sa tonalité', () {
      final Melodie triste = const Reglages(majeur: false)
          .applique(_partition(armure: const Armure(tonique: 0, majeur: true)));

      // Seule la tierce descend d'un demi-ton : la mélodie reste elle-même.
      expect(_hauteurs(triste), [60, 63, 67, 72]);
    });

    test('sans armure, le mode demandé reste sans effet', () {
      final Melodie jouee =
          const Reglages(majeur: false).applique(_partition());
      expect(_hauteurs(jouee), [60, 64, 67, 72]);
    });

    test('le mode se change avant la transposition', () {
      // Les degrés se comptent depuis la tonique écrite : sinon, un morceau
      // transposé verrait abaisser la mauvaise note.
      final Melodie jouee = const Reglages(majeur: false, octave: 1)
          .applique(_partition(armure: const Armure(tonique: 0, majeur: true)));

      expect(_hauteurs(jouee), [72, 75, 79, 84]);
    });

    test('la partition d\'origine n\'est jamais touchée', () {
      final Melodie partition = _partition();
      const Reglages(tempo: 200, instrument: 0, octave: 2)
          .applique(partition);

      expect(partition.tempo, 90);
      expect(partition.instrumentMidi, 40);
      expect(_hauteurs(partition), [60, 64, 67, 72]);
    });
  });
}
