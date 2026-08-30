import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bizet_engine/bizet_engine.dart';
import 'package:dart_melty_soundfont/dart_melty_soundfont.dart';

/// Le banc d'écoute qui doit trancher deux questions restées en l'air :
/// **quelle vélocité** pour la mélodie principale, et **l'égalisation par la
/// mesure tient-elle à l'oreille**.
///
/// Depuis que la vélocité ne dit plus que l'attaque et que le niveau passe par
/// le volume de canal, ces deux questions sont enfin séparables — mais elles
/// ne se répondent pas au calcul. Elles se répondent en écoutant, et en
/// écoutant *à volume égal* : une même sonorité jouée plus fort passe pour
/// plus belle, et le jugement ne vaut alors plus rien. Tout ce que ce banc
/// fabrique est donc ramené au même niveau, mesure à l'appui.
///
/// Deux séries en sortent :
///
/// * **A — la vélocité.** Le même passage joué à 60, 70, 80, 90 puis 100 sur
///   chaque sonorité, tous ramenés au même niveau. Ce qui change d'un extrait
///   à l'autre est le timbre, et rien d'autre. Attention : la vélocité ne
///   choisit pas un timbre sur une pente douce, elle choisit une couche
///   d'échantillons — d'où l'écoute par paliers plutôt qu'au curseur.
/// * **B — l'égalisation.** Les quatre sonorités, avant puis après
///   correction. « Avant », c'est l'application d'aujourd'hui : tout le monde
///   à la même vélocité, personne au même niveau. « Après », chacune est
///   corrigée par le `rms` mesuré dans `instruments.json` — exactement le
///   chiffre dont disposerait l'appli.
///
/// Un extrait par fichier, tous de la même longueur : c'est ce qui permet à la
/// page d'écoute de passer de l'un à l'autre **sans déplacer le curseur de
/// lecture**. Comparer deux timbres de mémoire ne marche pas ; les entendre se
/// remplacer au même endroit de la phrase, si.
///
///     dart run tool/banc_ecoute.dart <dossier-instruments> <dossier-sortie>
///
/// où `<dossier-instruments>` est celui que publie `publier_instruments.dart`
/// (un `instruments.json` et les `pNNN.sf2`). Ouvrir ensuite le
/// `banc-ecoute.html` écrit dans le dossier de sortie.
Future<void> main(List<String> arguments) async {
  if (arguments.length < 2) {
    stderr.writeln('Usage : dart run tool/banc_ecoute.dart '
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

  final Map<int, double> rmsPublies = _rmsPublies(source);

  final Melodie passage = _passage();
  final List<_Evenement> evenements = _evenements(passage);
  final double secondesParTemps = 60.0 / passage.tempo;
  final double duree =
      passage.mesures.fold(0.0, (somme, m) => somme + m.dureeEffective) *
          secondesParTemps;
  final int echantillons = ((duree + _queue) * _frequence).ceil();

  stdout.writeln('Passage : « ${passage.titre} », '
      '${passage.mesures.length} mesures à ${passage.tempo} à la noire, '
      '${duree.toStringAsFixed(1)} s.');
  stdout.writeln('');

  // Un rendu par sonorité et par vélocité. Rien n'est encore mis à niveau :
  // on garde les mesures brutes, c'est d'elles que sortiront les corrections.
  final Map<int, Map<int, Int16List>> rendus = {};
  final Map<int, Map<int, double>> puissances = {};

  for (final (int programme, String etiquette, _) in _sonorites) {
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

    final Synthesizer synth = _synthetiseur(donnees);
    rendus[programme] = {};
    puissances[programme] = {};

    for (final int velocite in _velocites) {
      final Int16List son = _jouer(synth, programme, evenements, velocite,
          secondesParTemps, echantillons);
      rendus[programme]![velocite] = son;
      puissances[programme]![velocite] = _puissance(son);
    }

    // Le banc dessine ses propres événements plutôt que d'appeler le moteur,
    // faute d'y pouvoir changer la vélocité. Il doit donc prouver qu'il joue
    // la même chose : à 80, son rendu doit être celui du moteur, échantillon
    // pour échantillon. Si ce n'est plus vrai, le banc ment.
    final RenduAudio moteur = RenduAudio()..chargerSoundFont(donnees);
    final bool fidele = _identiques(
      rendus[programme]![Epaisseur.velociteBase]!,
      moteur.rendre(passage, reglages: Reglages(instrument: programme)),
    );

    stdout.writeln('$etiquette — ${_velocites.length} vélocités rendues'
        '${fidele ? '' : '  ⚠ DIFFÈRE DU MOTEUR À ${Epaisseur.velociteBase}'}');
  }
  stdout.writeln('');

  final List<_Extrait> extraits = [];

  // --- Série A : la vélocité, à niveau égal --------------------------------
  //
  // Le repère est la vélocité la plus faible : on ne peut qu'atténuer sans
  // risquer de saturer, et l'oreille ne compare que ce qui reste — le timbre.
  for (final (int programme, _, String cle) in _sonorites) {
    final Map<int, double> mesure = puissances[programme]!;
    final double repere = mesure.values.reduce(math.min);
    for (final int velocite in _velocites) {
      extraits.add(_Extrait(
        nom: 'a-$cle-v$velocite.wav',
        // Chaque sonorité de la série A est son propre monde : on n'y compare
        // jamais une sonorité à une autre, seulement des vélocités entre
        // elles. Elle peut donc être montée au maximum, ce qui évite d'avoir
        // à écouter le marimba à trois fois rien.
        groupe: 'a-$cle',
        serie: 'a',
        instrument: cle,
        variante: '$velocite',
        son: rendus[programme]![velocite]!,
        gain: repere / mesure[velocite]!,
      ));
    }
  }

  // --- Série B : l'égalisation ---------------------------------------------
  //
  // Chaque sonorité est ramenée sur la plus discrète des quatre : le volume de
  // canal ne monte quasiment pas au-dessus de son repos, il n'y a donc qu'un
  // sens praticable — baisser les fortes.
  final double reperePublie =
      _sonorites.map((s) => rmsPublies[s.$1]!).reduce(math.min);

  for (final bool corrige in const [false, true]) {
    for (final (int programme, _, String cle) in _sonorites) {
      final double db =
          corrige ? _db(reperePublie / rmsPublies[programme]!) : 0.0;
      extraits.add(_Extrait(
        nom: 'b-${corrige ? 'apres' : 'avant'}-$cle.wav',
        // Tout « avant » et tout « après » partagent un gain : sinon chacun
        // serait remonté pour lui-même et l'égalisation paraîtrait gratuite.
        // Ce qu'elle coûte en volume d'ensemble doit s'entendre.
        groupe: 'b',
        serie: 'b',
        instrument: cle,
        variante: corrige ? 'apres' : 'avant',
        son: rendus[programme]![Epaisseur.velociteBase]!,
        gain: math.pow(10, db / 20).toDouble(),
        correction: db,
        volumeDeCanal: corrige ? RenduAudio.volumeDeCanal(db) : null,
      ));
    }
  }

  // --- Le gain de sortie, groupe par groupe ---------------------------------
  //
  // Monter le son ne se décide pas extrait par extrait : deux extraits qu'on
  // doit comparer doivent monter ensemble, sinon la normalisation efface
  // justement ce qu'on cherchait à entendre.
  final Map<String, double> pics = {};
  for (final _Extrait e in extraits) {
    final int p = _pic(e.son, e.gain);
    if (p > (pics[e.groupe] ?? 0)) pics[e.groupe] = p.toDouble();
  }
  final double sortieMax = 32767 * math.pow(10, -1 / 20).toDouble();
  final Map<String, double> makeup =
      pics.map((groupe, pic) => MapEntry(groupe, sortieMax / pic));

  // --- Écriture -------------------------------------------------------------
  final ExportMusical export = ExportMusical();
  for (final _Extrait e in extraits) {
    File('${sortie.path}/${e.nom}').writeAsBytesSync(
      export.versWav(_ajuster(e.son, e.gain * makeup[e.groupe]!),
          frequence: _frequence),
      flush: true,
    );
  }

  // Ce que pèse réellement chaque extrait une fois corrigé : la correction a
  // beau annoncer un chiffre, c'est le passage entier qui décide. Le repère
  // est le plus discret de sa série et de sa variante — ce que la page affiche
  // sous le nom d'« écart mesuré ».
  final Map<String, double> repereMesure = {};
  for (final _Extrait e in extraits) {
    final double niveau = _puissance(e.son) * e.gain;
    final String cle = '${e.serie}-${e.serie == 'a' ? e.instrument : e.variante}';
    if (niveau < (repereMesure[cle] ?? double.infinity)) {
      repereMesure[cle] = niveau;
    }
  }

  final Map<String, Object?> manifeste = {
    'passage': {
      'titre': passage.titre,
      'source': passage.source,
      'tempo': passage.tempo,
      'mesures': passage.mesures.length,
      'duree': double.parse(duree.toStringAsFixed(2)),
    },
    'velocites': _velocites,
    'velociteActuelle': Epaisseur.velociteBase,
    'instruments': [
      for (final (int programme, String etiquette, String cle) in _sonorites)
        {
          'cle': cle,
          'nom': etiquette,
          'programme': programme,
          'rms': rmsPublies[programme],
        },
    ],
    'extraits': [
      for (final _Extrait e in extraits)
        {
          'fichier': e.nom,
          'serie': e.serie,
          'instrument': e.instrument,
          'variante': e.variante,
          'miseANiveau': _arrondi(_db(e.gain)),
          'correction': e.correction == null ? null : _arrondi(e.correction!),
          'volumeDeCanal': e.volumeDeCanal,
          'mesure': _arrondi(_db(_puissance(e.son) *
              e.gain /
              repereMesure[
                  '${e.serie}-${e.serie == 'a' ? e.instrument : e.variante}']!)),
        },
    ],
  };

  File('${sortie.path}/donnees.js').writeAsStringSync(
    'const BANC = ${const JsonEncoder.withIndent('  ').convert(manifeste)};\n',
    flush: true,
  );

  final File page = File(
      '${File.fromUri(Platform.script).parent.path}/banc_ecoute.html');
  page.copySync('${sortie.path}/banc-ecoute.html');

  stdout
    ..writeln('${extraits.length} extraits écrits dans ${sortie.path}')
    ..writeln('')
    ..writeln('À ouvrir : ${sortie.path}/banc-ecoute.html');
}

/// Qualité de rendu : celle de l'application, pas une pour la route. Juger un
/// timbre sur un rendu dégradé ne prouverait rien de ce qu'on entendra.
const int _frequence = RenduAudio.frequence;

/// Les paliers à départager. Cinq, sans demi-teinte : la vélocité choisit une
/// couche d'échantillons, pas un point sur une pente.
const List<int> _velocites = [60, 70, 80, 90, 100];

/// Les quatre sonorités, de la plus discrète à la plus lourde. Quatre
/// familles, quatre comportements après l'attaque, et 13,5 dB d'écart naturel
/// entre les extrêmes — dont le trombone, le plus fort de toute la banque. Le
/// piano est là pour une raison précise : ceux de MuseScore se sont déjà
/// révélés muets à une vélocité et corrects à une autre.
const List<(int, String, String)> _sonorites = [
  (12, 'Marimba', 'marimba'),
  (73, 'Flûte', 'flute'),
  (0, 'Piano', 'piano'),
  (57, 'Trombone', 'trombone'),
];

/// La queue laissée aux notes pour s'éteindre, comme dans le moteur.
const double _queue = 1.0;

/// Le passage : les six premières mesures de la vocalise de Franz Abt, sa
/// ligne de chant seule.
///
/// Monophonique à dessein — c'est le périmètre de Bizet, et un timbre ne
/// s'examine pas sous une texture. La phrase tient tout ce qu'il faut
/// entendre : des tenues longues pour le corps du son, des notes brèves pour
/// l'attaque, un silence pour la chute, et une montée du do central au si.
Melodie _passage() => Melodie(
      titre: 'Vocalise nº 1 — six mesures',
      source: 'Franz Abt, Vocalise nº 1 — Mutopia, domaine public',
      tempo: 110,
      instrumentMidi: 0,
      mesures: [
        _mesure([(64, 2.0), (62, 2.0)]),
        _mesure([(60, 4.0)]),
        _mesure([(62, 2.0), (64, 1.0), (65, 1.0)]),
        _mesure([(64, 2.0)]), // suivi d'un silence : d'où la durée déclarée
        _mesure([(67, 2.0), (69, 2.0)]),
        _mesure([(71, 4.0)]),
      ],
    );

/// Une mesure de quatre temps, les notes posées à la suite.
Mesure _mesure(List<(int, double)> notes) {
  final List<Note> posees = [];
  double position = 0;
  for (final (int hauteur, double duree) in notes) {
    posees.add(Note(hauteur: hauteur, duree: duree, position: position));
    position += duree;
  }
  return Mesure(notes: posees, duree: 4.0);
}

/// Les débuts et fins de notes, dans l'ordre du temps.
///
/// Le placement vient du moteur ([Reglages.notesSonnantes]) et non d'un calcul
/// refait ici : articulation, respirations et gardes par hauteur sont ainsi
/// exactement celles de l'application. Seule la vélocité est laissée ouverte,
/// puisque c'est ce que le banc met en question.
List<_Evenement> _evenements(Melodie passage) {
  const Reglages reglages = Reglages();
  final List<_Evenement> liste = [];
  for (final sonnante in reglages.notesSonnantes(passage)) {
    liste
      ..add(_Evenement(sonnante.debut, true, sonnante.hauteur))
      ..add(_Evenement(sonnante.fin, false, sonnante.hauteur));
  }
  // À instant égal on éteint avant d'allumer, comme le moteur : deux notes de
  // même hauteur qui se suivent ne se marchent pas dessus.
  liste.sort((a, b) {
    final int parTemps = a.temps.compareTo(b.temps);
    return parTemps != 0 ? parTemps : (a.debut ? 1 : -1);
  });
  return liste;
}

Synthesizer _synthetiseur(ByteData banque) => Synthesizer.loadByteData(
      banque,
      SynthesizerSettings(
        sampleRate: _frequence,
        blockSize: 64,
        maximumPolyphony: 64,
        enableReverbAndChorus: true,
      ),
    );

/// Joue le passage sur une sonorité, à une vélocité donnée.
Int16List _jouer(
  Synthesizer synth,
  int programme,
  List<_Evenement> evenements,
  int velocite,
  double secondesParTemps,
  int echantillons,
) {
  synth.reset();
  synth.processMidiMessage(
      channel: 0, command: 0xC0, data1: programme, data2: 0);

  final ArrayInt16 tampon = ArrayInt16.zeros(numShorts: echantillons);
  int position = 0;

  for (final _Evenement e in evenements) {
    final int cible = (e.temps * secondesParTemps * _frequence)
        .round()
        .clamp(0, echantillons);
    if (cible > position) {
      synth.renderMonoInt16(tampon, offset: position, length: cible - position);
      position = cible;
    }
    if (e.debut) {
      synth.noteOn(channel: 0, key: e.hauteur, velocity: velocite);
    } else {
      synth.noteOff(channel: 0, key: e.hauteur);
    }
  }
  if (position < echantillons) {
    synth.renderMonoInt16(tampon,
        offset: position, length: echantillons - position);
  }

  return tampon.bytes.buffer
      .asInt16List(tampon.bytes.offsetInBytes, echantillons);
}

/// Puissance perçue d'un rendu : sa valeur efficace. C'est elle, et non le
/// pic, qui dit à quel point une chose sonne fort.
double _puissance(Int16List son) {
  double somme = 0;
  for (final int v in son) {
    somme += v * v;
  }
  return math.sqrt(somme / son.length);
}

int _pic(Int16List son, double gain) {
  int pic = 0;
  for (final int v in son) {
    final int a = v.abs();
    if (a > pic) pic = a;
  }
  return (pic * gain).ceil();
}

double _db(double rapport) => 20 * (math.log(rapport) / math.ln10);

double _arrondi(double v) => double.parse(v.toStringAsFixed(1));

/// Le même son, à un autre niveau.
ArrayInt16 _ajuster(Int16List son, double gain) {
  final Int16List ajuste = Int16List(son.length);
  for (int i = 0; i < son.length; i++) {
    ajuste[i] = (son[i] * gain).round().clamp(-32767, 32767);
  }
  return ArrayInt16(bytes: ajuste.buffer.asByteData());
}

/// Vrai si le banc et le moteur ont rendu le même son. Le tampon du moteur est
/// plus long d'une seconde de queue, comme celui du banc : on compare ce qu'ils
/// ont en commun.
bool _identiques(Int16List banc, ArrayInt16 moteur) {
  final int commun = math.min(banc.length, moteur.bytes.lengthInBytes ~/ 2);
  for (int i = 0; i < commun; i++) {
    if (banc[i] != moteur[i]) return false;
  }
  return true;
}

/// Le `rms` de chaque sonorité, tel que l'appli le connaît. C'est ce chiffre-là
/// qu'il faut essayer, pas une mesure refaite sur le passage — sans quoi le
/// banc validerait une égalisation que l'appli ne saurait pas reproduire.
Map<int, double> _rmsPublies(Directory source) {
  final Map<String, dynamic> publie = jsonDecode(
          File('${source.path}/instruments.json').readAsStringSync())
      as Map<String, dynamic>;
  return {
    for (final Map<String, dynamic> i
        in (publie['instruments'] as List).cast<Map<String, dynamic>>())
      i['programme'] as int:
          ((i['standard'] as Map<String, dynamic>)['rms'] as num).toDouble(),
  };
}

class _Evenement {
  final double temps;
  final bool debut;
  final int hauteur;

  _Evenement(this.temps, this.debut, this.hauteur);
}

/// Un extrait à écouter : un fichier, ce qu'il fait entendre, et de quoi le
/// mettre au bon niveau.
class _Extrait {
  _Extrait({
    required this.nom,
    required this.groupe,
    required this.serie,
    required this.instrument,
    required this.variante,
    required this.son,
    required this.gain,
    this.correction,
    this.volumeDeCanal,
  });

  final String nom;

  /// Les extraits d'un même groupe partagent leur gain de sortie, parce qu'on
  /// les compare l'un à l'autre.
  final String groupe;

  final String serie;
  final String instrument;
  final String variante;
  final Int16List son;
  final double gain;

  /// Correction d'égalisation demandée, en dB — série B seulement.
  final double? correction;

  /// Ce que cette correction vaudrait en volume de canal MIDI, tel que
  /// l'appliquerait le moteur.
  final int? volumeDeCanal;
}
