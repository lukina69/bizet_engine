import 'balancement.dart';
import 'bourdon.dart';
import 'compagnons.dart';
import 'epaisseur.dart';
import 'melodie.dart';
import 'reverberation.dart';
import 'rubato.dart';

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

  /// Le lieu où le morceau semble joué.
  final Reverberation reverberation;

  /// Les doublages qui donnent du corps à la mélodie.
  final Epaisseur epaisseur;

  /// Les instruments qui doublent la mélodie à l'unisson.
  final Compagnons compagnons;

  /// La note tenue sous la mélodie, du premier temps au dernier.
  final Bourdon bourdon;

  /// La liberté de placement dans le temps : ce qui fait qu'on entend
  /// quelqu'un jouer plutôt qu'une machine.
  final Rubato rubato;

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
    this.reverberation = Reverberation.salon,
    this.epaisseur = Epaisseur.simple,
    this.compagnons = Compagnons.aucun,
    this.bourdon = Bourdon.aucun,
    this.rubato = Rubato.mecanique,
    this.graine = 0,
  });

  /// Premier canal MIDI libre après la mélodie, ses doublages et ses
  /// compagnons : celui où le bourdon s'installe.
  int canalBourdon(Melodie melodie) =>
      epaisseur.canaux + compagnons.canaux(epaisseur.canaux).length;

  /// Les voix tenues du bourdon pour ce morceau, chacune sur son canal.
  ///
  /// Vide si le réglage est à l'arrêt, si l'armure manque — sans tonique, pas
  /// de bourdon — ou si le morceau n'a pas de note. La hauteur se cale sous la
  /// note la plus grave **telle qu'elle est jouée** : le bourdon suit le
  /// morceau quand on le descend d'une octave.
  List<({int canal, int hauteur})> voixBourdon(Melodie melodie) {
    final int? tonique = melodie.armure?.tonique;

    int? plusBasse;
    for (final mesure in melodie.mesures) {
      for (final note in mesure.notes) {
        if (plusBasse == null || note.hauteur < plusBasse) {
          plusBasse = note.hauteur;
        }
      }
    }

    return bourdon.voix(tonique, plusBasse, canalBourdon(melodie));
  }

  /// Les notes à faire sonner : le rythme écrit, dévié par le rubato, puis
  /// articulé. C'est le seul endroit où ces deux-là se composent, et l'ordre
  /// compte — le piqué se prend sur la durée réellement jouée.
  ///
  /// Le rubato est calculé sur les durées **écrites** : c'est là que se lisent
  /// les silences et les notes longues, qu'un piqué prononcé effacerait.
  List<({double debut, double fin, int hauteur})> notesSonnantes(
    Melodie melodie,
  ) {
    final List<({double debut, double fin, int hauteur})> ecrites =
        melodie.deroule();

    return melodie.deroule(
      articulation: articulation,
      ecarts: calculerRubato(
        ecrites,
        intensite: rubato.bridePar(balancement),
        graine: graine,
        // Une seule variante pour l'instant : l'appli ne compte pas les tours
        // de boucle. Le calcul, lui, sait déjà en produire d'autres.
        indexCycle: 0,
      ),
    );
  }

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
