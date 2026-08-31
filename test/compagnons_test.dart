import 'package:bizet_engine/bizet_engine.dart';
import 'package:test/test.dart';

void main() {
  group('calesSur : le compagnon se met à l\'octave où il sonne bien', () {
    test('la flûte monte d\'une octave sur une ligne grave', () {
      // Une ligne autour du do3 (48-59) : la flûte (tessiture 60-96) n'y a
      // aucune note à elle. Une octave plus haut, tout y est.
      final Compagnons cales =
          Compagnons([73, null]).calesSur([48, 52, 55, 59]);
      expect(cales.decalages, [1, 0]);

      // Et les voix jouent bien douze demi-tons plus haut.
      expect(cales.voix(48, 1).single.hauteur, 60);
    });

    test('le tuba descend, de deux octaves s\'il le faut', () {
      // Une ligne autour du do5 : à -1 le tuba (28-65) n'en attrape qu'une
      // partie, à -2 il a tout.
      final Compagnons cales =
          Compagnons([58, null]).calesSur([72, 76, 79, 84]);
      expect(cales.decalages, [-2, 0]);
    });

    test('une mélodie déjà dans la tessiture ne bouge pas', () {
      final Compagnons cales = Compagnons([40, null]).calesSur([60, 67, 72]);
      expect(cales.decalages, [0, 0], reason: 'le violon y est chez lui');
    });

    test('à égalité parfaite, le décalage le plus sobre gagne', () {
      // La harpe (24-103) contient cette ligne à toutes les octaves
      // proposées : on reste sur place.
      final Compagnons cales = Compagnons([46, null]).calesSur([60, 66, 72]);
      expect(cales.decalages, [0, 0]);
    });

    test('une sonorité hors catalogue reste à l\'unisson', () {
      final Compagnons cales = Compagnons([99, null]).calesSur([48, 52]);
      expect(cales.decalages, [0, 0],
          reason: 'sans tessiture connue, on ne devine pas');
    });

    test('chaque voix se cale pour elle-même', () {
      // Même ligne grave : la flûte monte, le violoncelle (36-81) reste.
      final Compagnons cales = Compagnons([73, 42]).calesSur([48, 52, 55]);
      expect(cales.decalages, [1, 0]);
    });
  });

  group('equilibres : chaque voix ramenée au même niveau', () {
    // L'égalisation corrige un NIVEAU, pas une attaque : elle agit sur le
    // volume de canal, et la vélocité ne bouge plus. Une voix mise en retrait
    // garde donc le timbre qu'elle avait en avant.
    double niveau(Compagnons c) => c.canaux(1).single.niveau;

    test('le repère est la médiane des poids de la banque', () {
      // Ce chiffre-là a été choisi à l'oreille, au banc `banc_repere.dart`.
      // Il n'est pas écrit en dur : une nouvelle mesure de la banque le
      // déplacerait. Le test veille seulement à ce qu'il reste une médiane,
      // c'est-à-dire à ce qu'autant de sonorités soient au-dessus qu'en
      // dessous — sans quoi l'appli perdrait ou gagnerait du volume partout.
      final int dessous =
          poidsMesures.values.where((p) => p < repereEgalisation).length;
      expect(dessous, closeTo(poidsMesures.length / 2, 1));
    });

    test('une sonorité forte descend, une sonorité douce monte', () {
      // Le tuba est presque le plus fort de la banque, la boîte à musique
      // parmi les plus discrètes. Ils se rejoignent.
      expect(niveau(Compagnons([58, null]).equilibres()), lessThan(-8));
      expect(niveau(Compagnons([10, null]).equilibres()), greaterThan(8));
      expect(Compagnons([58, null]).equilibres().voix(60, 1).single.velocite,
          Epaisseur.velociteBase - 20,
          reason: 'la vélocité ne sert plus au niveau');
    });

    test('le repère est absolu, il ne dépend pas de la mélodie', () {
      // C'est là qu'est la différence avec l'ancienne égalisation, qui posait
      // l'accompagnement sous la mélodie : le même compagnon était corrigé
      // autrement selon la sonorité principale, et le volume du morceau
      // sautait dès qu'on changeait celle-ci.
      final double seul = niveau(Compagnons([56, null]).equilibres());
      expect(seul, closeTo(-1.1, 0.05));
      expect(Compagnons([56, 40]).equilibres().canaux(1).first.niveau, seul,
          reason: 'la voisine ne change rien non plus');
    });

    test('deux sonorités de même poids reçoivent la même correction', () {
      // Violon et trompette pèsent pareil dans la banque.
      expect(niveau(Compagnons([56, null]).equilibres()),
          niveau(Compagnons([40, null]).equilibres()));
    });

    test('une sonorité que le catalogue ignore est égalisée quand même', () {
      // Le catalogue ne décrit qu'une vingtaine de sonorités, mais les poids
      // sont mesurés pour les cent vingt : l'égalisation ne s'arrête donc
      // plus au bord du catalogue. Elle s'y arrêtait, et c'était un silence
      // — la plupart des couples d'instruments n'était pas corrigée sans que
      // rien ne le dise.
      expect(instrumentParProgramme(99), isNull,
          reason: 'l\'atmosphère n\'est pas décrite par le catalogue');
      expect(niveau(Compagnons([99, null]).equilibres()), closeTo(-0.1, 0.05));
    });

    test('une sonorité absente de la banque ne se corrige pas', () {
      // Les huit effets sonores (120 à 127) ne sont pas publiés : rien à
      // jouer, donc rien à peser, donc rien à corriger — plutôt qu'une
      // correction devinée.
      expect(poidsNaturel(120), isNull);
      expect(niveau(Compagnons([120, null]).equilibres()), 0);
    });

    test('la présence garde la main par-dessus l\'équilibre', () {
      final Compagnons voix = Compagnons([56, null]);
      final double equilibre = niveau(voix.equilibres());

      expect(niveau(voix.equilibres(presence: -2)), closeTo(equilibre - 8, 1e-9));
      expect(niveau(voix.equilibres(presence: 2)), closeTo(equilibre + 8, 1e-9));
    });

    test('la présence s\'applique même sans poids connu', () {
      expect(niveau(Compagnons([120, null]).equilibres(presence: 2)), 8,
          reason: 'l\'égalisation ne sait rien, la main de l\'utilisateur si');
    });

    test('le volume de canal traduit les décibels, et plafonne vers le haut',
        () {
      expect(RenduAudio.volumeDeCanal(0), 100, reason: 'le repos');
      // Un facteur deux en amplitude, soit six décibels.
      expect(RenduAudio.volumeDeCanal(-12), closeTo(50, 1));
      // On ne peut pas monter au-delà de quatre décibels : cent est déjà
      // haut placé dans une échelle qui s'arrête à cent vingt-sept.
      expect(RenduAudio.volumeDeCanal(20), 127);
    });

    test('l\'égalisation n\'écrase pas le calage d\'octave', () {
      // Flûte sur ligne grave : elle monte d'une octave ET s'égalise.
      final Compagnons cales =
          Compagnons([73, null]).calesSur([48, 52, 55]).equilibres();
      expect(cales.decalages, [1, 0]);
      expect(cales.voix(48, 1).single.hauteur, 60);
      expect(niveau(cales), closeTo(-2.2, 0.05));
      expect(cales.voix(48, 1).single.velocite, Epaisseur.velociteBase - 20,
          reason: 'et garde son attaque : le niveau seul a bougé');
    });
  });

  test('le calage est un état de jeu, pas un réglage : il ne s\'enregistre pas',
      () {
    final Compagnons cales = Compagnons([73, null]).calesSur([48, 52]);
    expect(cales.toJson(), [73, null],
        reason: 'le fichier de travail ne porte que les programmes');
    expect(Compagnons.depuisJson(cales.toJson()).decalages, [0, 0],
        reason: 'relu, il repart à l\'unisson jusqu\'au prochain calage');
  });

  test('le calage ne touche ni aux canaux ni aux vélocités', () {
    final Compagnons nus = Compagnons([73, 42]);
    final Compagnons cales = nus.calesSur([48, 52, 55]);

    expect(cales.canaux(1), nus.canaux(1));
    expect(
      [for (final v in cales.voix(48, 1)) (v.canal, v.velocite)],
      [for (final v in nus.voix(48, 1)) (v.canal, v.velocite)],
    );
  });
}
