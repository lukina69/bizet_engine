import 'melodie.dart';

/// Les nuances : le poids de chaque note.
///
/// Le rubato fait vivre le **temps** ; les nuances font vivre la **force**.
/// Une machine joue toutes les notes au même poids, et l'oreille le lit
/// immédiatement comme « machine » — d'autant plus depuis que la vélocité de
/// base est douce. Deux mécanismes, tous deux minuscules :
///
/// * l'**accent métrique** : le premier temps de la mesure s'appuie un peu,
///   les autres temps un rien — le « UN-deux-trois » d'une valse, ce que
///   fait tout instrumentiste sans y penser ;
/// * la **marche de poids** : une dérive aléatoire bornée autour de la
///   vélocité de base, note par note. Une marche et non des tirages
///   indépendants : des poids tirés au sort sonnent nerveux, une dérive
///   sonne humaine.
enum Nuances {
  /// Toutes les notes au même poids : la machine assumée.
  uniformes(0, 0, 0),

  /// Les valeurs du document de passation : on n'entend pas l'effet, on
  /// entend seulement que c'est vivant. Le réglage par défaut de l'appli.
  souples(10, 4, 8),

  /// Le même geste, franchement dessiné.
  marquees(14, 6, 12);

  const Nuances(this.accentPremierTemps, this.accentTempsFort, this.marche);

  /// Ajout de vélocité sur le premier temps de la mesure.
  final int accentPremierTemps;

  /// Ajout sur les autres notes qui tombent pile sur un temps.
  final int accentTempsFort;

  /// Amplitude de la marche aléatoire, en vélocité, de part et d'autre.
  final int marche;

  /// Relit un nom enregistré ; un nom inconnu retombe sur le défaut de
  /// l'appli.
  static Nuances depuisNom(String? nom) => Nuances.values
      .firstWhere((n) => n.name == nom, orElse: () => Nuances.souples);
}

/// L'écart de vélocité de chaque note du morceau, dans l'ordre où
/// `Melodie.deroule()` les donne : accent métrique plus marche de poids.
///
/// Fonction pure : mêmes entrées, mêmes écarts. [graine] et [indexCycle]
/// suffisent à reproduire exactement une exécution — et la vélocité
/// s'applique au moment du noteOn, si bien qu'un futur compteur de tours
/// pourra faire varier le poids d'un cycle à l'autre sans re-rendre l'audio.
List<int> calculerNuances(
  Melodie melodie, {
  required Nuances intensite,
  required int graine,
  required int indexCycle,
}) {
  final List<int> accents = accentsMetriques(melodie, intensite);
  final List<double> marche = marcheDePoids(
    accents.length,
    amplitude: intensite.marche,
    graine: graine,
    indexCycle: indexCycle,
  );

  return [
    for (int i = 0; i < accents.length; i++)
      accents[i] + marche[i].round(),
  ];
}

/// La part déterministe : l'accent métrique de chaque note, lu sur la
/// partition. Le premier temps de la mesure s'appuie, les autres temps un
/// rien, le reste ne bouge pas.
List<int> accentsMetriques(Melodie melodie, Nuances intensite) {
  final double pulsation = melodie.pulsation;

  final List<int> accents = [];
  for (final mesure in melodie.mesures) {
    for (final note in mesure.notes) {
      // À quel battement la note tombe, et à quelle distance du plus proche
      // — la tolérance absorbe les poussières de virgule flottante.
      final double battement = note.position / pulsation;
      final bool surLeTemps = (battement - battement.round()).abs() < 1e-6;

      if (note.position.abs() < 1e-9) {
        accents.add(intensite.accentPremierTemps);
      } else if (surLeTemps) {
        accents.add(intensite.accentTempsFort);
      } else {
        accents.add(0);
      }
    }
  }
  return accents;
}

/// La part vivante : une marche aléatoire bornée à ±[amplitude], un pas par
/// note. Chaque poids part du précédent — c'est la marche qui sonne humaine.
///
/// Comme pour le rubato, la marche se rejoue depuis le début à chaque appel :
/// un cycle donné rend toujours les mêmes poids, sans état gardé nulle part.
List<double> marcheDePoids(
  int nombre, {
  required int amplitude,
  required int graine,
  required int indexCycle,
}) {
  if (amplitude == 0) return List<double>.filled(nombre, 0.0);

  int etat = _amorce(graine ^ (indexCycle * 0x9E3779B9));
  double valeur = 0.0;

  final List<double> marche = [];
  for (int i = 0; i < nombre; i++) {
    etat = _pas(etat);
    valeur = (valeur + (etat / 0x100000000 * 2 - 1) * _pasDeMarche)
        .clamp(-amplitude.toDouble(), amplitude.toDouble());
    marche.add(valeur);
  }
  return marche;
}

/// De combien un poids peut s'écarter du précédent, en vélocité.
const double _pasDeMarche = 3.0;

/// Le même xorshift que celui du rubato, recopié à dessein : le hasard de
/// chaque couche est reproductible et à elle seule — la même graine doit
/// rendre la même musique sur n'importe quelle machine.
int _amorce(int graine) {
  final int v = graine & 0xFFFFFFFF;
  return v == 0 ? 0x2545F491 : v;
}

int _pas(int etat) {
  int v = etat;
  v ^= (v << 13) & 0xFFFFFFFF;
  v ^= v >> 17;
  v ^= (v << 5) & 0xFFFFFFFF;
  return v & 0xFFFFFFFF;
}
