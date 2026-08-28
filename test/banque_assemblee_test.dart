import 'dart:io';
import 'dart:typed_data';

import 'package:dart_melty_soundfont/dart_melty_soundfont.dart' show ArrayInt16;
import 'package:test/test.dart';

import 'package:bizet_engine/bizet_engine.dart';

/// La banque de l'application, comme pour [BanqueReduite] : recoller ne se
/// vérifie que sur de vraies banques. Les essais se sautent si elle manque.
final File _banque = File('../bizet/assets/soundfonts/Bizet_v4.sf2');

/// La banque complète de MuseScore, d'où viennent les sonorités que l'appli
/// propose au téléchargement. Trop lourde pour le dépôt (215 Mo), gardée à
/// côté ; c'est la seule où deux sonorités partagent vraiment leurs
/// échantillons, donc la seule où la déduplication se vérifie.
final File _museScore = File('../bizet/docs/MuseScore_General_officielle.sf2');

ByteData _octets() {
  final Uint8List o = _banque.readAsBytesSync();
  return ByteData.view(o.buffer, o.offsetInBytes);
}

ByteData _vue(Uint8List o) => ByteData.view(o.buffer, o.offsetInBytes);

/// Une sonorité seule, taillée dans la banque sans rien rééchantillonner
/// (48 000 Hz est au-dessus de tout ce qu'elle contient).
ByteData _seule(ByteData source, int programme) => _vue(
  BanqueReduite.pour(
    source,
    programmes: {programme},
    frequence: 48000,
  ).ecrire(),
);

Melodie _gamme(int instrument) => Melodie(
  titre: 'gamme',
  source: '',
  tempo: 120,
  instrumentMidi: instrument,
  mesures: [
    Mesure(
      notes: [
        for (int i = 0; i < 8; i++)
          Note(hauteur: 60 + i, duree: 0.5, position: i * 0.5),
      ],
      duree: 4.0,
    ),
  ],
);

ArrayInt16 _rendre(ByteData banque, int instrument) {
  final RenduAudio rendu = RenduAudio();
  rendu.chargerSoundFont(banque);
  return rendu.rendre(
    _gamme(instrument),
    reglages: Reglages(instrument: instrument),
  );
}

int _pic(ArrayInt16 son) {
  int pic = 0;
  final int points = son.bytes.lengthInBytes ~/ 2;
  for (int i = 0; i < points; i++) {
    final int v = (son[i] as int).abs();
    if (v > pic) pic = v;
  }
  return pic;
}

void main() {
  group(
    'BanqueAssemblee',
    () {
      late ByteData source;
      late List<int> programmes;

      setUpAll(() {
        source = _octets();
        final RenduAudio rendu = RenduAudio();
        rendu.chargerSoundFont(source);
        programmes = rendu.programmes;
      });

      test('découpée en une banque par sonorité puis recollée, la banque sonne '
          'à l\'identique', () {
        // Le test de vérité : chaque sonorité dans son propre fichier, comme
        // elles arriveront du téléchargement, puis tout recollé.
        final BanqueAssemblee assemblee = BanqueAssemblee.de([
          for (final int p in programmes) _seule(source, p),
        ]);

        expect(assemblee.programmes, programmes);
        expect(assemblee.ignores, isEmpty);

        final ByteData recollee = _vue(assemblee.ecrire());

        // Flûte, violon, boîte à musique : trois familles, et le même son au
        // point près que la banque d'origine.
        for (final int instrument in [73, 40, 10]) {
          final ArrayInt16 avant = _rendre(source, instrument);
          final ArrayInt16 apres = _rendre(recollee, instrument);
          expect(
            Uint8List.sublistView(apres.bytes),
            Uint8List.sublistView(avant.bytes),
            reason: 'programme $instrument',
          );
          // Et ce qu'on compare est bien du son, pas deux silences égaux — la
          // boîte à musique, la plus discrète de la banque, culmine sous 1 000.
          expect(
            _pic(apres),
            greaterThan(150),
            reason: 'programme $instrument',
          );
        }
      });

      test('le poids annoncé est exactement celui du fichier produit', () {
        final BanqueAssemblee assemblee = BanqueAssemblee.de([
          _seule(source, 73),
          _seule(source, 40),
        ]);

        expect(assemblee.ecrire().lengthInBytes, assemblee.octets);
      });

      test('une sonorité apportée deux fois n\'est gardée qu\'une fois, et '
          'c\'est dit', () {
        final BanqueAssemblee assemblee = BanqueAssemblee.de([
          _seule(source, 73),
          _seule(source, 73),
          _seule(source, 10),
        ]);

        expect(assemblee.programmes, [10, 73]);
        expect(assemblee.ignores, [73]);

        final RenduAudio rendu = RenduAudio();
        rendu.chargerSoundFont(_vue(assemblee.ecrire()));
        expect(rendu.programmes, [10, 73]);
      });

      test('deux sonorités qui partagent leurs échantillons ne les paient '
        'qu\'une fois', () {
      // Dans MuseScore_General, les cordes rapides (48), lentes (49) et en
      // trémolo (44) sont le même enregistrement joué autrement : mêmes
      // 5,6 Mo de son, enveloppes différentes. Les télécharger toutes les
      // trois ne doit pas coûter trois fois le prix d'une.
      final Uint8List octets = _museScore.readAsBytesSync();
      final ByteData source = ByteData.view(
        octets.buffer,
        octets.offsetInBytes,
      );

      ByteData cordes(int programme) => _vue(
            BanqueReduite.pour(
              source,
              programmes: {programme},
              frequence: 48000,
            ).ecrire(),
          );

      final ByteData rapides = cordes(48);
      final BanqueAssemblee seule = BanqueAssemblee.de([rapides]);
      final BanqueAssemblee trois = BanqueAssemblee.de([
        rapides,
        cordes(49),
        cordes(44),
      ]);

      expect(trois.programmes, [44, 48, 49]);
      expect(seule.echantillonsPartages, 0);
      expect(trois.echantillonsPartages, greaterThan(0));

      // Le poids des trois reste celui d'une, à la marge des en-têtes près.
      expect(trois.octets, lessThan((seule.octets * 1.1).round()));

      // Et les trois sonnent, chacune la sienne : partager les échantillons
      // ne doit pas les avoir confondues.
      final ByteData recollee = _vue(trois.ecrire());
      for (final int programme in [44, 48, 49]) {
        expect(
          _pic(_rendre(recollee, programme)),
          greaterThan(150),
          reason: 'programme $programme muet',
        );
      }
    }, skip: _museScore.existsSync()
        ? null
        : 'banque MuseScore absente : ${_museScore.path}');

    test('des octets qui ne sont pas un SoundFont sont refusés', () {
        expect(
          () => BanqueAssemblee.de([_seule(source, 73), ByteData(64)]),
          throwsA(isA<FormatException>()),
        );
      });
    },
    skip: _banque.existsSync()
        ? null
        : 'banque de sons absente : ${_banque.path}',
  );
}
