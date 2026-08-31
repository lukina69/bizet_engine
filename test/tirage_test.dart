import 'package:test/test.dart';

import 'package:bizet_engine/bizet_engine.dart';

/// Une valse : des croches, de quoi balancer, une armure, des notes longues
/// où le rubato a prise.
Melodie _valse(String titre) => Melodie(
      titre: titre,
      source: 'Mutopia: exemple',
      tempo: 150,
      instrumentMidi: 0,
      mesures: [
        for (int m = 0; m < 4; m++)
          Mesure(
            notes: [
              Note(hauteur: 62, duree: 0.5, position: 0.0),
              Note(hauteur: 66, duree: 0.5, position: 0.5),
              Note(hauteur: 69, duree: 2.0, position: 1.0),
            ],
            duree: 3.0,
          ),
      ],
      armure: const Armure(tonique: 2, majeur: true),
    );

MorceauRecette _morceau(
  String titre, {
  int poids = 1,
  BornesRecette? bornes,
  InstrumentationRecette? instrumentation,
}) =>
    MorceauRecette(
      partition: _valse(titre),
      poids: poids,
      bornes: bornes ?? _bornesLarges,
      instrumentation: instrumentation ??
          const InstrumentationRecette.enCouples([
            CoupleInstruments(principal: 73, accompagnants: [24]),
          ]),
    );

const BornesRecette _bornesLarges = BornesRecette(
  tempo: Intervalle(90, 180),
  articulation: Intervalle(40, 100),
  swing: Intervalle(0, 3),
  rubato: Intervalle(0, 3),
  nuances: Intervalle(0, 2),
  epaisseur: Intervalle(0, 3),
  octave: Intervalle(-1, 1),
  accompagnement: Intervalle(-3, 0),
  caractereOrigine: 50,
);

const BornesRecette _bornesFigees = BornesRecette(
  tempo: Intervalle.fixe(120),
  articulation: Intervalle.fixe(100),
  swing: Intervalle.fixe(0),
  rubato: Intervalle.fixe(0),
  nuances: Intervalle.fixe(0),
  epaisseur: Intervalle.fixe(0),
  octave: Intervalle.fixe(0),
  accompagnement: Intervalle.fixe(-1),
);

Tirage _tirage(List<MorceauRecette> morceaux, {int graine = 1}) => Tirage(
      Recette(nom: 'essai', morceaux: morceaux),
      instrumentsDisponibles: const [0, 24, 40, 73],
      graine: graine,
    );

