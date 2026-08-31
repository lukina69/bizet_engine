import 'balancement.dart';
import 'compagnons.dart';
import 'epaisseur.dart';
import 'melodie.dart';
import 'nuances.dart';
import 'rubato.dart';
import 'voix.dart';

/// Tout ce qui sépare une partition du son qu'on entend.
///
/// La [Melodie] dit ce qui est écrit ; ces réglages disent comment le jouer.
/// Les deux restent distincts : le morceau n'est jamais modifié, on lui
/// applique une lecture. Le même objet vaut pour l'écoute, pour l'export MIDI
/// et pour le rendu d'un fichier — c'est la garantie qu'un morceau exporté
/// sonne comme il sonnait à l'écoute.
///
/// Les réglages qui peuvent valoir « comme c'est écrit » sont nuls par défaut
/// plutôt que fixés à une valeur : sans cela, jouer une partition sans rien
/// régler lui imposerait un tempo et une sonorité qui ne sont pas les siens.
class Reglages {
  /// Tempo voulu en noires par minute, ou nul pour celui de la partition.
  final int? tempo;

  /// Programme General MIDI voulu, ou nul pour celui de la partition.
  final int? instrument;

  /// Transposition en octaves, de part et d'autre.
  final int octave;

  /// Vrai pour le majeur, faux pour le mineur, nul pour le mode écrit.
  final bool? majeur;

  /// Multiplicateur de la durée sonore des notes : 1,0 les laisse sonner
  /// jusqu'à la suivante, 0,4 les pique, au-delà de 1,0 elles se recouvrent.
  final double articulation;

  /// Le balancement, et sur quelle paire de notes il porte.
  final Balancement balancement;

  /// Les doublages qui donnent du corps à la mélodie.
  final Epaisseur epaisseur;

  /// Les instruments qui doublent la mélodie à l'unisson.
  final Compagnons compagnons;

  /// La présence de l'accompagnement, en crans de 4 dB autour de l'équilibre
  /// automatique (zéro) : négatif vers le discret, positif vers l'en-avant.
  final int accompagnement;

  /// La brillance : le grain du son, du plus terne au plus éclatant.
  ///
  /// C'est la vélocité de la mélodie, et **rien que le timbre** — depuis que
  /// le niveau passe par le volume de canal, frapper plus fort ne fait plus
  /// jouer plus fort, seulement plus clair. Au-delà, ça devient métallique ;
  /// en dessous, assourdi.
  ///
  /// Réglable parce qu'aucune valeur ne convient partout : le banc d'écoute a
  /// montré que 100 gagne sur des enceintes de salon et 70 sur le
  /// haut-parleur d'un téléphone. C'est donc un réglage d'appareil, que
  /// l'hôte porte — le moteur, lui, s'en tient à [Epaisseur.velociteBase],
  /// ce qu'il a toujours joué.
  ///
  /// Les voix d'accompagnement suivent, en gardant leur recul : l'équilibre
  /// entre les voix ne dépend jamais de ce réglage, seul le grain d'ensemble
  /// change.
  final int brillance;

  /// La liberté de placement dans le temps : ce qui fait qu'on entend
  /// quelqu'un jouer plutôt qu'une machine.
  final Rubato rubato;

  /// Le poids de chaque note : l'autre moitié du geste humain — le rubato
  /// fait vivre le temps, les nuances font vivre la force.
  final Nuances nuances;

  /// De quoi rejouer exactement le même rubato. Deux graines différentes font
  /// respirer le morceau à des endroits différents, tous justifiés.
  final int graine;

  const Reglages({
    this.tempo,
    this.instrument,
    this.octave = 0,
    this.majeur,
    this.articulation = 1.0,
    this.balancement = const Balancement(),
    this.epaisseur = Epaisseur.simple,
    this.compagnons = Compagnons.aucun,
    this.accompagnement = 0,
    this.brillance = Epaisseur.velociteBase,
    this.rubato = Rubato.mecanique,
    this.nuances = Nuances.uniformes,
    this.graine = 0,
  });

