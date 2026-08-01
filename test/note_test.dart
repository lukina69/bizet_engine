import 'package:test/test.dart';

import 'package:bizet_engine/bizet_engine.dart';

void main() {
  group('Note', () {
    test('transposee décale la hauteur, garde durée et position', () {
      final n = Note(hauteur: 60, duree: 1.0, position: 0.0);
      final t = n.transposee(2);
      expect(t.hauteur, 62);
      expect(t.duree, 1.0);
      expect(t.position, 0.0);
      // L'originale n'est pas modifiée.
      expect(n.hauteur, 60);
    });

    test('transposee accepte un intervalle négatif', () {
      final n = Note(hauteur: 60, duree: 1.0, position: 0.0);
      expect(n.transposee(-12).hauteur, 48);
    });

    test('aller-retour JSON conserve les valeurs', () {
      final n = Note(hauteur: 67, duree: 0.5, position: 1.5);
      final copie = Note.fromJson(n.toJson());
      expect(copie.hauteur, 67);
      expect(copie.duree, 0.5);
      expect(copie.position, 1.5);
    });

    test('fromJson accepte un entier pour un champ double', () {
      // Un JSON peut contenir 1 au lieu de 1.0 pour la durée.
      final n = Note.fromJson({'hauteur': 60, 'duree': 1, 'position': 0});
      expect(n.duree, 1.0);
      expect(n.position, 0.0);
    });
  });
}
