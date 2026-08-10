import 'dart:io';
import 'dart:typed_data';

import 'package:bizet_engine/bizet_engine.dart';
import 'package:dart_melty_soundfont/dart_melty_soundfont.dart'
    show ArrayInt16;

/// L'essai en ligne de commande : une recette entre, un WAV sort.
///
/// C'est la façon la moins chère de savoir si des bornes tombent juste. Pas
/// de jeu à lancer, pas d'appli à installer : on écoute quelques boucles
/// tirées à la suite, dans l'ordre où le module les jouera, et on entend
/// aussi ce que donne le passage d'une boucle à l'autre.
///
///     dart run bizet_engine:essai ma.recette.json banque.sf2 [boucles] [graine]
Future<void> main(List<String> arguments) async {
  if (arguments.length < 2) {
    stderr.writeln(
      'Usage : dart run bizet_engine:essai '
      '<recette.json> <banque.sf2> [boucles] [graine]\n'
      '\n'
      '  recette.json  le fichier exporté par l\'atelier Scène de Bizet\n'
      '  banque.sf2    la banque de sons\n'
      '  boucles       combien de tours enchaîner (4 par défaut)\n'
      '  graine        pour rejouer exactement la même suite\n',
    );
    exitCode = 64; // EX_USAGE
    return;
  }

  final File fichierRecette = File(arguments[0]);
  final File fichierBanque = File(arguments[1]);

  for (final File f in [fichierRecette, fichierBanque]) {
    if (!f.existsSync()) {
      stderr.writeln('Introuvable : ${f.path}');
      exitCode = 66; // EX_NOINPUT
      return;
    }
  }

  final int boucles = arguments.length > 2 ? int.parse(arguments[2]) : 4;
  final int? graine = arguments.length > 3 ? int.parse(arguments[3]) : null;

  final Uint8List octets = await fichierBanque.readAsBytes();

  final Scene scene;
  try {
    scene = Scene.depuisJson(
      await fichierRecette.readAsString(),
      soundFont: ByteData.view(octets.buffer, octets.offsetInBytes),
      graine: graine,
    );
  } on FormatException catch (e) {
    stderr.writeln('Ce fichier n\'est pas une recette lisible : ${e.message}');
    exitCode = 65; // EX_DATAERR
    return;
  }

  stdout.writeln('Recette « ${scene.recette.nom} » — '
      '${scene.recette.morceaux.length} morceau(x), '
      '${scene.instrumentsDisponibles.length} sonorités dans la banque.');
  stdout.writeln('');

  final List<String> noms = _nomsInstruments();

  // Chaque boucle est rendue puis mise bout à bout : le fichier obtenu est
  // exactement ce que l'hôte entendrait en enchaînant les tours.
  final List<Boucle> tours = [];
  for (int tour = 1; tour <= boucles; tour++) {
    final Boucle boucle = scene.prochaine();
    tours.add(boucle);
    stdout.writeln('Boucle $tour — ${_resume(boucle, noms)}');
  }

  final Uint8List wav = ExportMusical()
      .versWav(_bouteBout(tours), frequence: Scene.frequence);

  final String base =
      arguments[0].replaceAll(RegExp(r'(\.recette)?\.json$'), '');
  final String sortie = '$base-essai.wav';
  await File(sortie).writeAsBytes(wav, flush: true);

  final double duree = tours.fold(0.0, (somme, b) => somme + b.secondes);
  stdout.writeln('');
  stdout.writeln('→ $sortie '
      '(${duree.toStringAsFixed(1)} s, '
      '${(wav.lengthInBytes / 1000000).toStringAsFixed(1)} Mo)');
}

/// Les boucles mises bout à bout dans un seul tampon.
///
/// Rien entre elles : c'est justement le passage brut d'un morceau au suivant
/// qu'il faut entendre avant de décider s'il gêne.
ArrayInt16 _bouteBout(List<Boucle> boucles) {
  final int total = boucles.fold(0, (somme, b) => somme + b.echantillons);
  final ArrayInt16 tout = ArrayInt16.zeros(numShorts: total);

  int position = 0;
  for (final Boucle boucle in boucles) {
    for (int i = 0; i < boucle.echantillons; i++) {
      tout[position + i] = boucle.son[i] as int;
    }
    position += boucle.echantillons;
  }
  return tout;
}

