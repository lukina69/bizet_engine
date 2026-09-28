import 'package:bizet_engine/bizet_engine.dart';
import 'package:test/test.dart';

/// L'égalisation vivait dans les épreuves des compagnons, du temps où c'était
/// eux qui la portaient. Elle appartient maintenant à `egalisation.dart` et
/// vaut pour toutes les voix : ses épreuves la suivent.
void main() {
  group('le repère sur lequel toutes les voix s\'alignent', () {
    test('c\'est la médiane des poids de la banque', () {
      // Le chiffre lui-même a été choisi à l'oreille, au banc `banc_repere`.
      // Il n'est pas écrit en dur : une nouvelle mesure de la banque le
      // déplacerait. L'épreuve veille seulement à ce qu'il reste une médiane,
      // faute de quoi l'appli perdrait ou gagnerait du volume partout.
      final int dessous =
          poidsMesures.values.where((p) => p < repereEgalisation).length;
      // La tolérance laisse passer les ex aequo : plusieurs sonorités peuvent
      // peser exactement pareil, et elles tombent alors du même côté.
      expect(dessous, closeTo(poidsMesures.length / 2, 4));
    });

    test('une sonorité forte descend, une sonorité douce monte', () {
      // Aucun chiffre en dur : une nouvelle mesure de la banque les
      // déplacerait tous, et l'épreuve ne dirait plus que l'humeur du jour.
      expect(correctionEgalisation(58),
          closeTo(repereEgalisation - poidsNaturel(58)!, 1e-9));
      expect(correctionEgalisation(58), lessThan(0),
          reason: 'le tuba est au-dessus du repère, donc il descend');
      expect(correctionEgalisation(10), greaterThan(0),
          reason: 'la boîte à musique est en dessous, donc elle monte');
    });

    test('deux sonorités de même poids reçoivent la même correction', () {
      // Cherchées dans la table plutôt qu'écrites en dur : quelles sonorités
      // pèsent pareil dépend de la mesure, et la mesure évolue.
      final Map<double, List<int>> parPoids = {};
      poidsMesures.forEach((programme, poids) {
        (parPoids[poids] ??= []).add(programme);
      });
      final List<int> jumelles =
          parPoids.values.firstWhere((l) => l.length >= 2);

      expect(correctionEgalisation(jumelles[0]),
          correctionEgalisation(jumelles[1]));
    });

    test('une sonorité que le catalogue ignore est égalisée quand même', () {
      // Le catalogue ne décrit qu'une vingtaine de sonorités, mais les poids
      // sont mesurés pour les cent vingt : l'égalisation ne s'arrête pas au
      // bord du catalogue. Elle s'y arrêtait, et c'était un silence — la
      // plupart des couples d'instruments n'était pas corrigée sans que rien
      // ne le dise.
      expect(instrumentParProgramme(99), isNull,
          reason: 'l\'atmosphère n\'est pas décrite par le catalogue');
      expect(correctionEgalisation(99),
          closeTo(repereEgalisation - poidsNaturel(99)!, 1e-9));
    });

    test('une sonorité absente de la banque ne se corrige pas', () {
      // Les huit effets sonores (120 à 127) ne sont pas publiés : rien à
      // jouer, donc rien à peser, donc rien à corriger — plutôt qu'une
      // correction devinée.
      expect(poidsNaturel(120), isNull);
      expect(correctionEgalisation(120), 0);
    });

    test('le volume de canal traduit les décibels, et plafonne vers le haut',
        () {
      expect(RenduAudio.volumeDeCanal(0), 100, reason: 'le repos');
      // Un facteur deux en amplitude, soit six décibels.
      expect(RenduAudio.volumeDeCanal(-12), closeTo(50, 1));
      // On ne peut pas monter au-delà de quatre décibels : cent est déjà haut
      // placé dans une échelle qui s'arrête à cent vingt-sept.
      expect(RenduAudio.volumeDeCanal(20), 127);
    });
  });
}
