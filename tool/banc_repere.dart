import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bizet_engine/bizet_engine.dart';
import 'package:dart_melty_soundfont/dart_melty_soundfont.dart';

import 'banc_commun.dart';

/// Le banc qui doit trancher **sur quoi aligner les sonorités**.
///
/// L'égalisation est adoptée, mais elle pose une question qu'aucun calcul ne
/// tranche : à quel niveau ramener tout le monde. Le volume de canal ne monte
/// presque pas au-dessus de son repos — quatre décibels — et descend sans
/// limite. Le repère ne peut donc être qu'un plafond commun : plus il est bas,
/// plus l'égalisation est complète, et plus l'application entière devient
/// discrète.
///
/// Les cent vingt sonorités s'étalent sur vingt-cinq décibels, mais très
/// inégalement : le gros de la troupe tient dans une dizaine de décibels, et la
/// queue basse ne compte que des percussions. Descendre le repère jusqu'à la
/// plus discrète ferait donc payer quinze décibels à tout le monde pour
/// rattraper une poignée de sonorités que personne ne joue en mélodie.
///
/// Quatre repères sont mis à l'épreuve, calculés sur la table des poids et non
/// écrits en dur — une nouvelle mesure les déplacera d'elle-même :
///
/// * la **médiane** : la moitié des sonorités au-dessus, la moitié en dessous ;
/// * le **premier quartile** ;
/// * le **premier décile** ;
/// * la **plus discrète de toutes**, l'égalisation stricte.
///
/// Chacun est joué par cinq témoins qui couvrent l'étendue, du trombone — le
/// plus fort de la banque, celui qui a le plus à perdre — au xylophone. Le
/// « Aucune » reproduit l'application d'aujourd'hui.
///
/// **Tous les extraits partagent un seul gain de sortie.** C'est indispensable
/// ici : ce qu'on juge n'est pas seulement l'égalité entre sonorités, c'est
/// aussi le volume que l'appli y perd. Normaliser chaque variante pour
/// elle-même effacerait la moitié de la question.
///
///     dart run tool/banc_repere.dart <dossier-instruments> <dossier-sortie>
Future<void> main(List<String> arguments) async {
  if (arguments.length < 2) {
    stderr.writeln('Usage : dart run tool/banc_repere.dart '
        '<dossier-instruments> <dossier-sortie>');
    exitCode = 64; // EX_USAGE
    return;
  }

  final Directory source = Directory(arguments[0]);
  final Directory sortie = Directory(arguments[1]);
  if (!source.existsSync()) {
    stderr.writeln('Introuvable : ${source.path}');
    exitCode = 66; // EX_NOINPUT
    return;
  }
  sortie.createSync(recursive: true);

  final List<double> poids = poidsMesures.values.toList()..sort();
  final List<_Repere> reperes = [
    const _Repere('aucune', 'Aucune', 'l\'appli d\'aujourd\'hui', null),
    _Repere('souple', 'Souple', 'la médiane', _quantile(poids, 0.50)),
    _Repere('moyenne', 'Moyenne', 'le premier quartile', _quantile(poids, 0.25)),
    _Repere('ferme', 'Ferme', 'le premier décile', _quantile(poids, 0.10)),
    _Repere('totale', 'Totale', 'la plus discrète', poids.first),
  ];

  final Melodie morceau = passage();
  final List<Evenement> notes = evenements(morceau);
  final double secondesParTemps = 60.0 / morceau.tempo;
  final int total = echantillons(morceau);

  stdout
    ..writeln('Passage : « ${morceau.titre} », '
        '${secondes(morceau).toStringAsFixed(1)} s, brillance $_brillance.')
    ..writeln('${poids.length} sonorités pesées, '
        'de ${poids.first.toStringAsFixed(1)} à '
        '${poids.last.toStringAsFixed(1)} dB.')
    ..writeln('');

  // Ce que chaque repère coûterait au catalogue entier. C'est le chiffre qui
  // cadre l'écoute : l'oreille dira si l'égalité s'entend, la table dit ce
  // qu'elle coûte à toutes les sonorités, pas seulement aux cinq témoins.
  stdout.writeln('repère            dB   au niveau   reste   volume perdu');
  for (final _Repere r in reperes) {
    if (r.niveau == null) continue;
    final _Bilan bilan = _bilanDe(r.niveau!, poids);
    stdout.writeln('${r.nom.padRight(10)}'
        '${r.niveau!.toStringAsFixed(1).padLeft(8)}'
        '${'${bilan.auNiveau}/${poids.length}'.padLeft(12)}'
        '${'${bilan.residu.toStringAsFixed(1)} dB'.padLeft(9)}'
        '${'${bilan.perteMoyenne.toStringAsFixed(1)} dB'.padLeft(15)}');
  }
  stdout.writeln('');

  final List<_Extrait> extraits = [];

  for (final (int programme, String etiquette, String cle) in _temoins) {
    final File banque = File(
        '${source.path}/p${programme.toString().padLeft(3, '0')}.sf2');
    if (!banque.existsSync()) {
      stderr.writeln('Sonorité absente du dossier : ${banque.path}');
      exitCode = 66;
      return;
    }
    final Uint8List octets = banque.readAsBytesSync();
    final ByteData donnees = ByteData.view(
        octets.buffer, octets.offsetInBytes, octets.lengthInBytes);

    final double? poidsTemoin = poidsNaturel(programme);
    if (poidsTemoin == null) {
      stderr.writeln('Sonorité sans poids mesuré : $etiquette');
      exitCode = 65; // EX_DATAERR
      return;
    }

    for (final _Repere r in reperes) {
      final int? volume = r.niveau == null
          ? null
          : RenduAudio.volumeDeCanal(r.niveau! - poidsTemoin);

      extraits.add(_Extrait(
        nom: '${r.cle}-$cle.wav',
        repere: r.cle,
        instrument: cle,
        son: jouer(donnees, programme, notes, _brillance,
            secondesParTemps: secondesParTemps,
            total: total,
            volumeDeCanal: volume),
        demande: r.niveau == null ? null : r.niveau! - poidsTemoin,
        volumeDeCanal: volume,
      ));
    }

    // Le banc dessine ses propres événements : il doit prouver qu'il joue ce
    // que jouerait l'appli. C'est la variante « souple » qui sert de témoin,
    // parce que c'est elle qui applique la correction du moteur — le repère
    // médian étant précisément celui que l'égalisation a adopté.
    final RenduAudio moteur = RenduAudio()..chargerSoundFont(donnees);
    final bool fidele = identiqueAuMoteur(
      extraits
          .firstWhere((e) => e.repere == 'souple' && e.instrument == cle)
          .son,
      moteur.rendre(morceau,
          reglages: Reglages(instrument: programme, brillance: _brillance)),
    );

    stdout.writeln('$etiquette — ${reperes.length} repères rendus '
        '(poids ${poidsTemoin.toStringAsFixed(1)} dB)'
        '${fidele ? '' : '  ⚠ DIFFÈRE DU MOTEUR'}');
  }
  stdout.writeln('');

  // Un seul gain de sortie pour tout le banc : les vingt-cinq extraits se
  // comparent tous entre eux, aussi bien d'une sonorité à l'autre que d'un
  // repère à l'autre.
  final int plusFort =
      extraits.map((e) => pic(e.son)).reduce(math.max);
  final double gain = 32767 * math.pow(10, -1 / 20).toDouble() / plusFort;

  final ExportMusical export = ExportMusical();
  for (final _Extrait e in extraits) {
    File('${sortie.path}/${e.nom}').writeAsBytesSync(
      export.versWav(ajuster(e.son, gain), frequence: frequence),
      flush: true,
    );
  }

  // Le niveau réellement obtenu, rapporté au plus discret des cinq témoins du
  // même repère : c'est l'égalité que l'oreille doit confirmer ou démentir.
  final Map<String, double> plusDiscret = {};
  for (final _Extrait e in extraits) {
    final double niveau = puissance(e.son);
    if (niveau < (plusDiscret[e.repere] ?? double.infinity)) {
      plusDiscret[e.repere] = niveau;
    }
  }

  final Map<String, Object?> manifeste = {
    'passage': {
      'titre': morceau.titre,
      'source': morceau.source,
      'tempo': morceau.tempo,
      'mesures': morceau.mesures.length,
      'duree': arrondi(secondes(morceau)),
      'brillance': _brillance,
    },
    'reperes': [
      for (final _Repere r in reperes)
        {
          'cle': r.cle,
          'nom': r.nom,
          'quoi': r.quoi,
          'niveau': r.niveau == null ? null : arrondi(r.niveau!),
          if (r.niveau != null) ...() {
            final _Bilan b = _bilanDe(r.niveau!, poids);
            return {
              'auNiveau': b.auNiveau,
              'total': poids.length,
              'residu': arrondi(b.residu),
              'perte': arrondi(b.perteMoyenne),
            };
          }(),
        },
    ],
    'instruments': [
      for (final (int programme, String etiquette, String cle) in _temoins)
        {
          'cle': cle,
          'nom': etiquette,
          'programme': programme,
          'poids': arrondi(poidsNaturel(programme)!),
        },
    ],
    'extraits': [
      for (final _Extrait e in extraits)
        {
          'fichier': e.nom,
          'repere': e.repere,
          'instrument': e.instrument,
          'demande': e.demande == null ? null : arrondi(e.demande!),
          'volumeDeCanal': e.volumeDeCanal,
          'obtenu':
              e.volumeDeCanal == null ? null : arrondi(dbRendu(e.volumeDeCanal!)),
          'mesure': arrondi(db(puissance(e.son) / plusDiscret[e.repere]!)),
        },
    ],
  };

  File('${sortie.path}/donnees.js').writeAsStringSync(
    'const BANC = ${const JsonEncoder.withIndent('  ').convert(manifeste)};\n',
    flush: true,
  );

  File('${File.fromUri(Platform.script).parent.path}/banc_repere.html')
      .copySync('${sortie.path}/banc-repere.html');

  stdout
    ..writeln('${extraits.length} extraits écrits dans ${sortie.path}')
    ..writeln('')
    ..writeln('À ouvrir : ${sortie.path}/banc-repere.html');
}

