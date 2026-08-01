import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:bizet_engine/bizet_engine.dart';

/// Le moteur bout à bout, hors de toute application : un fichier LilyPond est
/// lu, transformé, puis écrit en MIDI — le tout en ligne de commande, sans
/// Flutter et sans appareil. C'est le gain de l'extraction, et ce test est là
/// pour le prouver.
void main() {
  Melodie ouvrir() => LilypondParser().parse(
        File('test/fixtures/vocalise1.ly').readAsStringSync(),
      );

  test('un .ly se lit, se transpose et sonne une quinte plus haut', () {
    final Melodie origine = ouvrir();
    expect(origine.mesures, isNotEmpty);

    final Melodie transposee = origine.transposee(7);

    final List<int> avant =
        origine.mesures.expand((m) => m.notes).map((n) => n.hauteur).toList();
    final List<int> apres = transposee.mesures
        .expand((m) => m.notes)
        .map((n) => n.hauteur)
        .toList();

    expect(apres.length, avant.length);
    expect(apres, [for (final h in avant) h + 7]);

    // La transposition ne touche à rien d'autre : même montage, même tempo.
    expect(transposee.tempo, origine.tempo);
    expect(transposee.mesures.length, origine.mesures.length);
  });

  test('la mélodie lue s\'écrit en MIDI', () {
    final Uint8List midi = ExportMusical().versMidi(ouvrir());

    // En-tête d'un fichier MIDI standard : « MThd ».
    expect(midi.sublist(0, 4), [0x4D, 0x54, 0x68, 0x64]);
    // Une seule piste, annoncée par « MTrk ».
    expect(midi.sublist(14, 18), [0x4D, 0x54, 0x72, 0x6B]);
    expect(midi.length, greaterThan(100));
  });
}
