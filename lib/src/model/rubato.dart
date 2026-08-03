import 'balancement.dart';

/// Le rubato : ce qui sépare un musicien d'une boîte à rythme.
///
/// Personne ne joue exactement en place. Une fin de phrase s'étire, une note
/// longue s'appuie, une reprise après un silence se fait attendre d'un rien.
/// Ces écarts sont minuscules — quelques centièmes de la durée d'une note —
/// mais ce sont eux qui font entendre quelqu'un plutôt que quelque chose.
///
/// **Ce n'est pas du hasard note à note.** Un placement tiré au sort ne sonne
/// pas expressif, il sonne faux : les écarts n'ont d'effet que là où la
/// musique les appelle. Le choix de *quelles* notes dévient est donc
/// entièrement déterminé par la partition ; le hasard ne porte que sur
/// l'ampleur générale et sur la sélection, et ne change qu'aux frontières de
/// boucle.
enum Rubato {
  /// En place, comme une machine.
  mecanique(0.0),

  /// À peine perceptible. C'est le réglage par défaut : on n'entend pas le
  /// rubato, on entend seulement que ce n'est plus une machine.
  leger(0.4),

  /// Franchement joué.
  modere(0.7),

  /// Le plus libre qui reste musical.
  expressif(1.0);

  const Rubato(this._intensite);

  /// Ce par quoi les écarts sont multipliés, de 0 (aucun) à 1.
  final double _intensite;

  /// Relit un nom enregistré ; un nom inconnu retombe sur le défaut.
  static Rubato depuisNom(String? nom) =>
      Rubato.values.firstWhere((r) => r.name == nom, orElse: () => Rubato.leger);

  /// Le rubato réellement appliqué compte tenu du balancement.
  ///
  /// Le balancement est déjà un déplacement systématique du temps. Passé son
  /// cran discret, les deux effets sont de même ampleur et se détruisent
  /// mutuellement : ce qui balance ne peut plus respirer. Le rubato est alors
  /// ramené à son cran léger.
  Rubato bridePar(Balancement balancement) {
    final bool balanceFort = balancement.swing != Swing.droit &&
        balancement.swing != Swing.leger;
    if (!balanceFort) return this;
    return _intensite > Rubato.leger._intensite ? Rubato.leger : this;
  }
}

/// L'écart appliqué à une note : de combien son début et sa fin bougent, en
/// temps (1,0 = une noire). Positif, la note commence ou finit plus tard.
///
/// Les deux sont séparés parce qu'ils ne disent pas la même chose : décaler
/// le début seul retarde une attaque, décaler la fin seule allonge la note et
/// pousse ce qui suit.
typedef EcartRubato = ({double debut, double fin});

/// Une note telle que le calcul la voit : son début et sa fin **écrits**, sans
/// piqué ni balancement. C'est ce que renvoie `Melodie.deroule()`.
typedef NoteEcrite = ({double debut, double fin, int hauteur});

/// Vrai si le morceau offre au rubato de quoi s'exercer.
///
/// Il lui faut au moins un silence, ou une note nettement plus longue que les
/// autres. Une suite de notes toutes semblables et sans respiration ne
/// déclenche aucune règle : le réglage n'y ferait rien, et vaut mieux être
/// grisé que trompeur.
bool rubatoAudible(List<NoteEcrite> notes) {
  if (notes.length < 2) return false;

  final double mediane = _medianeDurees(notes);
  for (int i = 0; i < notes.length; i++) {
    if (notes[i].fin - notes[i].debut >= mediane * _seuilNoteLongue) return true;
    if (i + 1 < notes.length && _silenceApres(notes, i)) return true;
  }
  return false;
}

/// Les écarts à appliquer à chaque note, dans l'ordre où elles viennent.
///
/// Fonction pure : mêmes entrées, mêmes écarts, sans état gardé nulle part.
/// [graine] et [indexCycle] suffisent à reproduire exactement une exécution.
///
/// Le temps emprunté est rendu à l'intérieur de la boucle : la dernière note
/// finit là où elle finissait. Sans cela, le point de raccord d'une lecture en
/// boucle se déplacerait à chaque tour — c'est immédiatement audible.
List<EcartRubato> calculerRubato(
  List<NoteEcrite> notes, {
  required Rubato intensite,
  required int graine,
  required int indexCycle,
}) {
  final List<EcartRubato> aucun = [
    for (final _ in notes) (debut: 0.0, fin: 0.0),
  ];
  if (intensite == Rubato.mecanique || notes.length < 2) return aucun;

  final double mediane = _medianeDurees(notes);
  final _Tirage tirage = _Tirage(graine, indexCycle);
  final double ampleur = intensite._intensite * tirage.multiplicateurDuCycle();

  // Allongements et retards bruts, note par note. Une note peut être candidate
  // à plusieurs titres ; on garde le plus grand plutôt que d'additionner, sinon
  // la dernière note longue d'une phrase partirait deux fois.
  final List<double> allongements = List<double>.filled(notes.length, 0.0);
  final List<double> retards = List<double>.filled(notes.length, 0.0);

  for (int i = 0; i < notes.length; i++) {
    final double duree = notes[i].fin - notes[i].debut;

    // 1. Fin de phrase : la note est suivie d'un silence, ou termine la boucle.
    final bool finDePhrase =
        i == notes.length - 1 || _silenceApres(notes, i);
    // 2. Accent agogique : une note qui dépasse nettement les autres.
    final bool accent = duree >= mediane * _seuilNoteLongue;

    double part = 0.0;
    if (finDePhrase && tirage.retenue()) part = _allongementFinDePhrase;
    if (accent && tirage.retenue()) {
      part = part > _allongementAccent ? part : _allongementAccent;
    }
    allongements[i] = duree * part * ampleur;

    // 3. Reprise après un silence : l'attaque se fait attendre.
    if (i > 0 && _silenceApres(notes, i - 1) && tirage.retenue()) {
      retards[i] = duree * _retardApresSilence * ampleur;
    }
  }

  // Le temps emprunté est rendu par les notes qui n'ont rien demandé, au
  // prorata de leur durée. S'il n'y en a aucune, le reliquat est absorbé par
  // la dernière note — la boucle prime sur la règle.
  final double emprunte = allongements.fold(0.0, (s, a) => s + a);
  if (emprunte > 0) {
    double dureeLibre = 0.0;
    for (int i = 0; i < notes.length; i++) {
      if (allongements[i] == 0 && retards[i] == 0) {
        dureeLibre += notes[i].fin - notes[i].debut;
      }
    }

    if (dureeLibre > 0) {
      for (int i = 0; i < notes.length; i++) {
        if (allongements[i] == 0 && retards[i] == 0) {
          final double duree = notes[i].fin - notes[i].debut;
          allongements[i] = -emprunte * duree / dureeLibre;
        }
      }
    } else {
      allongements[notes.length - 1] -= emprunte;
    }
  }

  // Les allongements s'accumulent : une note qui s'étire pousse tout ce qui la
  // suit. Le retard d'attaque, lui, reste local — il mange le début de sa
  // propre note et ne déplace rien d'autre.
  final List<EcartRubato> ecarts = [];
  double cumul = 0.0;
  for (int i = 0; i < notes.length; i++) {
    final double debut = cumul + retards[i];
    cumul += allongements[i];
    ecarts.add((debut: debut, fin: cumul));
  }
  return ecarts;
}

