import '../instruments/catalogue.dart';
import '../instruments/egalisation.dart';
import '../instruments/instrument.dart';
import 'balancement.dart';
import 'epaisseur.dart';
import 'melodie.dart';
import 'nuances.dart';

/// Une voix : un instrument, et tout ce qui dit comment il joue.
///
/// C'est l'unité du modèle sonore de Bizet. Un morceau se joue à une, deux ou
/// trois voix ; chacune porte sa sonorité et son jeu, et rien de ce qui est ici
/// n'est partagé avec les autres.
///
/// **Ce qui n'est pas ici est au chef** : le tempo, le rubato et la graine
/// vivent dans [Reglages], au-dessus des voix. Le rubato en particulier ne
/// pourrait pas descendre : deux voix qui respireraient chacune de leur côté ne
/// sonneraient pas « plus vivantes », elles se désynchroniseraient.
///
/// La brillance non plus : c'est un réglage d'appareil, le même pour tout ce
/// qui sonne.
class Voix {
  const Voix({
    this.instrument,
    this.octave = 0,
    this.majeur,
    this.articulation = 1.0,
    this.balancement = const Balancement(),
    this.epaisseur = Epaisseur.simple,
    this.nuances = Nuances.uniformes,
    this.volume = 0,
    this.recul = 0,
  });

  /// Programme General MIDI de la voix.
  ///
  /// Sur la **voix principale**, nul veut dire « la sonorité qu'indique la
  /// partition ». Sur les **voix ajoutées**, nul veut dire éteinte : c'est
  /// ainsi qu'une voix se tait sans quitter son rang, et donc sans déplacer
  /// les canaux MIDI des autres au milieu d'un morceau.
  final int? instrument;

  /// Décalage voulu par l'utilisateur, en octaves, **par-dessus** l'octave
  /// naturelle de la voix — celle où le calage automatique la place. Zéro
  /// laisse donc la voix là où elle sonne bien, et non à la hauteur écrite.
  final int octave;

  /// Vrai pour le majeur, faux pour le mineur, nul pour le mode écrit.
  final bool? majeur;

  /// Multiplicateur de la durée sonore des notes : 1,0 les laisse sonner
  /// jusqu'à la suivante, 0,4 les pique.
  final double articulation;

  /// Le balancement, et sur quelle paire de notes il porte.
  final Balancement balancement;

  /// Les doublages qui donnent du corps à cette voix.
  final Epaisseur epaisseur;

  /// Le poids de chaque note.
  final Nuances nuances;

  /// Le volume de la voix, en crans de 4 dB autour du repère d'égalisation.
  /// Zéro laisse l'équilibre automatique tel quel.
  final int volume;

  /// Recul de vélocité sous la brillance, en crans.
  ///
  /// **Transitoire.** Il porte l'ancien modèle, où les voix ajoutées jouaient
  /// par construction d'une attaque plus molle que la mélodie — 20 et 35 crans
  /// en dessous. C'était le seul moyen de les mettre en retrait avant que le
  /// niveau ait son propre chemin. Maintenant que chaque voix a son volume, ce
  /// retrait-là n'a plus de raison d'être imposé : il disparaîtra, et les trois
  /// voix partiront de la même attaque.
  final int recul;

  /// Vrai quand la voix fait du son. Le rang zéro sonne toujours ; les autres
  /// ne sonnent que si on leur a donné une sonorité.
  bool sonneAuRang(int rang) => rang == 0 || instrument != null;

  /// Le programme réellement joué, la partition servant de recours.
  int programmeSur(Melodie melodie) => instrument ?? melodie.instrumentMidi;

  /// Le niveau de la voix, en dB : l'égalisation, plus la main de
  /// l'utilisateur.
  double niveauSur(Melodie melodie) =>
      correctionEgalisation(programmeSur(melodie)) + volume * dbParCran;

  /// dB par cran de volume : deux crans font 8 dB, un vrai geste sans jamais
  /// devenir brutal.
  static const double dbParCran = 4.0;

  /// Nombre de canaux MIDI qu'occupe la voix : un par doublage d'épaisseur.
  int get canaux => epaisseur.canaux;

  /// L'octave où cette voix sonne juste sur les [hauteurs] données, en plus du
  /// décalage voulu par l'utilisateur.
  ///
  /// Une flûte qui double une ligne de violoncelle monte, un tuba qui double
  /// une ligne de flûte descend — sans réglage : la tessiture vient du
  /// catalogue. Le décalage vaut pour le morceau entier, jamais note à note :
  /// une voix qui sauterait d'octave en cours de route casserait le dessin de
  /// la mélodie.
  int caleeSur(List<int> hauteurs, Melodie melodie) {
    final Instrument? connu = instrumentParProgramme(programmeSur(melodie));
    if (connu == null) return octave;

    int meilleur = 0;
    int plusDedans = -1;
    // À égalité, le plus sobre gagne — zéro d'abord, puis une octave avant
    // deux : dès que le morceau tient dans la tessiture, on ne s'éloigne pas
    // de la mélodie pour un mieux imaginaire.
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
    return meilleur + octave;
  }

  Voix avec({
    int? instrument,
    bool effacerInstrument = false,
    int? octave,
    bool? majeur,
    double? articulation,
    Balancement? balancement,
    Epaisseur? epaisseur,
    Nuances? nuances,
    int? volume,
    int? recul,
  }) =>
      Voix(
        instrument:
            effacerInstrument ? null : (instrument ?? this.instrument),
        octave: octave ?? this.octave,
        majeur: majeur ?? this.majeur,
        articulation: articulation ?? this.articulation,
        balancement: balancement ?? this.balancement,
        epaisseur: epaisseur ?? this.epaisseur,
        nuances: nuances ?? this.nuances,
        volume: volume ?? this.volume,
        recul: recul ?? this.recul,
      );
}
