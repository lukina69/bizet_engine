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
