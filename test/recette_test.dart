import 'dart:convert';

import 'package:test/test.dart';

import 'package:bizet_engine/bizet_engine.dart';

Melodie _partition() => Melodie(
      titre: 'Danube',
      source: 'Mutopia: StraussJJ/O314',
      tempo: 150,
      instrumentMidi: 0,
      mesures: [
        Mesure(notes: [Note(hauteur: 62, duree: 1.0, position: 0.0)]),
      ],
      armure: const Armure(tonique: 2, majeur: true),
    );

Recette _recette() => Recette(
      nom: 'Capture — niveau 1',
      morceaux: [
        MorceauRecette(
          partition: _partition(),
          poids: 2,
          bornes: const BornesRecette(
            tempo: Intervalle(120, 180),
            articulation: Intervalle(70, 100),
            swing: Intervalle(0, 1),
            rubato: Intervalle(1, 3),
            nuances: Intervalle(1, 2),
            epaisseur: Intervalle.fixe(0),
            octave: Intervalle(-1, 1),
            accompagnement: Intervalle(-3, -1),
            caractereOrigine: 80,
          ),
          instrumentation: const InstrumentationRecette.enCouples([
            CoupleInstruments(principal: 73, accompagnants: [24], poids: 2),
            CoupleInstruments(principal: 40, accompagnants: [24, 0]),
          ]),
        ),
      ],
    );

void main() {
  group('Recette', () {
    test('aller-retour JSON complet, mode couples', () {
      final Recette relue = Recette.fromJson(
          jsonDecode(jsonEncode(_recette().toJson())) as Map<String, dynamic>);

      expect(relue.version, Recette.versionCourante);
      expect(relue.nom, 'Capture — niveau 1');
      expect(relue.morceaux, hasLength(1));

      final MorceauRecette m = relue.morceaux.first;
      expect(m.partition.titre, 'Danube');
      expect(m.partition.armure?.majeur, isTrue);
      expect(m.poids, 2);
      expect(m.bornes.tempo.min, 120);
      expect(m.bornes.tempo.max, 180);
      expect(m.bornes.epaisseur.min, m.bornes.epaisseur.max);
      expect(m.bornes.caractereOrigine, 80);

      expect(m.instrumentation.mode, ModeInstrumentation.couples);
      expect(m.instrumentation.couples, hasLength(2));
      expect(m.instrumentation.couples.first.principal, 73);
      expect(m.instrumentation.couples.first.accompagnants, [24]);
      expect(m.instrumentation.couples.first.poids, 2);
      expect(m.instrumentation.couples.last.accompagnants, [24, 0]);
    });

    test('aller-retour JSON, mode libre — « tous » traverse comme nul', () {
      const InstrumentationRecette libre = InstrumentationRecette.libre(
        principaux: [40, 73],
        // accompagnants absents : tous ceux de la banque livrée.
      );

      final InstrumentationRecette relue = InstrumentationRecette.fromJson(
          jsonDecode(jsonEncode(libre.toJson())) as Map<String, dynamic>);

      expect(relue.mode, ModeInstrumentation.libre);
      expect(relue.principaux, [40, 73]);
      expect(relue.accompagnants, isNull);
    });

    test('une liste vide d\'accompagnants reste vide — la mélodie joue seule',
        () {
      const InstrumentationRecette seule =
          InstrumentationRecette.libre(accompagnants: []);

      final InstrumentationRecette relue = InstrumentationRecette.fromJson(
          jsonDecode(jsonEncode(seule.toJson())) as Map<String, dynamic>);

      expect(relue.principaux, isNull);
      expect(relue.accompagnants, isEmpty);
    });

    test('une version plus récente est refusée', () {
      final Map<String, dynamic> j = _recette().toJson();
      j['version'] = Recette.versionCourante + 1;
      expect(() => Recette.fromJson(j), throwsFormatException);
    });
  });
}