void main() {
  group('Tirage', () {
    test('des bornes figées donnent toujours le même réglage', () {
      final Tirage tirage = _tirage([_morceau('A', bornes: _bornesFigees)]);

      for (int tour = 0; tour < 20; tour++) {
        final Reglages r = tirage.prochain().reglages;
        expect(r.tempo, 120);
        expect(r.octave, 0);
        expect(r.balancement.swing, Swing.droit);
        expect(r.rubato, Rubato.mecanique);
        expect(r.nuances, Nuances.uniformes);
        expect(r.epaisseur, Epaisseur.simple);
        expect(r.volumes, [0, -1, -1],
            reason: 'le même cran aux deux voix ajoutées, la principale au repère');
      }
    });

    test('chaque valeur tirée reste dans sa borne', () {
      final Tirage tirage = _tirage([_morceau('A')]);

      for (int tour = 0; tour < 100; tour++) {
        final Reglages r = tirage.prochain().reglages;
        expect(r.tempo, inInclusiveRange(90, 180));
        expect(r.octave, inInclusiveRange(-1, 1));
        expect(r.volumeDe(1), inInclusiveRange(-3, 0));
        expect(r.volumeDe(2), r.volumeDe(1));
        // L'articulation part en multiplicateur de durée, pas en pourcentage.
        expect(r.articulation, inInclusiveRange(0.57, 1.05));
      }
    });

    test('le rubato respire d\'un tour à l\'autre : graine neuve à chaque fois',
        () {
      final Tirage tirage = _tirage([_morceau('A', bornes: _bornesFigees)]);

      final Set<int> graines = {
        for (int tour = 0; tour < 10; tour++) tirage.prochain().reglages.graine,
      };
      expect(graines.length, greaterThan(1));
    });

    test('même graine, même suite de tirages', () {
      final List<int> premiere = [
        for (int tour = 0; tour < 20; tour++)
          _tirage([_morceau('A')], graine: 7).prochain().reglages.tempo!,
      ];
      final List<int> seconde = [
        for (int tour = 0; tour < 20; tour++)
          _tirage([_morceau('A')], graine: 7).prochain().reglages.tempo!,
      ];
      expect(premiere, seconde);
    });

    test('le même morceau ne sort jamais deux fois de suite', () {
      final Tirage tirage =
          _tirage([_morceau('A'), _morceau('B'), _morceau('C')]);

      String precedent = '';
      final Set<String> vus = {};
      for (int tour = 0; tour < 60; tour++) {
        final String titre = tirage.prochain().partition.titre;
        expect(titre, isNot(precedent), reason: 'tour $tour');
        precedent = titre;
        vus.add(titre);
      }
      // Les trois sortent bien : l'interdiction ne fige pas un aller-retour.
      expect(vus, hasLength(3));
    });

    test('un morceau seul se répète, faute de mieux', () {
      final Tirage tirage = _tirage([_morceau('A')]);
      for (int tour = 0; tour < 5; tour++) {
        expect(tirage.prochain().partition.titre, 'A');
      }
    });

    test('le poids fait sortir un morceau plus souvent que l\'autre', () {
      final Tirage tirage = _tirage([
        _morceau('lourd', poids: 9),
        _morceau('leger'),
        _morceau('autre'),
      ]);

      int lourd = 0;
      for (int tour = 0; tour < 600; tour++) {
        if (tirage.prochain().partition.titre == 'lourd') lourd++;
      }

      // Sans les poids, un tiers des tours ; avec, nettement plus.
      expect(lourd, greaterThan(240));

      // Mais jamais plus de la moitié, quel que soit le poids :
      // l'interdiction de répétition immédiate met un tour sur deux hors
      // d'atteinte. C'est le plafond à connaître avant de monter un poids à 9
      // en espérant entendre un morceau « presque tout le temps ».
      expect(lourd, lessThanOrEqualTo(300));
    });

    test('les couples sortent entiers, jamais recomposés', () {
      final Tirage tirage = _tirage([
        _morceau(
          'A',
          instrumentation: const InstrumentationRecette.enCouples([
            CoupleInstruments(principal: 73, accompagnants: [24]),
            CoupleInstruments(principal: 40, accompagnants: [0, 24]),
          ]),
        ),
      ]);

      for (int tour = 0; tour < 60; tour++) {
        final Reglages r = tirage.prochain().reglages;
        final List<int?> voix = r.compagnons.rangs;
        if (r.instrument == 73) {
          expect(voix, [24, null]);
        } else {
          expect(r.instrument, 40);
          expect(voix, [0, 24]);
        }
      }
    });

    test('en mode libre, « tous » veut dire ce que la banque possède', () {
      final Tirage tirage = _tirage([
        _morceau('A', instrumentation: const InstrumentationRecette.libre()),
      ]);

      final Set<int> principaux = {};
      for (int tour = 0; tour < 100; tour++) {
        final Reglages r = tirage.prochain().reglages;
        expect(const [0, 24, 40, 73], contains(r.instrument));
        expect(const [0, 24, 40, 73], contains(r.compagnons.rangs.first));
        principaux.add(r.instrument!);
      }
      // Le hasard associe : sur cent tours, il ne s'est pas figé sur un seul.
      expect(principaux.length, greaterThan(1));
    });

    test('une liste vide d\'accompagnants laisse la mélodie seule', () {
      final Tirage tirage = _tirage([
        _morceau('A',
            instrumentation:
                const InstrumentationRecette.libre(accompagnants: [])),
      ]);

      for (int tour = 0; tour < 10; tour++) {
        expect(tirage.prochain().reglages.compagnons.rangs, [null, null]);
      }
    });

    test('un morceau sans armure reste dans son mode écrit', () {
      final Melodie sansArmure = Melodie(
        titre: 'nu',
        source: '',
        tempo: 120,
        instrumentMidi: 0,
        mesures: [
          Mesure(notes: [Note(hauteur: 60, duree: 1.0, position: 0.0)]),
        ],
      );

      final Tirage tirage = Tirage(
        Recette(nom: 'essai', morceaux: [
          MorceauRecette(
            partition: sansArmure,
            // Une borne qui réclamerait l'autre mode neuf fois sur dix.
            bornes: const BornesRecette(
              tempo: Intervalle.fixe(120),
              articulation: Intervalle.fixe(100),
              swing: Intervalle.fixe(0),
              rubato: Intervalle.fixe(0),
              nuances: Intervalle.fixe(0),
              epaisseur: Intervalle.fixe(0),
              octave: Intervalle.fixe(0),
              accompagnement: Intervalle.fixe(0),
              caractereOrigine: 10,
            ),
            instrumentation: const InstrumentationRecette.enCouples([
              CoupleInstruments(principal: 0),
            ]),
          ),
        ]),
        instrumentsDisponibles: const [0],
        graine: 3,
      );

      for (int tour = 0; tour < 20; tour++) {
        expect(tirage.prochain().reglages.majeur, isNull);
      }
    });

    test('un morceau qui ne balance ni ne respire ne se voit rien imposer',
        () {
      // Que des blanches, toutes pareilles : ni note entre les temps à
      // retarder, ni respiration où s'attarder.
      final Melodie plat = Melodie(
        titre: 'plat',
        source: '',
        tempo: 120,
        instrumentMidi: 0,
        mesures: [
          for (int m = 0; m < 4; m++)
            Mesure(
              notes: [
                Note(hauteur: 60, duree: 2.0, position: 0.0),
                Note(hauteur: 62, duree: 2.0, position: 2.0),
              ],
              duree: 4.0,
            ),
        ],
      );

      final Tirage tirage = Tirage(
        Recette(nom: 'essai', morceaux: [
          MorceauRecette(
            partition: plat,
            bornes: _bornesLarges,
            instrumentation: const InstrumentationRecette.enCouples([
              CoupleInstruments(principal: 0),
            ]),
          ),
        ]),
        instrumentsDisponibles: const [0],
        graine: 5,
      );

      for (int tour = 0; tour < 30; tour++) {
        final Reglages r = tirage.prochain().reglages;
        expect(r.balancement.swing, Swing.droit);
        expect(r.rubato, Rubato.mecanique);
      }
    });
  });
}