/// La brillance de l'application, pas celle du moteur : le banc doit faire
/// entendre ce que l'utilisateur entendra en ouvrant Bizet.
const int _brillance = 70;

/// Cinq témoins qui couvrent l'étendue des poids, du plus lourd au plus léger,
/// tous jouables dans le registre du passage — un instrument qu'on entendrait
/// hors de sa tessiture ne dirait rien de son niveau.
const List<(int, String, String)> _temoins = [
  (57, 'Trombone', 'trombone'),
  (60, 'Cor d\'harmonie', 'cor'),
  (21, 'Accordéon', 'accordeon'),
  (26, 'Guitare jazz', 'guitare'),
  (13, 'Xylophone', 'xylophone'),
];

/// Un niveau candidat sur lequel aligner les sonorités.
class _Repere {
  const _Repere(this.cle, this.nom, this.quoi, this.niveau);

  final String cle;
  final String nom;

  /// Ce que ce repère est, en un mot — pour que le chiffre ne soit pas seul.
  final String quoi;

  /// Le niveau visé, en dB sous la sonorité la plus forte. Nul pour
  /// l'application d'aujourd'hui, qui ne corrige rien.
  final double? niveau;
}

/// Ce qu'un repère fait au catalogue entier.
class _Bilan {
  const _Bilan(this.auNiveau, this.residu, this.perteMoyenne);

