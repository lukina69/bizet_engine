import 'package:bizet_engine/bizet_engine.dart';
import 'package:test/test.dart';

void main() {
  /// Les vélocités jouées pour une note, mélodie d'abord puis doublages.
  List<int> doublages(Epaisseur epaisseur, {int? brillance}) => [
        for (final v in brillance == null
            ? epaisseur.voix(60)
            : epaisseur.voix(60, brillance: brillance))
          v.velocite,
      ];

  /// Les vélocités des voix ajoutées, dans l'ordre des rangs.
  List<int> ajoutees(Compagnons compagnons, {int? brillance}) => [
        for (final v in brillance == null
            ? compagnons.voix(60, 1)
            : compagnons.voix(60, 1, brillance: brillance))
          v.velocite,
      ];

  group('brillance : le grain du son, sans toucher à l\'équilibre', () {
    test('sans rien demander, le moteur joue ce qu\'il a toujours joué', () {
      expect(doublages(Epaisseur.large), [80, 70, 55]);
      expect(ajoutees(Compagnons([73, 40])), [60, 45]);
      expect(const Reglages().brillance, Epaisseur.velociteBase);
    });

    test('la brillance douce descend tout le monde de dix', () {
      expect(doublages(Epaisseur.large, brillance: 70), [70, 60, 45]);
      expect(ajoutees(Compagnons([73, 40]), brillance: 70), [50, 35]);
    });

    test('la brillance éclatante monte tout le monde de vingt', () {
      expect(doublages(Epaisseur.large, brillance: 100), [100, 90, 75]);
      expect(ajoutees(Compagnons([73, 40]), brillance: 100), [80, 65]);
    });

    test('les écarts entre voix ne bougent jamais', () {
      // C'est la garantie du réglage : il change le grain du morceau entier,
      // jamais le retrait d'une voix derrière une autre. Des vélocités
      // absolues feraient rejoindre la mélodie par son doublage à 70.
      for (final int brillance in const [70, 80, 90, 100]) {
        final List<int> voix = [
          ...doublages(Epaisseur.large, brillance: brillance),
          ...ajoutees(Compagnons([73, 40]), brillance: brillance),
        ];
        expect([for (final v in voix) v - voix.first], [0, -10, -25, -20, -35],
            reason: 'à la brillance $brillance');
      }
    });

    test('l\'égalisation des voix ajoutées reste sur le volume de canal', () {
      // La brillance touche l'attaque, l'égalisation le niveau : les deux ne
      // doivent pas se marcher dessus. Le tuba sous la boîte à musique se
      // calme autant, quelle que soit la brillance demandée.
      final Compagnons egalises = Compagnons([58, null]).equilibresSous(10);
      final double niveau = egalises.canaux(1).single.niveau;

      for (final int brillance in const [70, 100]) {
        expect(egalises.canaux(1).single.niveau, niveau);
        expect(ajoutees(egalises, brillance: brillance).first, brillance - 20);
      }
    });

    test('une brillance extravagante reste une vélocité jouable', () {
      // Personne ne peut la régler si bas depuis l'appli, mais le moteur ne
      // doit pas rendre une note muette ou hors norme pour autant.
      expect(doublages(Epaisseur.large, brillance: 1), [1, 1, 1]);
      expect(doublages(Epaisseur.large, brillance: 127), [127, 117, 102]);
    });
  });
}
