import 'package:bizet_engine/bizet_engine.dart';
import 'package:test/test.dart';

void main() {
  /// Les vélocités jouées pour une note : la voix d'abord, puis ses doublages.
  List<int> velocites(Epaisseur epaisseur, {int? brillance}) => [
        for (final v in brillance == null
            ? epaisseur.voix(60)
            : epaisseur.voix(60, brillance: brillance))
          v.velocite,
      ];

  /// Les vélocités de chaque voix d'un morceau à trois instruments.
  List<int> parVoix(Reglages reglages, Melodie melodie) => [
        for (final VoixJouee j in reglages.voixJouees(melodie))
          j.voix.epaisseur
              .voix(60, brillance: reglages.brillance)
              .first
              .velocite,
      ];

  Melodie morceau() => Melodie(
        titre: '',
        source: '',
        tempo: 120,
        instrumentMidi: 0,
        mesures: [
          Mesure(notes: [Note(hauteur: 60, duree: 1.0, position: 0.0)],
              duree: 4.0),
        ],
      );

  group('brillance : le grain du son, sans toucher à l\'équilibre', () {
    test('sans rien demander, le moteur joue ce qu\'il a toujours joué', () {
      expect(velocites(Epaisseur.large), [80, 70, 55]);
      expect(const Reglages().brillance, Epaisseur.velociteBase);
    });

    test('la brillance douce descend tout le monde de dix', () {
      expect(velocites(Epaisseur.large, brillance: 70), [70, 60, 45]);
    });

    test('la brillance éclatante monte tout le monde de vingt', () {
      expect(velocites(Epaisseur.large, brillance: 100), [100, 90, 75]);
    });

    test('les écarts entre doublages ne bougent jamais', () {
      // C'est la garantie du réglage : il change le grain du morceau entier,
      // jamais le retrait d'un doublage derrière la ligne qu'il double. Des
      // vélocités absolues feraient rejoindre la voix par son doublage à 70.
      for (final int brillance in const [70, 80, 90, 100]) {
        final List<int> voix = velocites(Epaisseur.large, brillance: brillance);
        expect([for (final v in voix) v - voix.first], [0, -10, -25],
            reason: 'à la brillance $brillance');
      }
    });

    test('les trois voix partent de la même attaque', () {
      // Les voix ajoutées frappaient autrefois vingt et trente-cinq crans plus
      // mollement, pour se mettre en retrait. Ça leur coûtait leur timbre : une
      // flûte discrète ne sonnait pas comme une flûte en avant. Le volume par
      // voix fait ce travail sans toucher au son.
      for (final int brillance in const [70, 100]) {
        expect(
          parVoix(
            Reglages(
              brillance: brillance,
              voix: const [
                Voix(instrument: 0),
                Voix(instrument: 73),
                Voix(instrument: 42),
              ],
            ),
            morceau(),
          ),
          List<int>.filled(3, brillance),
        );
      }
    });

    test('l\'égalisation ne passe pas par l\'attaque mais par le niveau', () {
      // Les deux ne doivent pas se marcher dessus : le tuba se calme d'autant,
      // quelle que soit la brillance demandée.
      for (final int brillance in const [70, 100]) {
        final VoixJouee jouee = Reglages(
          brillance: brillance,
          voix: const [Voix(instrument: 0), Voix(instrument: 58)],
        ).voixJouees(morceau()).last;

        expect(jouee.niveau, closeTo(correctionEgalisation(58), 1e-9));
        expect(
            jouee.voix.epaisseur
                .voix(60, brillance: brillance)
                .single
                .velocite,
            brillance);
      }
    });

    test('une brillance extravagante reste une vélocité jouable', () {
      // Personne ne peut la régler si bas depuis l'appli, mais le moteur ne
      // doit pas rendre une note muette ou hors norme pour autant.
      expect(velocites(Epaisseur.large, brillance: 1), [1, 1, 1]);
      expect(velocites(Epaisseur.large, brillance: 127), [127, 117, 102]);
    });
  });
}
