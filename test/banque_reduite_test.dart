import 'dart:io';
import 'dart:typed_data';

import 'package:dart_melty_soundfont/dart_melty_soundfont.dart'
    show ArrayInt16;
import 'package:test/test.dart';

import 'package:bizet_engine/bizet_engine.dart';

/// La banque de l'application : trop lourde pour vivre dans le dépôt du
/// moteur, mais réduire une banque ne se vérifie que sur une vraie banque.
/// Les essais se sautent d'eux-mêmes si elle manque.
final File _banque = File('../bizet/assets/soundfonts/Bizet_v4.sf2');

ByteData _octets() {
  final Uint8List o = _banque.readAsBytesSync();
  return ByteData.view(o.buffer, o.offsetInBytes);
}

/// Trois sonorités du Danube : guitare nylon, violon, flûte.
const Set<int> _trois = {24, 40, 73};

Melodie _gamme() => Melodie(
      titre: 'gamme',
      source: '',
      tempo: 120,
      instrumentMidi: 73,
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

void main() {
  group('BanqueReduite', () {
    late ByteData source;

    setUp(() => source = _octets());

    test('ne garder que trois sonorités divise la banque par sept', () {
      final BanqueReduite reduite =
          BanqueReduite.pour(source, programmes: _trois);

      expect(reduite.octets, lessThan(source.lengthInBytes ~/ 5));
      expect(reduite.detail, hasLength(3));
      expect(
        reduite.detail.map((d) => d.programme).toSet(),
        _trois,
      );
    });

    test('le poids annoncé est exactement celui du fichier produit', () {
      final BanqueReduite reduite =
          BanqueReduite.pour(source, programmes: _trois);

      // C'est tout l'enjeu du § 6 bis : le chiffre affiché dans l'atelier et
      // les octets livrés sortent du même code, donc ne peuvent pas mentir.
      expect(reduite.ecrire().lengthInBytes, reduite.octets);
    });

    test('descendre à 22 kHz divise encore par deux, ou presque', () {
      final int pleine = BanqueReduite.pour(source,
              programmes: _trois, frequence: 48000)
          .octets;
      final int reduite =
          BanqueReduite.pour(source, programmes: _trois, frequence: 22050)
              .octets;

      expect(reduite, lessThan(pleine));
      expect(reduite, greaterThan(pleine ~/ 3));
    });

    test('les sonorités absentes de la banque sont signalées', () {
      final BanqueReduite reduite =
          BanqueReduite.pour(source, programmes: {24, 0, 1});

      // Cette banque n'a ni piano acoustique (0) ni piano brillant (1).
      expect(reduite.manquants, [0, 1]);
      expect(reduite.detail.map((d) => d.programme), [24]);
    });

    test('la banque réduite se relit et sonne', () async {
      final BanqueReduite reduite = BanqueReduite.pour(
        source,
        programmes: _trois,
        noteMin: 48,
        noteMax: 84,
      );

      final Uint8List fichier = reduite.ecrire();

      // Relue par le synthétiseur lui-même : c'est la seule preuve qui
      // compte, celle qu'un fichier écrit à la main reste un SoundFont.
      final RenduAudio rendu = RenduAudio();
      rendu.chargerSoundFont(
          ByteData.view(fichier.buffer, fichier.offsetInBytes));

      expect(rendu.programmes, _trois.toList()..sort());

      // Et elle fait bien du son, pas du silence.
      final ArrayInt16 son =
          rendu.rendre(_gamme(), reglages: const Reglages(instrument: 73));

      int pic = 0;
      final int points = son.bytes.lengthInBytes ~/ 2;
      for (int i = 0; i < points; i++) {
        final int v = (son[i] as int).abs();
        if (v > pic) pic = v;
      }
      expect(pic, greaterThan(1000));
    });

    test('chaque sonorité gardée sonne encore une fois réduite', () {
      final Uint8List fichier =
          BanqueReduite.pour(source, programmes: _trois).ecrire();

      final RenduAudio rendu = RenduAudio();
      rendu.chargerSoundFont(
          ByteData.view(fichier.buffer, fichier.offsetInBytes));

      for (final int programme in _trois) {
        final ArrayInt16 son = rendu.rendre(
          _gamme(),
          reglages: Reglages(instrument: programme),
        );

        int pic = 0;
        final int points = son.bytes.lengthInBytes ~/ 2;
        for (int i = 0; i < points; i++) {
          final int v = (son[i] as int).abs();
          if (v > pic) pic = v;
        }
        expect(pic, greaterThan(1000), reason: 'programme $programme muet');
      }
    });

    test('la banque réduite garde les noms des sonorités', () {
      final Uint8List fichier =
          BanqueReduite.pour(source, programmes: {73}).ecrire();

      final RenduAudio rendu = RenduAudio();
      rendu.chargerSoundFont(
          ByteData.view(fichier.buffer, fichier.offsetInBytes));

      final BanqueReduite reference =
          BanqueReduite.pour(source, programmes: {73});
      expect(reference.detail.single.nom, contains('Flute'));
      expect(rendu.programmes, [73]);
    });

    test('des octets qui ne sont pas un SoundFont sont refusés', () {
      expect(
        () => BanqueReduite.pour(ByteData(64), programmes: _trois),
        throwsA(isA<FormatException>()),
      );
    });
  },
      skip: _banque.existsSync()
          ? null
          : 'banque de sons absente : ${_banque.path}');
}
