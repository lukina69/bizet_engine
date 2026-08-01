import 'package:test/test.dart';

import 'package:bizet_engine/bizet_engine.dart';

Mesure _mesureExemple({bool selectionnee = true}) => Mesure(
      notes: [
        Note(hauteur: 60, duree: 1.0, position: 0.0),
        Note(hauteur: 64, duree: 1.0, position: 1.0),
      ],
      selectionnee: selectionnee,
    );

void main() {
  group('Mesure', () {
    test('selectionnee vaut true par défaut', () {
      expect(Mesure(notes: const []).selectionnee, isTrue);
    });

    test('transposee transpose toutes les notes et garde la sélection', () {
      final m = _mesureExemple(selectionnee: false).transposee(2);
      expect(m.notes.map((n) => n.hauteur), [62, 66]);
      expect(m.selectionnee, isFalse);
    });

    test('avecSelection change la sélection sans toucher aux notes', () {
      final m = _mesureExemple();
      final decochee = m.avecSelection(false);
      expect(decochee.selectionnee, isFalse);
      expect(decochee.notes, m.notes);
      // L'originale reste sélectionnée.
      expect(m.selectionnee, isTrue);
    });

    test('dureeDeduite prend la fin de la note qui se termine le plus tard', () {
      // Deux noires : la seconde finit au temps 2.0.
      expect(_mesureExemple().dureeDeduite, 2.0);
    });

    test('dureeEffective utilise la durée renseignée quand elle existe', () {
      // Mesure à 4 temps qui se termine par un silence de 2 temps.
      final m = Mesure(
        notes: [Note(hauteur: 60, duree: 1.0, position: 0.0)],
        duree: 4.0,
      );
      expect(m.dureeDeduite, 1.0);
      expect(m.dureeEffective, 4.0);
    });

    test('dureeEffective retombe sur la déduction si la durée est absente', () {
      expect(_mesureExemple().duree, isNull);
      expect(_mesureExemple().dureeEffective, 2.0);
    });

    test('transposee conserve la durée de la mesure', () {
      final m = Mesure(notes: const [], duree: 3.0).transposee(2);
      expect(m.duree, 3.0);
    });

    test('avecSelection conserve la durée de la mesure', () {
      final m = Mesure(notes: const [], duree: 3.0).avecSelection(false);
      expect(m.duree, 3.0);
    });

    test('aller-retour JSON conserve la durée', () {
      final m = Mesure(notes: const [], duree: 4.0);
      expect(Mesure.fromJson(m.toJson()).duree, 4.0);
    });

    test('fromJson laisse la durée nulle si le champ est absent', () {
      final copie = Mesure.fromJson({
        'notes': [
          {'hauteur': 60, 'duree': 1.0, 'position': 0.0}
        ]
      });
      expect(copie.duree, isNull);
      expect(copie.dureeEffective, 1.0);
    });

    test('aller-retour JSON conserve les notes et la sélection (option B)', () {
      final m = _mesureExemple(selectionnee: false);
      final copie = Mesure.fromJson(m.toJson());
      expect(copie.notes.length, 2);
      expect(copie.notes.first.hauteur, 60);
      expect(copie.selectionnee, isFalse);
    });

    test('fromJson retombe sur true si selectionnee est absent (ancien fichier)',
        () {
      final copie = Mesure.fromJson({
        'notes': [
          {'hauteur': 60, 'duree': 1.0, 'position': 0.0}
        ]
      });
      expect(copie.selectionnee, isTrue);
    });
  });
}
