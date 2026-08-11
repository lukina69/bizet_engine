import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bizet_engine/bizet_engine.dart';
import 'package:test/test.dart';

/// La banque de sons de l'application : trop lourde pour vivre ici, mais
/// c'est la seule façon d'éprouver un module dont le métier est de faire du
/// son. Les essais qui en dépendent se sautent d'eux-mêmes si elle manque.
final File _banque =
    File('../bizet/assets/soundfonts/Bizet_v4.sf2');

ByteData _octetsBanque() {
  final Uint8List octets = _banque.readAsBytesSync();
  return ByteData.view(octets.buffer, octets.offsetInBytes);
}

Melodie _valse() => Melodie(
      titre: 'Valse',
      source: 'Mutopia: exemple',
      tempo: 150,
      instrumentMidi: 0,
      mesures: [
        for (int m = 0; m < 3; m++)
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

String _recetteJson() => jsonEncode(Recette(
      nom: 'essai',
      morceaux: [
        MorceauRecette(
          partition: _valse(),
          bornes: const BornesRecette(
            tempo: Intervalle(120, 160),
            articulation: Intervalle(60, 100),
            swing: Intervalle(0, 1),
            rubato: Intervalle(0, 2),
            nuances: Intervalle(0, 2),
            epaisseur: Intervalle(0, 1),
            octave: Intervalle(-1, 0),
            accompagnement: Intervalle(-3, -1),
          ),
          instrumentation: const InstrumentationRecette.enCouples([
            CoupleInstruments(principal: 73, accompagnants: [24]),
          ]),
        ),
      ],
    ).toJson());

void main() {
  group('Scene', () {
    test('un fichier qui n\'est pas une recette se signale tout de suite', () {
      expect(
        () => Scene.depuisJson('ceci n\'est pas du JSON',
            soundFont: ByteData(0)),
        throwsA(isA<FormatException>()),
      );
    });

    test('une recette d\'une version inconnue est refusée', () {
      final Map<String, dynamic> j =
          jsonDecode(_recetteJson()) as Map<String, dynamic>;
      j['version'] = Recette.versionCourante + 1;

      expect(
        () => Scene.depuisJson(jsonEncode(j), soundFont: ByteData(0)),
        throwsA(isA<FormatException>()),
      );
    });

    group('avec la banque de sons', () {
      late Scene scene;

      setUp(() {
        scene = Scene.depuisJson(
          _recetteJson(),
          soundFont: _octetsBanque(),
          graine: 12,
        );
      });

      test('la banque annonce les sonorités qu\'elle sait jouer', () {
        expect(scene.instrumentsDisponibles, isNotEmpty);
        expect(scene.instrumentsDisponibles, contains(73));
      });

      test('une boucle rend du son, et dit ce que le sort a choisi', () {
        final Boucle boucle = scene.prochaine();

        expect(boucle.partition.titre, 'Valse');
        expect(boucle.reglages.tempo, inInclusiveRange(120, 160));
        expect(boucle.reglages.instrument, 73);

        // Neuf temps à 120–160 BPM font entre 3,4 et 4,5 secondes, plus la
        // seconde de queue laissée aux notes pour s'éteindre.
        expect(boucle.secondes, inInclusiveRange(4.0, 6.0));

        // Et ce n'est pas du silence : le rendu a bien fait sonner la valse.
        int pic = 0;
        for (int i = 0; i < boucle.echantillons; i++) {
          final int v = (boucle.son[i] as int).abs();
          if (v > pic) pic = v;
        }
        expect(pic, greaterThan(1000));
      });

      test('deux boucles ne sonnent pas pareil', () {
        final List<Boucle> tours = [
          for (int tour = 0; tour < 6; tour++) scene.prochaine(),
        ];

        // Le tempo suffit à le montrer : sur six tours dans une borne de
        // quarante crans, ils ne peuvent pas tous être tombés au même.
        expect(tours.map((b) => b.reglages.tempo).toSet().length,
            greaterThan(1));
        // Et chacun respire à ses propres endroits.
        expect(tours.map((b) => b.reglages.graine).toSet(), hasLength(6));
      });

      test('l\'amorce et sa suite, bout à bout, font le tour entier '
          'à l\'échantillon près', () {
        Scene autre() => Scene.depuisJson(
              _recetteJson(),
              soundFont: _octetsBanque(),
              graine: 12,
            );

        final Boucle entiere = autre().prochaine();
        final BoucleAmorcee amorcee = autre().prochaineAmorcee();

        // Même graine, donc même tirage : c'est bien le même tour.
        expect(amorcee.reglages.tempo, entiere.reglages.tempo);

        // L'amorce n'est pas vide, et ne couvre que le début du tour.
        expect(amorcee.echantillonsAmorce, greaterThan(0));
        expect(amorcee.echantillonsAmorce, lessThan(entiere.echantillons));

        final suite = amorcee.suite();
        final int echantillonsSuite = suite.bytes.lengthInBytes ~/ 2;
        expect(amorcee.echantillonsAmorce + echantillonsSuite,
            entiere.echantillons);

        // Bout à bout, pas un échantillon ne diffère : une note tenue
        // traverse la coupure, la réverbération aussi.
        for (int i = 0; i < amorcee.echantillonsAmorce; i++) {
          if (amorcee.amorce[i] != entiere.son[i]) {
            fail('écart dans l\'amorce à l\'échantillon $i');
          }
        }
        for (int i = 0; i < echantillonsSuite; i++) {
          if (suite[i] != entiere.son[amorcee.echantillonsAmorce + i]) {
            fail('écart dans la suite à l\'échantillon $i');
          }
        }
      });

      test('la suite ne se rend qu\'une fois, et avant tout autre rendu', () {
        final BoucleAmorcee premiere = scene.prochaineAmorcee();
        premiere.suite();
        expect(premiere.suite, throwsStateError);

        // Un autre rendu passé derrière l'amorce invalide sa suite : le
        // synthétiseur ne lui appartient plus, mieux vaut une erreur qu'un
        // son qui n'a plus rien à voir.
        final BoucleAmorcee abandonnee = scene.prochaineAmorcee();
        scene.prochaine();
        expect(abandonnee.suite, throwsStateError);
      });

      test('la même graine rejoue exactement la même suite', () {
        Scene autre() => Scene.depuisJson(
              _recetteJson(),
              soundFont: _octetsBanque(),
              graine: 99,
            );

        final List<int> premiere = [
          for (int tour = 0; tour < 5; tour++)
            autre().prochaine().reglages.tempo!,
        ];
        final List<int> seconde = [
          for (int tour = 0; tour < 5; tour++)
            autre().prochaine().reglages.tempo!,
        ];
        expect(premiere, seconde);
      });
    },
        skip: _banque.existsSync()
            ? null
            : 'banque de sons absente : ${_banque.path}');
  });
}