/// Allongement d'une fin de phrase, en fraction de la durée de la note.
const double _allongementFinDePhrase = 0.12;

/// Allongement d'une note notablement plus longue que les autres.
const double _allongementAccent = 0.07;

/// Retard d'attaque d'une note qui repart après un silence.
const double _retardApresSilence = 0.03;

/// À partir de combien de fois la durée médiane une note fait accent.
const double _seuilNoteLongue = 1.5;

/// Une note est suivie d'un silence si la suivante ne démarre pas dans son
/// prolongement. La tolérance absorbe les poussières de virgule flottante.
bool _silenceApres(List<NoteEcrite> notes, int i) =>
    i + 1 < notes.length && notes[i + 1].debut > notes[i].fin + 1e-9;

double _medianeDurees(List<NoteEcrite> notes) {
  final List<double> durees = [
    for (final n in notes) n.fin - n.debut,
  ]..sort();
  if (durees.isEmpty) return 1.0;
  final int milieu = durees.length ~/ 2;
  return durees.length.isOdd
      ? durees[milieu]
      : (durees[milieu - 1] + durees[milieu]) / 2;
}

/// Le hasard de cette couche : reproductible, et à lui seul.
///
/// Un générateur écrit ici plutôt que celui de la bibliothèque : la même
/// graine doit rendre exactement la même musique sur n'importe quelle machine
/// et n'importe quelle version de Dart. C'est un xorshift, six lignes.
class _Tirage {
  final int _graine;
  final int _indexCycle;

  /// Le flot qui décide quelles déviations sont retenues. Il dépend du cycle :
  /// d'un tour à l'autre, ce ne sont pas les mêmes notes qui respirent.
  int _etat;

  _Tirage(this._graine, this._indexCycle)
      : _etat = _amorce(_graine ^ (_indexCycle * 0x9E3779B9));

  /// Un xorshift 32 bits ne démarre pas d'un état nul, et n'y retombe jamais.
  static int _amorce(int graine) {
    final int v = graine & 0xFFFFFFFF;
    return v == 0 ? 0x2545F491 : v;
  }

  static int _pas(int etat) {
    int v = etat;
    v ^= (v << 13) & 0xFFFFFFFF;
    v ^= v >> 17;
    v ^= (v << 5) & 0xFFFFFFFF;
    return v & 0xFFFFFFFF;
  }

  /// Vrai si une déviation candidate est jouée ce cycle-ci.
  bool retenue() {
    _etat = _pas(_etat);
    return _etat / 0x100000000 < _proportionRetenue;
  }

  double multiplicateurDuCycle() =>
      ampleurDuCycle(graine: _graine, indexCycle: _indexCycle);
}

/// L'ampleur générale d'un tour de boucle, entre 0,6 et 1,0.
///
/// C'est une **marche** aléatoire bornée, et non un tirage indépendant : d'un
/// tour au suivant, le jeu évolue au lieu de sauter. Deux cycles voisins ne
/// s'écartent jamais de plus de 0,2.
///
/// La marche se rejoue depuis le premier cycle à chaque appel : c'est ce qui
/// permet à un cycle donné de toujours rendre la même valeur, sans garder
/// d'état nulle part.
double ampleurDuCycle({required int graine, required int indexCycle}) {
  int etat = _Tirage._amorce(graine);
  double valeur = _ampleurMaximale;
  for (int c = 0; c < indexCycle; c++) {
    etat = _Tirage._pas(etat);
    final double pas = (etat / 0x100000000 * 2 - 1) * _pasMaximal;
    valeur = (valeur + pas).clamp(_ampleurMinimale, _ampleurMaximale);
  }
  return valeur;
}

/// Proportion des déviations candidates effectivement jouées. Toutes restent
/// musicalement justifiées ; c'est leur configuration qui change d'un tour à
/// l'autre.
const double _proportionRetenue = 0.65;

/// Bornes de l'ampleur générale, et écart maximal d'un cycle au suivant.
const double _ampleurMinimale = 0.6;
const double _ampleurMaximale = 1.0;
const double _pasMaximal = 0.2;
