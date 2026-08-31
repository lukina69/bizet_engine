import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bizet_engine/bizet_engine.dart';
import 'package:dart_melty_soundfont/dart_melty_soundfont.dart';

/// Mesure le poids naturel de **toutes** les sonorités publiées, et écrit la
/// table que le moteur embarque.
///
/// À vélocité égale, les presets ne pèsent pas pareil — vingt-cinq décibels
/// séparent le trombone du bloc de bois. Sans ce chiffre, égaliser deux voix
/// est impossible : c'est lui, et lui seul, qui dit de combien baisser la plus
/// lourde.
///
/// **Pourquoi une table embarquée, et non le manifeste téléchargé** : le
/// manifeste des sonorités se rapatrie depuis la release, et n'est donc là
/// qu'après un premier lancement avec du réseau. Une égalisation qui en
/// dépendrait ne marcherait pas hors ligne — et surtout, elle ne le dirait
/// pas. Cent vingt nombres ne pèsent rien : ils voyagent avec le code.
///
/// La mesure : la puissance (RMS sur 0,75 s) d'une note tenue à vélocité 60,
/// prise **là où l'instrument joue vraiment** — au do central quand sa
/// tessiture le contient, au centre de sa tessiture sinon. Une sonorité que le
/// catalogue ne connaît pas n'a pas de tessiture : on la prend au do central.
/// Tout mesurer au même do serait plus simple et moins juste : une boîte à
/// musique ne descend pas là, et l'échantillon qu'on y entendrait serait un
/// son étiré que personne ne jouera.
///
/// À relancer à chaque nouvelle édition du catalogue.
///
///     dart run tool/mesure_poids.dart <dossier-instruments> [sortie.dart]
///
/// où `<dossier-instruments>` est celui que publie `publier_instruments.dart`
/// (un `instruments.json` et les `pNNN.sf2`).
void main(List<String> arguments) {
  if (arguments.isEmpty) {
    stderr.writeln('Usage : dart run tool/mesure_poids.dart '
        '<dossier-instruments> [sortie.dart]');
    exitCode = 64; // EX_USAGE
    return;
  }

  final Directory source = Directory(arguments.first);
  if (!source.existsSync()) {
    stderr.writeln('Introuvable : ${source.path}');
    exitCode = 66; // EX_NOINPUT
    return;
  }

  final String sortie = arguments.length > 1
      ? arguments[1]
      : '${File.fromUri(Platform.script).parent.parent.path}'
          '/lib/src/instruments/poids.dart';

  final Map<String, dynamic> manifeste = jsonDecode(
          File('${source.path}/instruments.json').readAsStringSync())
      as Map<String, dynamic>;

  final List<(int, String, double)> mesures = [];

  for (final Map<String, dynamic> offert
      in (manifeste['instruments'] as List).cast<Map<String, dynamic>>()) {
    final int programme = offert['programme'] as int;
    final String nom = offert['nom'] as String;
    final File banque = File('${source.path}/'
        '${(offert['standard'] as Map<String, dynamic>)['fichier']}');

    if (!banque.existsSync()) {
      stderr.writeln('Sonorité absente : ${banque.path}');
      exitCode = 66;
      return;
    }

    mesures.add((programme, nom, _puissance(banque, programme)));
  }

  if (mesures.isEmpty) {
    stderr.writeln('Le manifeste ne décrit aucune sonorité.');
    exitCode = 65; // EX_DATAERR
    return;
  }

  // Le repère est la plus forte : tous les poids sont donc négatifs ou nuls,
  // et l'égalisation ne fait jamais que baisser — le seul sens praticable,
  // puisque le volume de canal est déjà presque au plafond au repos.
  final double maxi = mesures.map((m) => m.$3).reduce(math.max);

  final StringBuffer table = StringBuffer()
    ..writeln('// FICHIER ENGENDRÉ par tool/mesure_poids.dart — ne pas le')
    ..writeln('// retoucher à la main : la prochaine mesure l\'écraserait.')
    ..writeln('//')
    ..writeln('// ${mesures.length} sonorités, mesurées sur l\'édition '
        '« ${source.path.split('/').last} ».')
    ..writeln()
    ..writeln('/// Poids naturel de chaque sonorité, en décibels sous la plus')
    ..writeln('/// forte de la banque : l\'écart qu\'une voix doit compenser')
    ..writeln('/// pour peser autant qu\'une autre.')
    ..writeln('///')
    ..writeln('/// Passer par [poidsNaturel] plutôt que par cette table : une')
    ..writeln('/// sonorité inconnue doit rester une absence, jamais un zéro —')
    ..writeln('/// zéro voudrait dire « aussi forte que la plus forte ».')
    ..writeln('const Map<int, double> poidsMesures = {');

  for (final (programme, nom, puissance) in mesures) {
    final double db =
        puissance <= 0 ? -99.0 : 20 * (math.log(puissance / maxi) / math.ln10);
    table.writeln('  $programme: ${db.toStringAsFixed(1)}, '
        '// ${nom.replaceAll('\n', ' ')}');
  }

  table
    ..writeln('};')
    ..writeln()
    ..writeln('/// Le poids naturel de [programme], ou nul si la banque ne')
    ..writeln('/// connaît pas cette sonorité — auquel cas il n\'y a rien à')
    ..writeln('/// égaliser, et mieux vaut ne rien corriger que corriger au')
    ..writeln('/// hasard.')
    ..writeln(
        'double? poidsNaturel(int programme) => poidsMesures[programme];');

  File(sortie).writeAsStringSync(table.toString(), flush: true);

  stdout
    ..writeln('${mesures.length} sonorités mesurées.')
    ..writeln('La plus forte, qui sert de repère : '
        '${mesures.firstWhere((m) => m.$3 == maxi).$2}.')
    ..writeln('→ $sortie');
}

/// La puissance d'une note tenue, sur la sonorité seule.
double _puissance(File banque, int programme) {
  final Synthesizer synth = Synthesizer.loadByteData(
    banque.readAsBytesSync().buffer.asByteData(),
    SynthesizerSettings(
      sampleRate: 44100,
      blockSize: 64,
      maximumPolyphony: 64,
      enableReverbAndChorus: true,
    ),
  );

  // Là où l'instrument joue vraiment : le catalogue porte les tessitures
  // musicales de celles qu'il connaît. Les autres, faute de mieux, au do
  // central — c'est là que passe la quasi-totalité d'une mélodie.
  final Instrument? connu = instrumentParProgramme(programme);
  final int cle =
      connu == null ? 60 : (connu.contient(60) ? 60 : connu.centre);

  synth.processMidiMessage(
      channel: 0, command: 0xC0, data1: programme, data2: 0);

  const int points = 33075; // 0,75 s à 44 100 Hz
  final ArrayInt16 tampon = ArrayInt16.zeros(numShorts: points);
  synth.noteOn(channel: 0, key: cle, velocity: 60);
  synth.renderMonoInt16(tampon, offset: 0, length: points);

  double somme = 0;
  for (int i = 0; i < points; i++) {
    final int v = tampon[i] as int;
    somme += v * v;
  }
  return math.sqrt(somme / points);
}
