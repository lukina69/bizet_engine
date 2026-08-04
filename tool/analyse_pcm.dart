import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

void main(List<String> args) {
  if (args.isEmpty) {
    print('Usage : dart run tool/analyse_pcm.dart <fichier.wav>');
    exit(1);
  }

  final octets = File(args.first).readAsBytesSync();
  final vue = ByteData.sublistView(octets);

  // Parcours des chunks RIFF jusqu'à "data".
  var pos = 12, debut = -1, taille = 0;
  while (pos + 8 <= octets.length) {
    final id = String.fromCharCodes(octets.sublist(pos, pos + 4));
    taille = vue.getUint32(pos + 4, Endian.little);
    if (id == 'data') { debut = pos + 8; break; }
    pos += 8 + taille + (taille.isOdd ? 1 : 0);
  }
  if (debut < 0) { print('Chunk "data" introuvable.'); exit(1); }

  final fin = math.min(debut + taille, octets.length);
  var pic = 0, satures = 0, suite = 0, pireSuite = 0, n = 0;
  var sommeCarres = 0.0;

  for (var i = debut; i + 1 < fin; i += 2) {
    final s = vue.getInt16(i, Endian.little);
    n++;
    if (s.abs() > pic) pic = s.abs();
    sommeCarres += s * s.toDouble();
    if (s >= 32767 || s <= -32768) {
      satures++;
      if (++suite > pireSuite) pireSuite = suite;
    } else {
      suite = 0;
    }
  }

  double db(double v) =>
      v <= 0 ? double.negativeInfinity : 20 * (math.log(v / 32768) / math.ln10);

  print('Échantillons        : $n');
  print('Pic                 : $pic (${db(pic.toDouble()).toStringAsFixed(1)} dBFS)');
  print('RMS                 : ${db(math.sqrt(sommeCarres / n)).toStringAsFixed(1)} dBFS');
  print('Saturés             : $satures');
  print('Plus longue suite   : $pireSuite');
  print(pireSuite >= 3
      ? '\n>>> ÉCRÊTAGE CONFIRMÉ. Baisse le gain du synthé à 0.5, rends, puis normalise.'
      : '\n>>> Pas d\'écrêtage. Le son dur vient d\'ailleurs : passe à la vélocité.');
}
