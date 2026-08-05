import 'package:bizet_engine/bizet_engine.dart';
import 'package:test/test.dart';

/// Une valse d'école : deux mesures à trois temps, avec un contretemps dans
/// la seconde. La pulsation vaut la noire.
Melodie _valse() => Melodie(
      titre: '',
      source: '',
      tempo: 150,
      instrumentMidi: 4,
      mesures: [
        Mesure(
          notes: [
            Note(hauteur: 60, duree: 1.0, position: 0.0),
            Note(hauteur: 64, duree: 1.0, position: 1.0),
            Note(hauteur: 67, duree: 1.0, position: 2.0),
          ],
          duree: 3.0,
        ),
        Mesure(
          notes: [
            Note(hauteur: 60, duree: 1.0, position: 0.0),
            Note(hauteur: 64, duree: 0.5, position: 1.0),
            Note(hauteur: 65, duree: 0.5, position: 1.5),
          ],
          duree: 3.0,
        ),
      ],
    );

void main() {
  group('accents métriques', () {
    test('le premier temps s\'appuie, les temps un rien, le reste non', () {
      expect(accentsMetriques(_valse(), Nuances.souples),
          [10, 4, 4, 10, 4, 0],
          reason: 'UN-deux-trois, et le contretemps reste léger');
    });

    test('uniformes : la machine assumée, rien ne bouge', () {
      expect(accentsMetriques(_valse(), Nuances.uniformes),
          everyElement(0));
    });
  });

  group('marche de poids', () {
    test('bornée, et d\'un pas humain', () {
      final marche = marcheDePoids(200,
          amplitude: 8, graine: 42, indexCycle: 0);

      double precedente = 0.0;
      for (final double poids in marche) {
        expect(poids.abs(), lessThanOrEqualTo(8.0));
        expect((poids - precedente).abs(), lessThanOrEqualTo(3.0),
            reason: 'chaque poids part du précédent : une marche, pas des '
                'tirages indépendants');
        precedente = poids;
      }
    });

    test('même graine, même poids ; autre graine, autre vie', () {
      final a = marcheDePoids(50, amplitude: 8, graine: 7, indexCycle: 0);
      final b = marcheDePoids(50, amplitude: 8, graine: 7, indexCycle: 0);
      final c = marcheDePoids(50, amplitude: 8, graine: 8, indexCycle: 0);

      expect(a, b, reason: 'reproductible : même graine, même musique');
      expect(a, isNot(c));
      expect(a.toSet().length, greaterThan(1), reason: 'ça vit vraiment');
    });

    test('un autre cycle de boucle marche ailleurs', () {
      final a = marcheDePoids(50, amplitude: 8, graine: 7, indexCycle: 0);
      final b = marcheDePoids(50, amplitude: 8, graine: 7, indexCycle: 1);
      expect(a, isNot(b));
    });
  });

  test('l\'écart total reste dans l\'accent plus la marche', () {
    final deltas = calculerNuances(_valse(),
        intensite: Nuances.souples, graine: 3, indexCycle: 0);

    expect(deltas.length, 6, reason: 'un écart par note');
    for (int i = 0; i < deltas.length; i++) {
      final accents = accentsMetriques(_valse(), Nuances.souples);
      expect((deltas[i] - accents[i]).abs(), lessThanOrEqualTo(8),
          reason: 'accent métrique ± la marche, rien d\'autre');
    }
  });

  test('le rendu porte les nuances : premier temps plus lourd au noteOn', () {
    // Passe par l'export MIDI, le chemin le plus simple à relire : les
    // vélocités écrites doivent varier autour de la base quand les nuances
    // sont là, et rester plates sans elles.
    final plates = ExportMusical().versMidi(_valse());
    final vivantes = ExportMusical().versMidi(_valse(),
        reglages: const Reglages(nuances: Nuances.souples));

    expect(plates, isNot(vivantes),
        reason: 'les nuances doivent changer le fichier');
  });
}
