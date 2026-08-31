import 'package:bizet_engine/bizet_engine.dart';
import 'package:test/test.dart';

/// Un morceau court, dans le registre du chant.
Melodie _morceau() => Melodie(
      titre: '',
      source: '',
      tempo: 100,
      instrumentMidi: 0,
      mesures: [
        Mesure(notes: [
          Note(hauteur: 60, duree: 2.0, position: 0.0),
          Note(hauteur: 67, duree: 2.0, position: 2.0),
        ], duree: 4.0),
      ],
    );

void main() {
  group('les voix se posent sur leurs canaux', () {
    // Trois voix, la principale doublée à l'octave de part et d'autre : c'est
    // la configuration la plus chargée que l'appli sache produire aujourd'hui.
    final Reglages riches = Reglages(
      instrument: 0, // piano
      epaisseur: Epaisseur.large, // trois canaux
      compagnons: Compagnons([73, 42]), // flûte, violoncelle
      volumes: const [0, -1, -1],
    );

    test('chaque voix prend ses canaux à la suite', () {
      final List<VoixJouee> jouees = riches.voixJouees(_morceau());

      expect(jouees.map((j) => j.rang), [0, 1, 2]);
      expect(jouees.map((j) => j.premierCanal), [0, 3, 4],
          reason: 'la principale occupe 0, 1 et 2 avec ses doublages');
      expect(jouees.map((j) => j.programme), [0, 73, 42]);
    });

    test('une voix éteinte garde son canal réservé', () {
      // Sans cela, éteindre la première déplacerait la seconde au milieu d'un
      // morceau : une note tenue se retrouverait sur un canal qui vient de
      // changer d'instrument.
      final List<VoixJouee> jouees = Reglages(
        instrument: 0,
        epaisseur: Epaisseur.large,
        compagnons: Compagnons([null, 42]),
        volumes: const [0, -1, -1],
      ).voixJouees(_morceau());

      expect(jouees.map((j) => j.rang), [0, 2]);
      expect(jouees.map((j) => j.premierCanal), [0, 4],
          reason: 'le violoncelle ne remonte pas sur le canal libéré');
    });

    test('chaque voix porte son niveau : égalisation, puis volume', () {
      final List<VoixJouee> jouees = riches.voixJouees(_morceau());

      // La principale n'a que l'égalisation ; les ajoutées reçoivent en plus
      // le cran de retrait demandé.
      expect(jouees[0].niveau, closeTo(correctionEgalisation(0), 1e-9));
      expect(jouees[1].niveau,
          closeTo(correctionEgalisation(73) - Voix.dbParCran, 1e-9));
      expect(jouees[2].niveau,
          closeTo(correctionEgalisation(42) - Voix.dbParCran, 1e-9));
    });

    test('chaque voix a son volume, la principale comprise', () {
      // L'ancien bouton « accompagnement » valait pour les deux voix ajoutées
      // à la fois, et n'offrait rien à la principale. C'est cette main-là qui
      // rattrape ce que la mesure ne voit pas : le poids se mesure sur une
      // note tenue, et une percussion s'y trouve toujours sous-estimée.
      final List<VoixJouee> jouees = Reglages(
        instrument: 0,
        compagnons: Compagnons([73, 42]),
        volumes: const [-1, 0, -3],
      ).voixJouees(_morceau());

      expect(jouees[0].niveau,
          closeTo(correctionEgalisation(0) - Voix.dbParCran, 1e-9));
      expect(jouees[1].niveau, closeTo(correctionEgalisation(73), 1e-9),
          reason: 'celle-ci reste au repère');
      expect(jouees[2].niveau,
          closeTo(correctionEgalisation(42) - 3 * Voix.dbParCran, 1e-9));
    });

    test('un volume manquant vaut zéro plutôt que de faire tomber', () {
      // Un fichier de travail écrit par une autre version ne doit pas
      // fabriquer un objet bancal.
      const Reglages court = Reglages(volumes: [-2]);
      expect(court.volumeDe(0), -2);
      expect(court.volumeDe(1), 0);
      expect(court.volumeDe(2), 0);
    });

    test('les voix ajoutées se calent, la principale reste où elle est', () {
      // La flûte (tessiture 60-96) est chez elle sur ce morceau ; le
      // violoncelle (36-76) aussi. Aucune n'a besoin de bouger.
      final List<VoixJouee> jouees = riches.voixJouees(_morceau());
      expect(jouees.every((j) => j.octave == 0), isTrue);

      // Sur une ligne deux octaves plus bas, la flûte monte et la voix
      // principale, elle, ne bouge pas : le calage automatique ne s'applique
      // qu'aux voix ajoutées — c'est le chantier suivant.
      final Melodie grave = _morceau().transposee(-24);
      final List<VoixJouee> basses = riches.voixJouees(grave);
      expect(basses[0].octave, 0, reason: 'la principale reste écrite');
      expect(basses[1].octave, greaterThan(0), reason: 'la flûte remonte');
    });

    test('la brillance descend sur toutes les voix, chacune à son recul', () {
      // Les doublages de la principale restent 10 et 25 crans sous elle ; les
      // voix ajoutées 20 et 35 — l'ancien retrait d'attaque, que le volume par
      // voix rendra inutile.
      final List<Voix> rangs = riches.voix;
      expect(rangs[0].recul, 0);
      expect(rangs[1].recul, 20);
      expect(rangs[2].recul, 35);

      const int brillance = Epaisseur.velociteBase;
      expect(
        [for (final v in rangs[0].epaisseur.voix(60, brillance: brillance)) v.velocite],
        [brillance, brillance - 10, brillance - 25],
      );
      for (final int rang in const [1, 2]) {
        expect(
          rangs[rang]
              .epaisseur
              .voix(60, brillance: brillance - rangs[rang].recul)
              .single
              .velocite,
          brillance - rangs[rang].recul,
        );
      }
    });

    test('le rubato appartient au chef, pas aux voix', () {
      // Deux voix qui respireraient chacune de leur côté se
      // désynchroniseraient. Les écarts se calculent une fois et se
      // partagent : le même appel doit donc rendre exactement la même chose.
      final Melodie morceau = _morceau();
      final Reglages respire = Reglages(rubato: Rubato.expressif, graine: 7);

      expect(respire.rubatoDe(morceau), respire.rubatoDe(morceau));
      expect(
        respire.notesSonnantes(morceau, ecarts: respire.rubatoDe(morceau)),
        respire.notesSonnantes(morceau),
      );
    });
  });
}
