import 'dart:convert';

import 'package:dart_melty_soundfont/dart_melty_soundfont.dart'
    show ArrayInt16, ByteData;

import '../model/melodie.dart';
import '../model/recette.dart';
import '../model/reglages.dart';
import '../model/tirage.dart';
import 'rendu_audio.dart';

/// Un tour de boucle joué : le son, et ce que le sort avait choisi.
///
/// Les réglages voyagent avec le son parce qu'ils sont la seule façon de
/// savoir *pourquoi* ce tour-là sonne comme il sonne — indispensable pour
/// régler ses bornes, inutile pour l'hôte qui se contente de jouer.
class Boucle {
  /// La forme d'onde, 16 bits mono, à [Scene.frequence] échantillons par
  /// seconde. Elle porte une seconde de queue, le temps que les notes
  /// s'éteignent.
  final ArrayInt16 son;

  /// Le morceau tiré, tel qu'il est écrit. Son champ `source` porte
  /// l'attribution Mutopia : un hôte qui diffuse cette musique doit
  /// l'afficher, la licence CC BY-SA l'exige.
  final Melodie partition;

  /// La façon dont ce tour-ci le joue.
  final Reglages reglages;

  /// La finesse à laquelle ce son a été fabriqué. L'hôte en a besoin pour
  /// le jouer à la bonne vitesse : une scène peut rendre moins fin que la
  /// qualité du disque compact, pour aller plus vite.
  final int frequence;

  const Boucle({
    required this.son,
    required this.partition,
    required this.reglages,
    required this.frequence,
  });

  /// Nombre d'échantillons du tour, queue comprise.
  int get echantillons => son.bytes.lengthInBytes ~/ 2;

  /// Durée du tour en secondes, queue comprise.
  double get secondes => echantillons / frequence;
}

/// Un tour de boucle servi en deux temps : l'amorce tout de suite, la suite
/// pendant qu'elle joue.
///
/// C'est ce qui supprime le silence au lancement d'un jeu : l'[amorce] — les
/// premières mesures — ne coûte que quelques dizaines de millisecondes là où
/// le tour entier en coûte des centaines. L'hôte la joue sans attendre, et
/// fabrique la [suite] pendant ce temps-là : mises bout à bout, les deux
/// tranches sont, à l'échantillon près, la [Boucle] qu'aurait rendue
/// [Scene.prochaine] — une note tenue traverse la coupure, la réverbération
/// aussi.
class BoucleAmorcee {
  /// Les premières mesures du tour, prêtes à jouer. Sans queue : la musique
  /// continue dans [suite].
  final ArrayInt16 amorce;

  final ArrayInt16 Function() _suite;

  /// Le morceau tiré, comme sur [Boucle.partition] — l'attribution Mutopia
  /// voyage avec.
  final Melodie partition;

  /// La façon dont ce tour-ci le joue.
  final Reglages reglages;

  /// La finesse à laquelle ce son est fabriqué.
  final int frequence;

  BoucleAmorcee({
    required this.amorce,
    required ArrayInt16 Function() rendreSuite,
    required this.partition,
    required this.reglages,
    required this.frequence,
  }) : _suite = rendreSuite;

  /// Le reste du tour, queue comprise, à jouer bout à bout derrière
  /// l'amorce. Ne se rend qu'une fois, et avant tout autre rendu de la même
  /// scène — sinon [StateError].
  ArrayInt16 suite() => _suite();

  /// Nombre d'échantillons de l'amorce seule.
  int get echantillonsAmorce => amorce.bytes.lengthInBytes ~/ 2;

  /// Durée de l'amorce seule, en secondes.
  double get secondesAmorce => echantillonsAmorce / frequence;
}

