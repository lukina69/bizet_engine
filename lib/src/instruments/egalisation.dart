import 'poids.dart';

/// Le niveau sur lequel toutes les voix s'alignent, en décibels sous la
/// sonorité la plus forte de la banque.
///
/// Sans lui, changer la sonorité d'un morceau change son volume : vingt-cinq
/// décibels séparent le trombone du bloc de bois, et l'utilisateur qui essaie
/// des timbres croit régler autre chose que ce qu'il règle.
///
/// **C'est la médiane des poids**, et ce choix a été fait à l'oreille, sur un
/// banc d'écoute (`tool/banc_repere.dart`). Le raisonnement, pour qui voudrait
/// le déplacer : le volume de canal ne monte que de quatre décibels au-dessus
/// de son repos et descend sans limite, si bien qu'aligner revient toujours à
/// **baisser les fortes**. Plus le repère est bas, plus l'appli entière devient
/// discrète. Or les sonorités ne sont pas réparties uniformément : le gros de
/// la troupe tient dans une dizaine de décibels, et la queue basse n'est faite
/// que de percussions.
///
/// À la médiane, l'application ne perd que 0,3 dB de volume d'ensemble et
/// l'écart entre sonorités ordinaires tombe à environ 2 dB. Descendre plus bas
/// ne les rend pas plus égales — ça ne rattrape que les percussions, qu'aucun
/// repère raisonnable ne peut de toute façon remonter, et ça se paie jusqu'à
/// quatorze décibels de volume. Une percussion trop en retrait se corrige au
/// volume de sa voix, pas en assourdissant tout le reste.
///
/// Calculé sur la table plutôt qu'écrit en dur : une nouvelle mesure de la
/// banque le déplace d'elle-même.
final double repereEgalisation = _mediane();

/// La correction à appliquer à [programme] pour l'amener au repère, en dB.
///
/// Zéro quand la banque ne connaît pas cette sonorité : mieux vaut ne rien
/// corriger que corriger au hasard — et il n'y a alors rien à jouer non plus.
double correctionEgalisation(int programme) {
  final double? poids = poidsNaturel(programme);
  return poids == null ? 0.0 : repereEgalisation - poids;
}

double _mediane() {
  final List<double> triees = poidsMesures.values.toList()..sort();
  if (triees.isEmpty) return 0.0;
  final int milieu = triees.length ~/ 2;
  return triees.length.isOdd
      ? triees[milieu]
      : (triees[milieu - 1] + triees[milieu]) / 2;
}