  /// Ce que devient le curseur d'articulation une fois passé au moteur : un
  /// multiplicateur de la durée écrite, du plus piqué (0) au lié (100).
  ///
  /// Il ne descend jamais à zéro — la note serait muette — et dépasse
  /// légèrement 1,0 en haut de course, sans quoi le « lié » laisserait un
  /// blanc entre deux notes au lieu de les enchaîner.
  ///
  /// La conversion vit ici, et non dans l'écran qui porte le curseur : le
  /// tirage de `bizet_scene` en a besoin lui aussi, et deux barèmes feraient
  /// sonner différemment un même pourcentage.
  static double articulationDepuisCran(int cran) =>
      _gatePique + (_gateLie - _gatePique) * (cran.clamp(0, 100) / 100);

  static const double _gatePique = 0.25;
  static const double _gateLie = 1.05;

  /// Les voix telles qu'elles se jouent, dans l'ordre de leurs canaux.
  ///
  /// **Étape de transition.** Le modèle vise trois voix qui portent chacune
  /// leur jeu ; pour l'instant elles se déduisent des réglages à plat, et
  /// reproduisent donc exactement ce que l'appli fait aujourd'hui — même
  /// articulation, même balancement, mêmes nuances partout, l'épaisseur sur la
  /// seule voix principale, et le retrait d'attaque imposé aux voix ajoutées.
  /// La propriété passera aux voix quand l'écran saura les régler.
  List<Voix> get voix => [
        Voix(
          instrument: instrument,
          articulation: articulation,
          balancement: balancement,
          epaisseur: epaisseur,
          nuances: nuances,
        ),
        for (int rang = 0; rang < Compagnons.maximum; rang++)
          Voix(
            instrument: compagnons.rangs[rang],
            articulation: articulation,
            balancement: balancement,
            nuances: nuances,
            volume: accompagnement,
            recul: _reculsAjoutees[rang],
          ),
      ];

  /// Le retrait d'attaque des voix ajoutées, hérité de l'ancien modèle.
  /// Voir [Voix.recul] : il est appelé à disparaître.
  static const List<int> _reculsAjoutees = [20, 35];

  /// Les voix qui sonnent sur ce morceau, résolues : leur sonorité, leurs
  /// canaux MIDI, leur niveau et l'octave où elles se posent.
  ///
  /// **Les canaux sont réservés par rang, allumé ou non.** Deux voix ne
  /// peuvent pas atterrir sur le même canal quel que soit l'ordre dans lequel
  /// l'utilisateur les allume — sans quoi éteindre la première déplacerait la
  /// seconde au milieu d'un morceau, et une note tenue se retrouverait sur un
  /// canal qui vient de changer d'instrument.
  ///
  /// À calculer sur la mélodie **telle qu'elle est jouée** : la voix suit le
  /// morceau quand on le déplace ou qu'on change sa sonorité.
  List<VoixJouee> voixJouees(Melodie melodie) {
    final List<int> hauteurs = [
      for (final mesure in melodie.mesures)
        for (final note in mesure.notes) note.hauteur,
    ];

    final List<VoixJouee> jouees = [];
    final List<Voix> rangs = voix;
    int canal = 0;

    for (int rang = 0; rang < rangs.length; rang++) {
      final Voix v = rangs[rang];
      if (v.sonneAuRang(rang)) {
        jouees.add(VoixJouee(
          voix: v,
          rang: rang,
          premierCanal: canal,
          programme: v.programmeSur(melodie),
          niveau: v.niveauSur(melodie),
          // La voix principale reste à la hauteur écrite : le calage
          // automatique ne s'applique aujourd'hui qu'aux voix ajoutées, et
          // l'étendre est un chantier à part.
          octave: rang == 0 ? v.octave : v.caleeSur(hauteurs, melodie),
        ));
      }
      canal += v.canaux;
    }
    return jouees;
  }

