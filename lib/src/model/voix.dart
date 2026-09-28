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

  /// Le volume de la voix, en crans sous le repère d'égalisation. Zéro laisse
  /// l'équilibre automatique tel quel, négatif met la voix en retrait.
  ///
  /// **Le repère est le haut de la course, et c'est un choix.** On pourrait
  /// monter une voix au-dessus, mais pas également : le contrôleur MIDI ne
  /// dépasse son repos que de quatre décibels, et l'égalisation en a déjà
  /// dépensé une part variable selon la sonorité. Le même geste ne donnerait
  /// donc pas le même résultat d'un instrument à l'autre, ce qui est
  /// exactement la surprise que l'égalisation existe pour supprimer. Pour
  /// mettre une voix en avant, on baisse les autres.
  final int volume;

  /// Vrai quand la voix fait du son. Le rang zéro sonne toujours ; les autres
  /// ne sonnent que si on leur a donné une sonorité.
  bool sonneAuRang(int rang) => rang == 0 || instrument != null;

  /// Le programme réellement joué, la partition servant de recours.
  int programmeSur(Melodie melodie) => instrument ?? melodie.instrumentMidi;

  /// Le niveau de la voix, en dB : l'égalisation, plus la main de
  /// l'utilisateur.
  double niveauSur(Melodie melodie) =>
      correctionEgalisation(programmeSur(melodie)) + volume * dbParCran;

  /// dB par cran de volume. Trois : un cran s'entend sans être brutal, et dix
  /// crans mènent à trente décibels sous le reste, c'est-à-dire à un souffle.
  static const double dbParCran = 3.0;

  /// Combien de crans séparent le silence utile du repère.
  static const int cransDeVolume = 10;

  /// Nombre de canaux MIDI qu'occupe la voix : un par doublage d'épaisseur.
  int get canaux => epaisseur.canaux;

  /// L'octave où cette voix sonne juste sur les [hauteurs] données, en plus du
  /// décalage voulu par l'utilisateur.
  ///
  /// Une flûte qui double une ligne de violoncelle monte, un tuba qui double
  /// une ligne de flûte descend, sans réglage : la tessiture vient du
  /// catalogue. C'est ce qui donne son sens au réglage d'octave, dont le zéro
  /// veut dire « là où cette voix sonne bien » et non « à la hauteur écrite ».
  ///
  /// **Le catalogue ne décrit qu'une vingtaine de sonorités sur cent vingt.**
  /// Les autres restent où elles sont : une tessiture musicale se saisit à la
  /// main, elle ne se mesure pas comme un poids. Une sonorité inconnue vaut
  /// donc mieux que devinée. Le décalage vaut pour le morceau entier, jamais note à note :
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
    return _dansLeClavier(meilleur + octave, hauteurs);
  }

  /// Ramène le décalage à ce que le clavier MIDI peut porter.
  ///
  /// Le calage et le réglage de l'utilisateur s'ajoutent, et deux octaves plus
  /// deux peuvent pousser une mélodie aiguë au-delà de la note 127. Une note
  /// qui sort du clavier ne sonne pas : elle disparaît sans un mot, et le
  /// morceau se troue. On rend donc une octave plutôt que de perdre des notes.
  static int _dansLeClavier(int octave, List<int> hauteurs) {
    if (hauteurs.isEmpty) return octave;

    int vise = octave;
    while (vise > 0 && hauteurs.any((h) => h + 12 * vise > 127)) {
      vise--;
    }
    while (vise < 0 && hauteurs.any((h) => h + 12 * vise < 0)) {
      vise++;
    }
    return vise;
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
      );
}
