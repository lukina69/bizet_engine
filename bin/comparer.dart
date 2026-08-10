import 'dart:io';
import 'dart:typed_data';

import 'package:bizet_engine/bizet_engine.dart';
import 'package:dart_melty_soundfont/dart_melty_soundfont.dart'
    show ArrayInt16;

/// Compare à l'oreille ce que coûte la réduction de banque.
///
/// Le même tirage — même graine, donc mêmes instruments, même tempo, mêmes
/// respirations — rendu avec la banque telle quelle puis avec des banques
/// réduites. Un WAV par qualité, à écouter l'un après l'autre. C'est la
/// seule façon de décider si le brillant perdu se remarque.
///
///     dart run bizet_engine:comparer <recette.json> <banque.sf2> [graine]
Future<void> main(List<String> arguments) async {
  if (arguments.length < 2) {
    stderr.writeln('Usage : dart run bizet_engine:comparer '
        '<recette.json> <banque.sf2> [graine]');
    exitCode = 64;
    return;
  }

  final String recette = await File(arguments[0]).readAsString();
  final Uint8List banque = await File(arguments[1]).readAsBytes();
  final ByteData source =
      ByteData.view(banque.buffer, banque.offsetInBytes);
  final int graine = arguments.length > 2 ? int.parse(arguments[2]) : 7;

  // Ce que la recette réclame : c'est la même lecture que fera l'export.
  final Recette lue = Recette.fromJson(
      (Scene.depuisJson(recette, soundFont: source, graine: graine)).recette
          .toJson());

  final Set<int> programmes = {};
  int bas = 127;
  int haut = 0;
  for (final MorceauRecette m in lue.morceaux) {
    final InstrumentationRecette i = m.instrumentation;
    if (i.mode == ModeInstrumentation.couples) {
      for (final CoupleInstruments c in i.couples) {
        programmes.add(c.principal);
        programmes.addAll(c.accompagnants);
      }
    } else {
      programmes.addAll(i.principaux ?? const []);
      programmes.addAll(i.accompagnants ?? const []);
    }
    for (final mesure in m.partition.mesures) {
      for (final note in mesure.notes) {
        final int plancher = note.hauteur + 12 * m.bornes.octave.min - 12;
        final int plafond = note.hauteur + 12 * m.bornes.octave.max + 12;
        if (plancher < bas) bas = plancher;
        if (plafond > haut) haut = plafond;
      }
    }
  }

  stdout.writeln('Instruments réclamés : ${programmes.toList()..sort()}');
  stdout.writeln('Ambitus à couvrir    : $bas – $haut');
  stdout.writeln('');

  final String base = arguments[0].replaceAll(RegExp(r'(\.recette)?\.json$'), '');

  /// Rend trois boucles du même tirage avec la banque fournie.
  Future<void> rendre(String etiquette, ByteData avec, int poids) async {
    final Scene scene =
        Scene.depuisJson(recette, soundFont: avec, graine: graine);

    final List<Boucle> tours = [
      for (int i = 0; i < 3; i++) scene.prochaine(),
    ];

    final int total = tours.fold(0, (somme, b) => somme + b.echantillons);
    final ArrayInt16 tout = ArrayInt16.zeros(numShorts: total);
    int position = 0;
    for (final Boucle b in tours) {
      for (int i = 0; i < b.echantillons; i++) {
        tout[position + i] = b.son[i] as int;
      }
      position += b.echantillons;
    }

    final String sortie = '$base-$etiquette.wav';
    await File(sortie)
        .writeAsBytes(ExportMusical().versWav(tout, frequence: Scene.frequence),
            flush: true);

    stdout.writeln('  $sortie '
        '— banque ${(poids / 1000000).toStringAsFixed(2)} Mo');
  }

  stdout.writeln('Trois boucles du même tirage (graine $graine) :');

  await rendre('01-banque-complete', source, banque.lengthInBytes);

  // Les mêmes instruments, mais seuls : c'est le levier le plus fort, et il
  // ne coûte rien à l'oreille — les échantillons sont intacts.
  for (final (String etiquette, int frequence) in const [
    ('02-instruments-seuls', 48000),
    ('03-22khz', 22050),
    ('04-16khz', 16000),
    ('05-11khz', 11025),
  ]) {
    final BanqueReduite reduite = BanqueReduite.pour(
      source,
      programmes: programmes,
      noteMin: bas,
      noteMax: haut,
      frequence: frequence,
    );
    if (reduite.manquants.isNotEmpty) {
      stdout.writeln('  (absents de la banque : ${reduite.manquants})');
    }
    final Uint8List fichier = reduite.ecrire();
    await rendre(
      etiquette,
      ByteData.view(fichier.buffer, fichier.offsetInBytes),
      fichier.lengthInBytes,
    );
  }

  stdout.writeln('');
  stdout.writeln('Détail par sonorité, à la qualité par défaut '
      '(${BanqueReduite.frequenceParDefaut} Hz) :');
  for (final d in BanqueReduite.pour(
    source,
    programmes: programmes,
    noteMin: bas,
    noteMax: haut,
  ).detail) {
    stdout.writeln('  ${d.programme.toString().padLeft(3)} '
        '${d.nom.padRight(24).substring(0, 24)} '
        '${(d.octets / 1000000).toStringAsFixed(2)} Mo');
  }
}
