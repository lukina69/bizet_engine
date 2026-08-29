import 'dart:io';
import 'dart:typed_data';

import 'package:bizet_engine/bizet_engine.dart';

/// Fabrique la banque que l'application embarque : le socle, celui sur lequel
/// viennent se poser les sonorités téléchargées.
///
///     dart run tool/banque_embarquee.dart <source.sf2> <sortie.sf2> [ajout.sf2...]
///
/// L'application ne peut pas livrer les cent vingt sonorités du catalogue —
/// elle pèserait près d'un giga-octet. Elle en embarque donc une poignée,
/// choisie pour qu'on puisse jouer dès l'installation sans rien télécharger,
/// et les autres s'ajoutent à la demande.
///
/// Les [ajout] sont des banques d'une sonorité chacune, recollées au socle :
/// c'est ainsi que le piano acoustique y entre, puisqu'il ne vient pas de la
/// même banque que le reste.
void main(List<String> args) {
  if (args.length < 2) {
    print(
      'Usage : dart run tool/banque_embarquee.dart '
      '<source.sf2> <sortie.sf2> [ajout.sf2...]',
    );
    exit(1);
  }

  final ByteData source = _lire(args[0]);
  final File sortie = File(args[1]);
  final List<ByteData> ajouts = [for (final a in args.skip(2)) _lire(a)];

  final BanqueReduite socle = BanqueReduite.pour(
    source,
    programmes: embarquees,
    frequence: RenduAudio.frequence,
  );

  if (socle.manquants.isNotEmpty) {
    print('La source n\'a pas ${socle.manquants} : rien n\'est écrit.');
    exit(1);
  }

  print('Depuis ${args[0]} :');
  for (final d in socle.detail) {
    print(
      '  ${d.programme.toString().padLeft(3)}  ${d.nom.padRight(22)} '
      '${_mo(d.octets)}',
    );
  }

  final Uint8List taillee = socle.ecrire(nom: 'Bizet');
  Uint8List finale = taillee;

  if (ajouts.isNotEmpty) {
    final BanqueAssemblee assemblee = BanqueAssemblee.de([
      ByteData.view(taillee.buffer, taillee.offsetInBytes, taillee.length),
      ...ajouts,
    ]);
    if (assemblee.ignores.isNotEmpty) {
      print('Déjà dans le socle, ignoré : ${assemblee.ignores}');
    }
    finale = assemblee.ecrire(nom: 'Bizet');
    print(
      'Ajouts : ${args.skip(2).join(', ')}  '
      '(+${_mo(finale.length - taillee.length)})',
    );
  }

  sortie.writeAsBytesSync(finale);

  // La preuve qui compte : le fichier écrit se relit, et offre bien ce qu'on
  // voulait. Une banque qui perd une sonorité en chemin ferait jouer autre
  // chose en silence.
  final RenduAudio relu = RenduAudio();
  relu.chargerSoundFont(
    ByteData.view(finale.buffer, finale.offsetInBytes, finale.length),
  );

  print(
    '\n${sortie.path} : ${_mo(finale.length)}, '
    '${relu.programmes.length} sonorités — ${relu.programmes}',
  );
  print('La source en faisait ${_mo(source.lengthInBytes)}.');
}

/// Les sonorités livrées avec l'application.
///
/// Huit sonorités de `Bizet_v4`, choisies avec Ludo pour couvrir les familles
/// d'un bout à l'autre — un son qui s'éteint et un son qui se tient dans
/// chaque registre — sans dépasser six méga-octets. Le piano acoustique s'y
/// ajoute à part : il ne vient pas de cette banque-là.
///
/// En sortir une allège l'application d'autant, mais prive l'utilisateur de ce
/// son tant qu'il ne l'a pas téléchargé. C'est un arbitrage à faire à
/// l'oreille, pas au calcul.
const Set<int> embarquees = {
  4, // piano électrique — le clavier de tous les jours
  10, // boîte à musique — la plus légère de toutes, et la plus jolie
  12, // marimba — le bois qu'on frappe
  40, // violon — la voix qui chante
  42, // violoncelle — la même, en grave
  56, // trompette — le cuivre qui perce
  58, // tuba — le fond
  73, // flûte — le souffle
};

ByteData _lire(String chemin) {
  final Uint8List o = File(chemin).readAsBytesSync();
  return ByteData.view(o.buffer, o.offsetInBytes);
}

String _mo(int octets) => '${(octets / 1e6).toStringAsFixed(2)} Mo';
