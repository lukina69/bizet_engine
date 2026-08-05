import 'dart:io';
import 'dart:math' as math;

import 'package:bizet_engine/bizet_engine.dart';
import 'package:dart_melty_soundfont/dart_melty_soundfont.dart';

/// Mesure le poids naturel de chaque sonorité du catalogue dans une banque
/// donnée : la puissance (RMS sur 0,75 s) d'une note à vélocité 60, prise au
/// do central quand la tessiture le contient, à son centre sinon.
///
/// À relancer à chaque nouvelle banque, et reporter les valeurs dans
/// `lib/src/instruments/catalogue.dart` (champ `poidsNaturel`) : c'est lui
/// qui égalise les voix ajoutées sous la mélodie.
///
///     dart run tool/mesure_poids.dart <banque.sf2>
void main(List<String> args) {
  if (args.isEmpty) {
    print('Usage : dart run tool/mesure_poids.dart <banque.sf2>');
    exit(1);
  }

  final synth = Synthesizer.loadByteData(
    File(args.first).readAsBytesSync().buffer.asByteData(),
    SynthesizerSettings(
      sampleRate: 44100,
      blockSize: 64,
      maximumPolyphony: 64,
      enableReverbAndChorus: true,
    ),
  );

  double rms(int programme, int cle) {
    synth.reset();
    synth.processMidiMessage(
        channel: 0, command: 0xC0, data1: programme, data2: 0);
    final tampon = ArrayInt16.zeros(numShorts: 33075);
    synth.noteOn(channel: 0, key: cle, velocity: 60);
    synth.renderMonoInt16(tampon, offset: 0, length: 33075);
    double somme = 0;
    for (int i = 0; i < 33075; i++) {
      final int v = tampon[i] as int;
      somme += v * v;
    }
    return math.sqrt(somme / 33075);
  }

  final List<(Instrument, double)> mesures = [
    for (final Instrument i in catalogue)
      (i, rms(i.programme, i.contient(60) ? 60 : i.centre)),
  ];

  final double maxi =
      mesures.map((m) => m.$2).reduce((a, b) => a > b ? a : b);

  print('poids naturels, en dB relatifs au plus fort — à reporter dans le');
  print('catalogue :\n');
  for (final (instrument, valeur) in mesures) {
    final double db =
        valeur <= 0 ? -99.0 : 20 * (math.log(valeur / maxi) / math.ln10);
    print('  programme ${instrument.programme.toString().padLeft(3)}  '
        '${instrument.nom.padRight(22)} poidsNaturel: '
        '${db.toStringAsFixed(1)}');
  }
}
