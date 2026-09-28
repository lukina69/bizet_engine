import 'package:bizet_engine/bizet_engine.dart';
import 'package:test/test.dart';

/// Ce qui reste à éprouver d'un objet qui en faisait bien plus.
///
/// Le calage d'octave, l'égalisation et les vélocités sont partis dans `Voix`,
/// et leurs épreuves avec eux : voir `voix_test.dart` et
/// `egalisation_test.dart`. Il ne porte plus qu'une liste de sonorités, pour
/// la scène et pour relire un fichier de travail.
void main() {
  group('une liste de sonorités, et rien de plus', () {
    test('elle garde sa longueur, quelle que soit celle qu\'on donne', () {
      // Un fichier de travail écrit par une autre version ne peut donc pas
      // fabriquer un objet bancal.
      expect(Compagnons([]).rangs, [null, null]);
      expect(Compagnons([73]).rangs, [73, null]);
      expect(Compagnons([73, 42, 40, 56]).rangs, [73, 42]);
    });

    test('le rang garde sa place, allumé ou non', () {
      // C'est ce qui donne son canal MIDI à chaque voix : éteindre la première
      // ne doit pas déplacer la seconde au milieu d'un morceau.
      final Compagnons deux = Compagnons([73, 42]);
      expect(deux.avec(0, null).rangs, [null, 42]);
      expect(deux.avec(1, null).rangs, [73, null]);
      expect(deux.avec(0, 40).rangs, [40, 42]);
    });

    test('vide dit qu\'aucune voix ne sonne', () {
      expect(Compagnons.aucun.vide, isTrue);
      expect(Compagnons([null, 42]).vide, isFalse);
      expect(Compagnons([73, 42]).avec(0, null).avec(1, null).vide, isTrue);
    });

    test('le fichier de travail ne porte que les programmes', () {
      final Compagnons deux = Compagnons([73, 42]);
      expect(deux.toJson(), [73, 42]);
      expect(Compagnons.depuisJson(deux.toJson()).rangs, [73, 42]);
    });

    test('tout ce qui n\'est pas une liste de nombres se relit sans erreur',
        () {
      // Un fichier plus ancien, ou abîmé, s'ouvre sur la mélodie seule plutôt
      // que de faire tomber l'appli.
      expect(Compagnons.depuisJson(null).vide, isTrue);
      expect(Compagnons.depuisJson('pas une liste').vide, isTrue);
      expect(Compagnons.depuisJson([73, 'bonjour']).rangs, [73, null]);
      expect(Compagnons.depuisJson({'a': 1}).vide, isTrue);
    });
  });
}
