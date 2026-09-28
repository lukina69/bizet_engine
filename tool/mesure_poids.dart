import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bizet_engine/bizet_engine.dart';
import 'package:dart_melty_soundfont/dart_melty_soundfont.dart';

import 'banc_commun.dart';

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
/// La mesure : **le niveau que l'instrument atteint quand il sonne**, sur une
/// vraie phrase jouée à vélocité 60, transposée dans l'octave où le calage
/// automatique poserait l'instrument.
///
/// Deux fausses pistes ont été essayées avant celle-ci, et elles disent
/// pourquoi c'est celle-là.
///
/// **Une seule note tenue** sous-estimait les percussions : un marimba y passe
/// le plus clair du temps à s'éteindre, il paraissait donc faible et on le
/// remontait, alors que ses attaques le rendaient déjà présent.
///
/// **La moyenne sur une phrase entière** a aggravé le défaut au lieu de le
/// corriger, et pour la même raison en pire : une phrase de percussion est
/// surtout faite de silence. Mesuré ainsi, le xylophone perdait encore deux
/// décibels et les nappes en gagnaient six.
///
/// Ce qui trompe dans les deux cas, c'est la moyenne : l'oreille n'entend pas
/// l'énergie moyenne d'un passage, elle entend à quel point ça sonne fort
/// quand ça sonne. La phrase est donc découpée en tranches courtes, et on ne
/// retient que les plus fortes : les silences ne pénalisent plus les sons qui
/// s'éteignent, et les sons qui se tiennent ne sont pas récompensés de durer.
///
/// Le réglage a été choisi en comparant plusieurs mesures sur les mêmes
/// témoins. Entre un marimba et une flûte, l'écart tombe de 8,1 dB avec la
/// moyenne à 1,1 dB ici, et c'est bien 1 dB que l'oreille entend. Entre deux
/// instruments qui se tiennent, rien ne bouge.
///
/// L'octave suit la même règle que le moteur, faute de quoi on mesurerait un
/// échantillon étiré que personne ne jouera : une boîte à musique ne descend
/// pas au do central. Une sonorité que le catalogue ne décrit pas garde la
/// phrase telle quelle.
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

/// La puissance de la phrase, jouée par cette sonorité seule.
double _puissance(File banque, int programme) {
  final ByteData octets = banque.readAsBytesSync().buffer.asByteData();

  // Là où l'instrument jouera vraiment. Le moteur cale les voix sur leur
  // tessiture avant de les faire sonner : mesurer ailleurs reviendrait à peser
  // un son que personne n'entendra.
  final Melodie morceau = passage().transposee(12 * _octaveDe(programme));
  final double secondesParTemps = 60.0 / morceau.tempo;

  return niveauQuandCaSonne(jouer(
    octets,
    programme,
    evenements(morceau),
    60,
    secondesParTemps: secondesParTemps,
    total: echantillons(morceau),
  ));
}


/// L'octave où le calage automatique poserait cette sonorité sur la phrase.
/// Zéro pour celles que le catalogue ne décrit pas : une tessiture se saisit à
/// la main, elle ne se devine pas.
int _octaveDe(int programme) {
  final Instrument? connu = instrumentParProgramme(programme);
  if (connu == null) return 0;

  final List<int> hauteurs = [
    for (final mesure in passage().mesures)
      for (final note in mesure.notes) note.hauteur,
  ];

  int meilleur = 0;
  int plusDedans = -1;
  for (final int essai in const [0, -1, 1, -2, 2]) {
    int dedans = 0;
    for (final int h in hauteurs) {
      if (connu.contient(h + 12 * essai)) dedans++;
    }
    if (dedans > plusDedans) {
      meilleur = essai;
      plusDedans = dedans;
    }
  }
  return meilleur;
}
