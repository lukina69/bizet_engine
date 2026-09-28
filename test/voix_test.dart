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

    test('toutes les voix se calent, la principale comprise', () {
      // La flûte (tessiture 60-96) est chez elle sur ce morceau ; le
      // violoncelle (36-76) aussi. Aucune n'a besoin de bouger.
      final List<VoixJouee> jouees = riches.voixJouees(_morceau());
      expect(jouees.every((j) => j.octave == 0), isTrue);

      // Sur une ligne deux octaves plus bas, la flûte remonte, et la voix
      // principale aussi quand sa sonorité n'y descend pas. Elle jouait
      // jusqu'ici à la hauteur écrite, ce qui faisait deux poids deux mesures
      // pour un défaut qui s'entend.
      final Melodie grave = _morceau().transposee(-24);
      expect(riches.voixJouees(grave)[1].octave, greaterThan(0),
          reason: 'la flûte ajoutée remonte');

      // La flûte (60-96) en voix principale sur une ligne à 36 : elle remonte
      // de deux octaves pour retrouver son registre.
      final Reglages seule = Reglages(voix: [const Voix(instrument: 73)]);
      expect(seule.voixJouees(grave).single.octave, 2,
          reason: 'la flûte ne descend pas si bas');
    });

    test('le réglage d\'octave s\'ajoute au calage, il ne le remplace pas', () {
      // C'est ce qui donne son sens au zéro du curseur : « là où cette voix
      // sonne bien », et non « à la hauteur écrite ».
      final Melodie grave = _morceau().transposee(-24);

      final int naturelle =
          Reglages(voix: [const Voix(instrument: 73)]).voixJouees(grave)
              .single.octave;
      final int demandee =
          Reglages(voix: [const Voix(instrument: 73, octave: -1)])
              .voixJouees(grave).single.octave;

      expect(demandee, naturelle - 1);
    });

    test('le calage ne pousse jamais une note hors du clavier', () {
      // Le calage et le réglage de l'utilisateur s'ajoutent : sur une mélodie
      // aiguë, deux octaves plus deux passaient au-delà de la note 127. Ces
      // notes-là ne sonnent pas, elles disparaissent sans un mot.
      final Melodie haute = Melodie(
        titre: '',
        source: '',
        tempo: 120,
        instrumentMidi: 0,
        mesures: [
          Mesure(notes: [
            Note(hauteur: 100, duree: 1.0, position: 0.0),
            Note(hauteur: 107, duree: 1.0, position: 1.0),
          ], duree: 4.0),
        ],
      );

      for (final int demande in const [-2, 0, 2]) {
        final VoixJouee jouee =
            Reglages(voix: [Voix(instrument: 58, octave: demande)])
                .voixJouees(haute)
                .single;
        for (final mesure in haute.mesures) {
          for (final note in mesure.notes) {
            expect(note.hauteur + 12 * jouee.octave, inInclusiveRange(0, 127),
                reason: 'octave demandée $demande');
          }
        }
      }
    });

    test('une sonorité que le catalogue ignore reste où elle est écrite', () {
      // Une tessiture musicale se saisit à la main, elle ne se mesure pas
      // comme un poids : mieux vaut ne pas caler que caler au hasard.
      expect(instrumentParProgramme(99), isNull);
      final Melodie grave = _morceau().transposee(-24);
      expect(
        Reglages(voix: [const Voix(instrument: 99)]).voixJouees(grave)
            .single.octave,
        0,
      );
    });

    test('toutes les voix partent de la même attaque', () {
      // Les voix ajoutées frappaient vingt et trente-cinq crans plus mollement
      // que la mélodie. C'était le seul moyen de les mettre en retrait avant
      // que le niveau ait son propre chemin, et ça leur coûtait leur timbre :
      // une flûte discrète ne sonnait pas comme une flûte en avant. Le volume
      // par voix fait ce travail sans toucher au son.
      const int brillance = Epaisseur.velociteBase;
      for (final Voix v in riches.voix) {
        expect(v.epaisseur.voix(60, brillance: brillance).first.velocite,
            brillance);
      }

      // Les doublages d'une même voix gardent le leur : eux sont là pour
      // épaissir sans couvrir la ligne qu'ils doublent.
      expect(
        [
          for (final v in Epaisseur.large.voix(60, brillance: brillance))
            v.velocite,
        ],
        [brillance, brillance - 10, brillance - 25],
      );
    });

    test('des voix réglées une à une prennent le dessus sur les champs à plat',
        () {
      // C'est le pont : tant que la scène règle un morceau d'un bloc, les deux
      // chemins cohabitent. Ce qui compte est que l'hôte qui fournit ses voix
      // ne se fasse pas écraser par les anciens champs.
      final Reglages regle = Reglages(
        articulation: 1.0,
        epaisseur: Epaisseur.large,
        voix: [
          const Voix(instrument: 0, articulation: 0.4),
          const Voix(instrument: 73, articulation: 1.0),
        ],
      );

      expect(regle.voix.map((v) => v.articulation), [0.4, 1.0, 1.0],
          reason: 'chaque voix garde la sienne, la troisième prend le défaut');
      expect(regle.voix.first.epaisseur, Epaisseur.simple,
          reason: 'le champ à plat ne déborde plus sur la voix');
      expect(regle.voix.length, Reglages.voixMaximum,
          reason: 'la liste est complétée, jamais bancale');
    });

    test('sans voix fournies, rien ne change pour la scène', () {
      final Reglages ancien = Reglages(
        instrument: 0,
        articulation: 0.4,
        epaisseur: Epaisseur.large,
        compagnons: Compagnons([73, null]),
      );

      expect(ancien.voix[0].instrument, 0);
      expect(ancien.voix[0].epaisseur, Epaisseur.large);
      expect(ancien.voix[1].instrument, 73);
      expect(ancien.voix.map((v) => v.articulation), [0.4, 0.4, 0.4],
          reason: 'l\'ancien modèle imposait la même à toutes');
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