/// Ce que le sort a choisi pour cette boucle, en une ligne lisible.
String _resume(Boucle boucle, List<String> noms) {
  final Reglages r = boucle.reglages;

  String nom(int? programme) =>
      programme == null || programme >= noms.length ? '?' : noms[programme];

  final String instruments = [
    nom(r.instrument),
    for (final int? rang in r.compagnons.rangs)
      if (rang != null) nom(rang),
  ].join(' + ');

  final String mode = switch (r.majeur) {
    null => 'écrit',
    true => 'majeur',
    false => 'mineur',
  };

  return '${boucle.partition.titre} · $instruments · ${r.tempo} BPM'
      ' · ${r.balancement.swing.name} · rubato ${r.rubato.name}'
      ' · nuances ${r.nuances.name} · ${r.epaisseur.name}'
      ' · octave ${r.octave} · $mode'
      ' · accomp. ${r.accompagnement}'
      ' · ${boucle.secondes.toStringAsFixed(1)} s';
}

/// Les noms General MIDI, pour que la trace se lise. Un module embarqué n'en
/// a que faire ; cet essai-ci, si.
List<String> _nomsInstruments() => const [
      'Piano', 'Piano brillant', 'Piano électrique à queue', 'Piano bastringue',
      'Piano électrique 1', 'Piano électrique 2', 'Clavecin', 'Clavinet',
      'Célesta', 'Glockenspiel', 'Boîte à musique', 'Vibraphone',
      'Marimba', 'Xylophone', 'Cloches tubulaires', 'Tympanon',
      'Orgue Hammond', 'Orgue percussif', 'Orgue rock', 'Orgue d\'église',
      'Harmonium', 'Accordéon', 'Harmonica', 'Bandonéon',
      'Guitare nylon', 'Guitare acier', 'Guitare jazz', 'Guitare claire',
      'Guitare étouffée', 'Guitare saturée', 'Guitare distordue',
      'Harmoniques de guitare',
      'Basse acoustique', 'Basse doigtée', 'Basse au médiator',
      'Basse fretless',
      'Basse slappée 1', 'Basse slappée 2', 'Basse synthé 1', 'Basse synthé 2',
      'Violon', 'Alto', 'Violoncelle', 'Contrebasse',
      'Cordes trémolo', 'Cordes pizzicato', 'Harpe', 'Timbales',
      'Ensemble à cordes 1', 'Ensemble à cordes 2', 'Cordes synthé 1',
      'Cordes synthé 2',
      'Chœur « aah »', 'Voix « ooh »', 'Voix synthé', 'Coup d\'orchestre',
      'Trompette', 'Trombone', 'Tuba', 'Trompette bouchée',
      'Cor d\'harmonie', 'Section de cuivres', 'Cuivres synthé 1',
      'Cuivres synthé 2',
      'Saxophone soprano', 'Saxophone alto', 'Saxophone ténor',
      'Saxophone baryton',
      'Hautbois', 'Cor anglais', 'Basson', 'Clarinette',
      'Piccolo', 'Flûte', 'Flûte à bec', 'Flûte de Pan',
      'Souffle de bouteille', 'Shakuhachi', 'Sifflement', 'Ocarina',
      'Lead 1 (carré)', 'Lead 2 (dents de scie)', 'Lead 3 (calliope)',
      'Lead 4 (chiff)',
      'Lead 5 (charang)', 'Lead 6 (voix)', 'Lead 7 (quintes)',
      'Lead 8 (basse et lead)',
      'Nappe 1 (new age)', 'Nappe 2 (chaude)', 'Nappe 3 (polysynthé)',
      'Nappe 4 (chœur)',
      'Nappe 5 (archet)', 'Nappe 6 (métallique)', 'Nappe 7 (halo)',
      'Nappe 8 (balayage)',
      'FX 1 (pluie)', 'FX 2 (bande-son)', 'FX 3 (cristal)',
      'FX 4 (atmosphère)',
      'FX 5 (éclat)', 'FX 6 (gobelins)', 'FX 7 (échos)', 'FX 8 (science-fiction)',
      'Sitar', 'Banjo', 'Shamisen', 'Koto',
      'Kalimba', 'Cornemuse', 'Violon traditionnel', 'Shanai',
      'Clochette', 'Agogo', 'Steel drums', 'Bloc de bois',
      'Taiko', 'Tom mélodique', 'Batterie synthé', 'Cymbale inversée',
      'Bruit de frettes', 'Bruit de souffle', 'Bord de mer', 'Chant d\'oiseau',
      'Sonnerie de téléphone', 'Hélicoptère', 'Applaudissements',
      'Coup de feu',
    ];