/// La scène : l'endroit où le morceau se joue pour de vrai.
///
/// C'est le second versant du projet — la partie qu'un autre programme
/// embarque. On lui donne une recette et une banque de sons ; elle rend une
/// boucle à chaque appel de [prochaine], chacune tirée au sort dans les
/// bornes.
///
/// Elle s'arrête au tampon audio : faire sortir ce son d'un haut-parleur
/// regarde l'hôte, et lui seul. C'est ce qui permet de la loger dans un jeu
/// sans y traîner Flutter.
///
/// Le tirage a lieu **une fois par boucle**, pas une fois par note : on a
/// ainsi le temps de savourer le réglage tiré. Il laisse aussi toute la durée
/// d'un tour pour préparer le suivant — mesuré à un demi-seconde de calcul
/// pour quarante secondes de musique, soit un rapport de un à cent trente.
///
/// **Ce calcul n'a pas sa place dans une boucle d'affichage** : quelques
/// centaines de millisecondes valent vingt images. L'hôte le lance dans un
/// isolat pendant que la boucle courante joue.
class Scene {
  static const int frequence = RenduAudio.frequence;

  /// [recette] est le contrat fabriqué par l'atelier Scène de Bizet,
  /// [soundFont] les octets d'un fichier .sf2 — celui que l'atelier exporte,
  /// réduit aux seules sonorités que la recette cite.
  ///
  /// [graine] rejoue exactement la même suite de boucles — utile pour
  /// comparer deux banques, ou pour qu'un test dise toujours la même chose.
  Scene({
    required this.recette,
    required ByteData soundFont,
    int? graine,
    int frequenceRendu = frequence,
    bool reverberation = true,
  }) : _rendu = RenduAudio(
          frequenceRendu: frequenceRendu,
          reverberation: reverberation,
        ) {
    _rendu.chargerSoundFont(soundFont);
    _tirage = Tirage(
      recette,
      instrumentsDisponibles: _rendu.programmes,
      graine: graine,
    );
  }

  /// Même chose à partir du texte d'un fichier `.recette.json`.
  ///
  /// Lève [FormatException] si ce n'en est pas un — un fichier illisible se
  /// signale au démarrage, jamais au milieu d'une partie.
  factory Scene.depuisJson(
    String recette, {
    required ByteData soundFont,
    int? graine,
    int frequenceRendu = frequence,
    bool reverberation = true,
  }) =>
      Scene(
        recette:
            Recette.fromJson(jsonDecode(recette) as Map<String, dynamic>),
        soundFont: soundFont,
        graine: graine,
        frequenceRendu: frequenceRendu,
        reverberation: reverberation,
      );

  final Recette recette;

  final RenduAudio _rendu;
  late final Tirage _tirage;

  /// La finesse à laquelle cette scène fabrique son son.
  int get frequenceRendu => _rendu.frequenceRendu;

  /// Les sonorités que la banque livrée sait vraiment jouer. C'est ce que
  /// vaut « tous » dans une recette en mode libre.
  List<int> get instrumentsDisponibles => _rendu.programmes;

  /// Le tour de boucle suivant : un morceau, un réglage tiré dans ses bornes,
  /// et le son qui en découle.
  Boucle prochaine() {
    final TourDeBoucle tour = _tirage.prochain();
    return Boucle(
      // Le montage est déjà fait : la recette ne porte que les mesures
      // gardées, l'atelier ayant découpé avant d'exporter.
      son: _rendu.rendre(tour.partition, reglages: tour.reglages),
      partition: tour.partition,
      reglages: tour.reglages,
      frequence: _rendu.frequenceRendu,
    );
  }

  /// Le même tour que [prochaine], servi en deux temps : l'amorce — les
  /// [mesuresAmorce] premières mesures — sort presque aussitôt, et l'hôte
  /// fabrique la suite pendant qu'elle joue.
  ///
  /// C'est le geste du premier tour, celui où le joueur attend : les tours
  /// suivants se préparent tranquillement pendant que le précédent joue, en
  /// un seul bloc via [prochaine].
  BoucleAmorcee prochaineAmorcee({int mesuresAmorce = 2}) {
    final TourDeBoucle tour = _tirage.prochain();
    final (amorce: amorce, suite: suite) = _rendu.rendreParAmorce(
      tour.partition,
      reglages: tour.reglages,
      mesuresAmorce: mesuresAmorce,
    );
    return BoucleAmorcee(
      amorce: amorce,
      rendreSuite: suite,
      partition: tour.partition,
      reglages: tour.reglages,
      frequence: _rendu.frequenceRendu,
    );
  }
}
