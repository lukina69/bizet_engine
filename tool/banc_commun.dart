import 'dart:math' as math;

import 'package:bizet_engine/bizet_engine.dart';
import 'package:dart_melty_soundfont/dart_melty_soundfont.dart';

/// Ce que tous les bancs d'écoute partagent : le passage, la façon de le
/// jouer, et de quoi mesurer ce qui en sort.
///
/// **Le passage surtout.** Un banc ne vaut que si l'oreille peut reporter d'une
/// séance à l'autre ce qu'elle a appris à la précédente ; deux bancs sur deux
/// phrases différentes ne se comparent pas. Il vit donc ici, en un exemplaire.

/// Qualité de rendu : celle de l'application, pas une pour la route. Juger un
/// timbre sur un rendu dégradé ne prouverait rien de ce qu'on entendra.
const int frequence = RenduAudio.frequence;

/// La queue laissée aux notes pour s'éteindre, comme dans le moteur.
const double queue = 1.0;

/// Le passage : les six premières mesures de la vocalise de Franz Abt, sa
/// ligne de chant seule.
///
/// Monophonique à dessein — c'est le périmètre de Bizet, et un timbre ne
/// s'examine pas sous une texture. La phrase tient tout ce qu'il faut
/// entendre : des tenues longues pour le corps du son, des notes brèves pour
/// l'attaque, un silence pour la chute, et une montée du do central au si.
Melodie passage() => Melodie(
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

/// Combien de temps dure le passage, silence de fin compris.
double secondes(Melodie melodie) =>
    melodie.mesures.fold(0.0, (somme, m) => somme + m.dureeEffective) *
    (60.0 / melodie.tempo);

/// Combien d'échantillons occupe un extrait, queue comprise.
int echantillons(Melodie melodie) =>
    ((secondes(melodie) + queue) * frequence).ceil();

/// Un début ou une fin de note, positionné dans le temps musical.
class Evenement {
  final double temps;
  final bool debut;
  final int hauteur;

  Evenement(this.temps, this.debut, this.hauteur);
}

/// Les débuts et fins de notes, dans l'ordre du temps.
///
/// Le placement vient du moteur ([Reglages.notesSonnantes]) et non d'un calcul
/// refait ici : articulation, respirations et gardes par hauteur sont ainsi
/// exactement celles de l'application. Seuls la vélocité et le niveau restent
/// ouverts, puisque c'est ce que les bancs mettent en question.
List<Evenement> evenements(Melodie melodie) {
  const Reglages reglages = Reglages();
  final List<Evenement> liste = [];
  for (final sonnante in reglages.notesSonnantes(melodie)) {
    liste
      ..add(Evenement(sonnante.debut, true, sonnante.hauteur))
      ..add(Evenement(sonnante.fin, false, sonnante.hauteur));
  }
  // À instant égal on éteint avant d'allumer, comme le moteur : deux notes de
  // même hauteur qui se suivent ne se marchent pas dessus.
  liste.sort((a, b) {
    final int parTemps = a.temps.compareTo(b.temps);
    return parTemps != 0 ? parTemps : (a.debut ? 1 : -1);
  });
  return liste;
}

Synthesizer synthetiseur(ByteData banque) => Synthesizer.loadByteData(
      banque,
      SynthesizerSettings(
        sampleRate: frequence,
        blockSize: 64,
        maximumPolyphony: 64,
        enableReverbAndChorus: true,
      ),
    );

/// Joue le passage sur une sonorité, à une vélocité donnée, éventuellement à
/// un [volumeDeCanal] autre que le repos.
///
/// **Un synthétiseur neuf à chaque appel, et ce n'est pas du luxe** :
/// `Synthesizer.reset()` ne restitue pas un état vierge, si bien qu'un rendu
/// enchaîné derrière un autre ne donne pas le même son qu'un rendu isolé —
/// vérifié, l'écart apparaît dès le trentième échantillon. Un banc dont les
/// extraits dépendraient de l'ordre où on les fabrique ne prouverait rien.
///
/// Le volume de canal est celui du moteur, jamais un gain appliqué après coup :
/// c'est le seul moyen de mesurer ce que l'appli produirait vraiment, plafond
/// de 127 compris.
Int16List jouer(
  ByteData banque,
  int programme,
  List<Evenement> liste,
  int velocite, {
  required double secondesParTemps,
  required int total,
  int? volumeDeCanal,
}) {
  final Synthesizer synth = synthetiseur(banque);
  synth.processMidiMessage(
      channel: 0, command: 0xC0, data1: programme, data2: 0);
  if (volumeDeCanal != null) {
    synth.processMidiMessage(
        channel: 0, command: 0xB0, data1: 0x07, data2: volumeDeCanal);
  }

  final ArrayInt16 tampon = ArrayInt16.zeros(numShorts: total);
  int position = 0;

  for (final Evenement e in liste) {
    final int cible =
        (e.temps * secondesParTemps * frequence).round().clamp(0, total);
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
  if (position < total) {
    synth.renderMonoInt16(tampon, offset: position, length: total - position);
  }

  return tampon.bytes.buffer.asInt16List(tampon.bytes.offsetInBytes, total);
}

/// Puissance perçue d'un rendu : sa valeur efficace. C'est elle, et non le
/// pic, qui dit à quel point une chose sonne fort.
double puissance(Int16List son) {
  double somme = 0;
  for (final int v in son) {
    somme += v * v;
  }
  return math.sqrt(somme / son.length);
}

/// Le niveau atteint par les tranches les plus fortes d'un rendu.
///
/// Tranches de 50 ms, centile 99, soit les trois plus fortes d'une phrase de
/// quatorze secondes. C'est presque le pic, mais moyenné sur une tranche
/// plutôt que pris sur un échantillon isolé.
///
/// **C'est elle qui pèse les sonorités**, et pas la valeur efficace : une
/// percussion passe le plus clair d'une phrase à s'éteindre, la moyenne la
/// dit faible alors que ses attaques la rendent présente. Voir
/// `mesure_poids.dart`.
double niveauQuandCaSonne(Int16List son) {
  const int tranche = 2205; // 50 ms à 44 100 Hz
  final List<double> niveaux = [];

  for (int debut = 0; debut + tranche <= son.length; debut += tranche) {
    double somme = 0;
    for (int i = debut; i < debut + tranche; i++) {
      somme += son[i] * son[i];
    }
    niveaux.add(math.sqrt(somme / tranche));
  }
  if (niveaux.isEmpty) return 0;

  niveaux.sort();
  return niveaux[(niveaux.length * 0.99).floor().clamp(0, niveaux.length - 1)];
}

int pic(Int16List son, [double gain = 1.0]) {
  int haut = 0;
  for (final int v in son) {
    final int a = v.abs();
    if (a > haut) haut = a;
  }
  return (haut * gain).ceil();
}

double db(double rapport) => 20 * (math.log(rapport) / math.ln10);

double arrondi(double v) => double.parse(v.toStringAsFixed(1));

/// Le niveau qu'un volume de canal réalise vraiment, en dB.
///
/// Ce n'est pas tout à fait celui qu'on a demandé : le contrôleur MIDI est un
/// entier, et il plafonne à 127. Un banc qui afficherait la valeur demandée
/// mentirait sur ce que l'appli sait faire.
double dbRendu(int volumeDeCanal) => 40 * (math.log(volumeDeCanal / 100) / math.ln10);

/// Le même son, à un autre niveau. Sert au gain de sortie du banc, jamais à
/// simuler une correction — celle-là passe par le volume de canal.
ArrayInt16 ajuster(Int16List son, double gain) {
  final Int16List ajuste = Int16List(son.length);
  for (int i = 0; i < son.length; i++) {
    ajuste[i] = (son[i] * gain).round().clamp(-32767, 32767);
  }
  return ArrayInt16(bytes: ajuste.buffer.asByteData());
}

/// Vrai si le banc et le moteur ont rendu le même son.
///
/// Les bancs dessinent leurs propres événements, faute de pouvoir tout régler
/// depuis [Reglages] ; ils doivent donc prouver qu'ils jouent la même chose que
/// l'application. Sans ce contrôle, un banc peut mentir sans que personne ne le
/// voie.
bool identiqueAuMoteur(Int16List banc, ArrayInt16 moteur) {
  final int commun = math.min(banc.length, moteur.bytes.lengthInBytes ~/ 2);
  for (int i = 0; i < commun; i++) {
    if (banc[i] != moteur[i]) return false;
  }
  return true;
}
