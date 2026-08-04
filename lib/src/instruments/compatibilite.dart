import 'dart:math';

import 'instrument.dart';

/// Niveau de conseil pour une association d'instruments.
/// Aucun de ces niveaux n'interdit quoi que ce soit : l'appli trie et
/// signale, l'utilisateur reste libre d'essayer les combinaisons bizarres —
/// c'est ainsi qu'il apprend.
///
/// L'ordre des valeurs va du meilleur au pire : c'est lui que
/// [evaluerContre] utilise pour retenir le pire verdict.
enum Compatibilite {
  /// Association qui fonctionne bien dans la plupart des cas.
  conseille,

  /// Rien à signaler.
  neutre,

  /// Les deux instruments se recouvrent peu, ou font double emploi.
  /// À signaler discrètement, jamais à bloquer.
  inattendu,
}

/// Ce que donnerait l'association de deux instruments. Fonction pure : la
/// même paire donne toujours le même verdict, dans un sens comme dans
/// l'autre.
Compatibilite evaluer(Instrument a, Instrument b) {
  // Recouvrement des tessitures, en demi-tons. Négatif si elles sont
  // disjointes.
  final int recouvrement =
      min(a.noteMax, b.noteMax) - max(a.noteMin, b.noteMin);

  // Moins d'une quinte en commun : l'un des deux sera hors tessiture en
  // permanence, ils ne peuvent pas jouer la même mélodie.
  if (recouvrement < 7) return Compatibilite.inattendu;

  // Deux basses simultanées s'empâtent l'une l'autre.
  if (a.registre == Registre.grave && b.registre == Registre.grave) {
    return Compatibilite.inattendu;
  }

  // Même famille et presque toute la tessiture en commun : le second ne fait
  // que répéter le premier.
  if (a.famille == b.famille &&
      recouvrement > 0.75 * min(a.etendue, b.etendue)) {
    return Compatibilite.inattendu;
  }

  // Un son qui s'éteint sur un son qui se tient : les rôles se répartissent
  // d'eux-mêmes.
  if (a.enveloppe != b.enveloppe) return Compatibilite.conseille;

  return Compatibilite.neutre;
}

/// Le verdict d'un candidat contre des instruments déjà choisis : celui de
/// la **pire** paire, pas une moyenne — un instrument qui écrase l'un des
/// deux est un mauvais choix même s'il va bien avec l'autre.
///
/// Sans instrument déjà choisi, rien à signaler.
Compatibilite evaluerContre(Instrument candidat, List<Instrument> deja) {
  if (deja.isEmpty) return Compatibilite.neutre;

  Compatibilite pire = Compatibilite.conseille;
  for (final Instrument choisi in deja) {
    final Compatibilite verdict = evaluer(candidat, choisi);
    if (verdict.index > pire.index) pire = verdict;
  }
  return pire;
}
