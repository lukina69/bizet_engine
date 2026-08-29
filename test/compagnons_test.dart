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

  group('equilibresSous : l\'accompagnement au même retrait perçu', () {
    // L'égalisation corrige un NIVEAU, pas une attaque : elle agit désormais
    // sur le volume de canal, et la vélocité ne bouge plus. Une voix mise en
    // retrait garde donc le timbre qu'elle avait en avant.
    double niveau(Compagnons c) => c.canaux(1).single.niveau;

    test('deux sonorités de même poids : rien ne change', () {
      // Violon et trompette pèsent pareil dans la banque.
      final Compagnons egalises = Compagnons([56, null]).equilibresSous(40);
      expect(niveau(egalises), 0);
      expect(egalises.voix(60, 1).single.velocite, 60,
          reason: 'la vélocité ne sert plus au niveau');
    });

    test('un compagnon fort sous une mélodie douce se calme', () {
      // Le tuba (0 dB) sous la boîte à musique (-21,8 dB) : sans égalisation
      // il l'écraserait quatorze fois.
      final Compagnons egalises = Compagnons([58, null]).equilibresSous(10);
      expect(niveau(egalises), lessThan(-15));
      expect(egalises.voix(60, 1).single.velocite, 60);
    });

    test('un compagnon doux sous une mélodie forte s\'affirme', () {
      // La boîte à musique sous le tuba : elle monte.
      final Compagnons egalises = Compagnons([10, null]).equilibresSous(58);
      expect(niveau(egalises), greaterThan(15));
    });

    test('une sonorité hors catalogue ne se corrige pas', () {
      expect(niveau(Compagnons([99, null]).equilibresSous(40)), 0);
      expect(niveau(Compagnons([73, null]).equilibresSous(99)), 0,
          reason: 'mélodie inconnue : on ne devine pas');
    });

    test('la présence garde la main par-dessus l\'équilibre', () {
      // Violon et trompette pèsent pareil : à zéro rien ne bouge, et chaque
      // cran de 4 dB pousse ou retient la voix ajoutée.
      final Compagnons voix = Compagnons([56, null]);

      expect(niveau(voix.equilibresSous(40)), 0);
      expect(niveau(voix.equilibresSous(40, presence: -2)), -8);
      expect(niveau(voix.equilibresSous(40, presence: 2)), 8);
    });

    test('la présence s\'applique même sans poids connus', () {
      final Compagnons voix = Compagnons([99, null]);
      expect(niveau(voix.equilibresSous(98, presence: 2)), 8,
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
          Compagnons([73, null]).calesSur([48, 52, 55]).equilibresSous(58);
      expect(cales.decalages, [1, 0]);
      expect(cales.voix(48, 1).single.hauteur, 60);
      expect(niveau(cales), greaterThan(0),
          reason: 'la flûte s\'affirme sous le tuba');
      expect(cales.voix(48, 1).single.velocite, 60,
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