  /// Combien de sonorités atteignent vraiment le repère.
  final int auNiveau;

  /// Ce qu'il reste d'écart pour la plus récalcitrante, en dB.
  final double residu;

  /// Ce que l'ensemble du catalogue perd en volume, en moyenne.
  final double perteMoyenne;
}

_Bilan _bilanDe(double niveau, List<double> poids) {
  int auNiveau = 0;
  double residu = 0;
  double somme = 0;

  for (final double p in poids) {
    // La correction passe par un contrôleur MIDI entier qui plafonne à 127 :
    // ce qu'on obtient n'est pas toujours ce qu'on demande, et c'est bien
    // l'obtenu qu'il faut compter.
    final double obtenu = dbRendu(RenduAudio.volumeDeCanal(niveau - p));
    somme += obtenu;
    final double ecart = niveau - (p + obtenu);
    if (ecart > residu) residu = ecart;
    if (ecart.abs() < 0.2) auNiveau++;
  }

  return _Bilan(auNiveau, residu, somme / poids.length);
}

/// Le quantile [part] d'une liste déjà triée, par interpolation linéaire.
double _quantile(List<double> triee, double part) {
  final double rang = part * (triee.length - 1);
  final int bas = rang.floor();
  final int haut = rang.ceil();
  if (bas == haut) return triee[bas];
  return triee[bas] + (triee[haut] - triee[bas]) * (rang - bas);
}

/// Un extrait à écouter : un fichier, ce qu'il fait entendre, et ce que la
/// correction lui a vraiment fait.
class _Extrait {
  _Extrait({
    required this.nom,
    required this.repere,
    required this.instrument,
    required this.son,
    required this.demande,
    required this.volumeDeCanal,
  });

  final String nom;
  final String repere;
  final String instrument;
  final Int16List son;

  /// La correction voulue, en dB. Nulle quand rien n'est corrigé.
  final double? demande;

  /// Ce que le moteur enverrait vraiment comme volume de canal.
  final int? volumeDeCanal;
}