  /// Le rubato du morceau, calculé une fois pour toutes les voix.
  ///
  /// **C'est le chef qui respire, pas chaque instrument.** Deux voix qui
  /// étireraient la pulsation chacune de son côté ne sonneraient pas « plus
  /// vivantes », elles se désynchroniseraient. Les écarts se calculent donc
  /// ici, sur les durées écrites — c'est là que se lisent les silences et les
  /// notes longues, qu'un piqué prononcé effacerait — et chaque voix les
  /// reçoit tels quels.
  List<({double debut, double fin})> rubatoDe(Melodie melodie) =>
      calculerRubato(
        melodie.deroule(respiration: false),
        intensite: rubato.bridePar(balancement),
        graine: graine,
        // Une seule variante pour l'instant : l'appli ne compte pas les tours
        // de boucle. Le calcul, lui, sait déjà en produire d'autres.
        indexCycle: 0,
      );

  /// Les compagnons calés sur ce morceau : chaque voix ajoutée prend le
  /// décalage d'octave qui la met dans sa bonne tessiture, et le niveau qui
  /// l'amène au repère d'égalisation. À calculer sur la
  /// mélodie **telle qu'elle est jouée** (après [applique]) : le compagnon
  /// suit le morceau quand on le déplace ou qu'on change sa sonorité.
  Compagnons compagnonsCales(Melodie melodie) => compagnons.calesSur([
        for (final mesure in melodie.mesures)
          for (final note in mesure.notes) note.hauteur,
      ]).equilibres(presence: accompagnement);

  /// L'écart de vélocité de chaque note, dans l'ordre de [notesSonnantes] :
  /// accent métrique et marche de poids. Les voix d'une même note — mélodie,
  /// doublages, compagnons — le reçoivent toutes : c'est le geste entier qui
  /// s'appuie, pas un timbre isolé.
  List<int> deltasNuances(Melodie melodie, {Nuances? intensite}) =>
      calculerNuances(
        melodie,
        intensite: intensite ?? nuances,
        graine: graine,
        // Une seule variante pour l'instant, comme pour le rubato : l'appli
        // ne compte pas les tours de boucle.
        indexCycle: 0,
      );

  /// Les notes à faire sonner : le rythme écrit, dévié par le rubato, puis
  /// articulé. C'est le seul endroit où ces deux-là se composent, et l'ordre
  /// compte — le piqué se prend sur la durée réellement jouée.
  ///
  /// Le rubato est calculé sur les durées **écrites** : c'est là que se lisent
  /// les silences et les notes longues, qu'un piqué prononcé effacerait.
  List<({double debut, double fin, int hauteur})> notesSonnantes(
    Melodie melodie, {
    double? articulation,
    List<({double debut, double fin})>? ecarts,
  }) =>
      melodie.deroule(
        articulation: articulation ?? this.articulation,
        ecarts: ecarts ?? rubatoDe(melodie),
      );

  /// Le morceau tel qu'il doit sonner : dans le mode et à la hauteur voulus,
  /// au tempo et à la sonorité choisis. L'original n'est pas touché.
  ///
  /// Le mode se change **avant** la transposition : les degrés se comptent
  /// depuis la tonique écrite, pas depuis celle où l'on a déplacé le morceau.
  ///
  /// Ce qui relève du montage — la découpe, l'ordre des mesures — n'est pas
  /// ici : ce sont des choix sur le morceau, pas sur la façon de le jouer.
  Melodie applique(Melodie melodie) {
    final Melodie joue = melodie
        .enMode(majeur ?? melodie.armure?.majeur ?? true)
        .transposee(octave * 12);
    joue.tempo = tempo ?? melodie.tempo;
    joue.instrumentMidi = instrument ?? melodie.instrumentMidi;
    return joue;
  }
}

/// Une voix résolue sur un morceau : tout ce qu'il faut pour la faire sonner,
/// et rien de plus. Le moteur et l'export MIDI lisent la même chose.
class VoixJouee {
  const VoixJouee({
    required this.voix,
    required this.rang,
    required this.premierCanal,
    required this.programme,
    required this.niveau,
    required this.octave,
  });

  final Voix voix;

  /// Son rang parmi les trois : zéro est la voix principale.
  final int rang;

  /// Le premier des [Voix.canaux] canaux MIDI qu'elle occupe.
  final int premierCanal;

  /// La sonorité qu'elle joue vraiment.
  final int programme;

  /// Sa correction de niveau, en dB.
  final double niveau;

  /// L'octave où elle se pose, calage automatique compris.
  final int octave;
}
