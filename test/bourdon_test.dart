import 'package:test/test.dart';

import 'package:bizet_engine/bizet_engine.dart';

/// Un morceau d'une mesure, avec ou sans armure.
Melodie _morceau({Armure? armure, List<int> hauteurs = const [72, 76, 79]}) =>
    Melodie(
      titre: '',
      source: '',
      tempo: 120,
      instrumentMidi: 0,
      mesures: [
        Mesure(
          notes: [
            for (int i = 0; i < hauteurs.length; i++)
              Note(hauteur: hauteurs[i], duree: 1.0, position: i * 1.0),
          ],
          duree: 4.0,
        ),
      ],
      armure: armure,
    );

void main() {
  group('Bourdon', () {
    test('la note tenue est la tonique, posée sous la mélodie', () {
      // Do majeur, mélodie autour du do 5 (72) : le bourdon doit être un do,
      // au moins une quinte sous la note la plus grave.
      final hauteur = Bourdon.hauteur(0, 72);
      expect(hauteur % 12, 0, reason: 'un do');
      expect(hauteur, lessThanOrEqualTo(72 - 7));
      expect(hauteur, 60, reason: 'le plus haut do qui laisse cette place');
    });

    test('le bourdon suit la mélodie quand elle descend, jusqu\'à un point',
        () {
      expect(Bourdon.hauteur(0, 60), 48, reason: 'il descend avec elle');
      // Plus bas, il refuse : sous le sol 2, un téléphone ne rend plus rien.
      expect(Bourdon.hauteur(0, 48), 48,
          reason: 'plutôt au milieu de la texture que dans l\'inaudible');
    });

    test('jamais sous le sol 2 : le grave d\'un téléphone s\'arrête là', () {
      // La Vocalise descend au do 2 : la première version posait le bourdon
      // à 33 Hz, que le haut-parleur ne rendait pas. Plus jamais ça.
      for (final int tonique in [0, 5, 9, 11]) {
        for (final int plusBasse in [21, 36, 48, 72]) {
          expect(Bourdon.hauteur(tonique, plusBasse),
              greaterThanOrEqualTo(43),
              reason: 'tonique $tonique, plus basse $plusBasse');
        }
      }
    });

    test('la quinte ajoute sa voix au-dessus de la tonique', () {
      final voix = Bourdon.quinte.voix(0, 72, 3);
      expect(voix.length, 2);
      expect(voix[0].hauteur, 60);
      expect(voix[1].hauteur, 67, reason: 'sept demi-tons plus haut');
      expect(voix.map((v) => v.canal), [3, 4],
          reason: 'chacune son canal, à partir du premier libre');
    });

    test('sans armure ou sans note, pas de bourdon', () {
      expect(Bourdon.tonique.voix(null, 72, 1), isEmpty,
          reason: 'sans tonique, tenir une note serait une fausse note');
      expect(Bourdon.tonique.voix(0, null, 1), isEmpty,
          reason: 'sans mélodie, rien à accompagner');
      expect(Bourdon.aucun.voix(0, 72, 1), isEmpty);
    });

    test('un nom relu retrouve son cran, un nom inconnu retombe sur rien', () {
      for (final Bourdon cran in Bourdon.values) {
        expect(Bourdon.depuisNom(cran.name), cran);
      }
      expect(Bourdon.depuisNom(null), Bourdon.aucun);
      expect(Bourdon.depuisNom('vielle'), Bourdon.aucun);
    });
  });

  group('Bourdon dans les réglages', () {
    const Armure doMajeur = Armure(tonique: 0, majeur: true);

    test('les voix se posent après la mélodie, ses doublages et compagnons',
        () {
      final reglages = Reglages(
        bourdon: Bourdon.tonique,
        epaisseur: Epaisseur.large, // 3 canaux
        compagnons: Compagnons([73, null]), // 1 canal de plus
      );
      final voix = reglages.voixBourdon(_morceau(armure: doMajeur));

      expect(voix.length, 1);
      expect(voix.first.canal, 4, reason: '3 canaux d\'épaisseur + 1 compagnon');
    });

    test('le bourdon suit le morceau transposé d\'une octave', () {
      const bas = Reglages(bourdon: Bourdon.tonique, octave: -1);
      const haut = Reglages(bourdon: Bourdon.tonique);

      final Melodie partition = _morceau(armure: doMajeur);
      final int hautNote =
          haut.voixBourdon(haut.applique(partition)).first.hauteur;
      final int basNote = bas.voixBourdon(bas.applique(partition)).first.hauteur;

      expect(basNote, hautNote - 12,
          reason: 'le morceau descend, le bourdon descend avec lui');
    });

    test('sans armure, le réglage reste sans effet', () {
      const reglages = Reglages(bourdon: Bourdon.quinte);
      expect(reglages.voixBourdon(_morceau()), isEmpty);
    });
  });
}
