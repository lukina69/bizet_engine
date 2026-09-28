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

  /// Le volume de chaque voix, en crans de 4 dB autour du repère
  /// d'égalisation. Zéro laisse l'équilibre automatique tel quel, négatif met
  /// la voix en retrait.
  ///
  /// Il remplace l'ancienne « présence de l'accompagnement », qui était un
  /// seul bouton pour les deux voix ajoutées et n'en offrait aucun à la voix
  /// principale. Maintenant que toutes les voix visent le même repère, c'est
  /// bien à chacune d'avoir le sien : c'est la seule main qui reste sur
  /// l'équilibre, et c'est elle qui rattrape ce que la mesure ne voit pas —
  /// le poids d'une sonorité se mesure sur une note tenue, pas sur une phrase,
  /// et une percussion s'y trouve toujours sous-estimée.
  ///
  /// Toujours trois entrées, dans l'ordre des rangs ; une liste plus courte se
  /// complète de zéros.
  final List<int> volumes;

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

  /// Les voix réglées une à une, quand l'hôte sait le faire. Nul sinon, et
  /// [voix] les déduit alors des champs à plat.
  ///
  /// **C'est un pont, et il est provisoire.** Le modèle vise trois voix qui
  /// portent chacune leur jeu, et les champs à plat au-dessus n'ont plus de
  /// raison d'être une fois que tout le monde les fournit. Mais la scène et le
  /// tirage règlent encore un morceau d'un bloc, et les vider d'un coup
  /// reviendrait à retourner une quinzaine de fichiers pour un résultat que
  /// personne ne verrait. Les deux chemins cohabitent donc le temps que
  /// l'écran apprenne les voix, et le nettoyage vient après, à froid.
  final List<Voix>? _voixChoisies;

  /// Nombre de voix qu'un morceau peut porter. Trois : au-delà, l'oreille
  /// n'entend plus des timbres distincts mais une bouillie.
  static const int voixMaximum = 3;

  const Reglages({
    List<Voix>? voix,
    this.tempo,
    this.instrument,
    this.octave = 0,
    this.majeur,
    this.articulation = 1.0,
    this.balancement = const Balancement(),
    this.epaisseur = Epaisseur.simple,
    this.compagnons = Compagnons.aucun,
    this.volumes = const [0, 0, 0],
    this.brillance = Epaisseur.velociteBase,
    this.rubato = Rubato.mecanique,
    this.nuances = Nuances.uniformes,
    this.graine = 0,
  }) : _voixChoisies = voix;

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

  /// Le chemin inverse : retrouver le cran à partir du multiplicateur.
  ///
  /// L'écran range ses curseurs en crans, les voix portent des
  /// multiplicateurs. Tant que les deux cohabitent, il faut savoir passer de
  /// l'un à l'autre sans garder deux fois la même valeur, ce qui finirait
  /// toujours par les faire diverger.
  static int cranDepuisArticulation(double facteur) =>
      (((facteur - _gatePique) / (_gateLie - _gatePique)) * 100)
          .round()
          .clamp(0, 100);

  static const double _gatePique = 0.25;
  static const double _gateLie = 1.05;

  /// Les voix telles qu'elles se jouent, dans l'ordre de leurs canaux.
  ///
  /// Celles que l'hôte a réglées une à une, quand il en a fourni. Sinon elles
  /// se déduisent des champs à plat et reproduisent alors exactement ce que
  /// l'appli faisait avant les voix : même articulation, même balancement,
  /// mêmes nuances partout, l'épaisseur sur la seule voix principale, et le
  /// retrait d'attaque imposé aux voix ajoutées.
  List<Voix> get voix {
    final List<Voix>? choisies = _voixChoisies;
    if (choisies != null) {
      // Complétée ou tronquée : un fichier de travail écrit par une autre
      // version ne peut pas fabriquer un objet bancal.
      return [
        for (int rang = 0; rang < voixMaximum; rang++)
          rang < choisies.length ? choisies[rang] : const Voix(),
      ];
    }

    return [
      Voix(
        instrument: instrument,
        volume: volumeDe(0),
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
          volume: volumeDe(rang + 1),
        ),
    ];
  }

  /// Le volume du rang demandé, zéro à défaut : un fichier de travail écrit
  /// par une autre version ne peut pas fabriquer un objet bancal.
  int volumeDe(int rang) => rang < volumes.length ? volumes[rang] : 0;

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
          // Toutes les voix se calent, la principale comprise : une boîte à
          // musique ou un tuba en mélodie jouait jusqu'ici à la hauteur
          // écrite, souvent hors de sa tessiture, alors que la même sonorité
          // en voix ajoutée se replaçait toute seule. Deux poids, deux
          // mesures, pour un défaut qui s'entend.
          octave: v.caleeSur(hauteurs, melodie),
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
