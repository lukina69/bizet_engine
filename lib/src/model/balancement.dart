/// Les façons de balancer une paire de notes, du droit au pointé.
///
/// Ce réglage ne se prête pas à un curseur : entre deux de ces valeurs, ça ne
/// sonne pas « entre deux », ça sonne indécis. L'oreille range ce qu'elle
/// entend dans l'une de ces cases, et rien d'autre.
///
/// Le chiffre porté par chaque cran est la part de la paire laissée à la
/// première note. Il reste une affaire interne au moteur : au-dehors, on ne
/// manipule que le cran.
enum Swing {
  /// Tel que c'est écrit : les deux notes se partagent la paire à égalité.
  droit(0.500),

  /// Un balancement discret, qu'on sent sans pouvoir le nommer.
  leger(0.580),

  /// La croche du triolet : le balancement du jazz et du blues.
  ternaire(0.667),

  /// Croche pointée et double : le balancement le plus marqué qui reste
  /// musical.
  pointe(0.750);

  const Swing(this._part);

  /// Part de la paire laissée à la première note, de 0,5 (droit) à 0,75.
  final double _part;

  /// Relit un nom enregistré ; un nom inconnu retombe sur le droit.
  static Swing depuisNom(String? nom) =>
      Swing.values.firstWhere((s) => s.name == nom, orElse: () => Swing.droit);

  /// Relit l'ancien réglage, un pourcentage de 0 à 100 : on garde le cran dont
  /// le balancement est le plus proche de ce qui était entendu. À mi-chemin
  /// entre deux crans, le plus balancé l'emporte. Hors plage, on revient au
  /// droit — la valeur n'a pas été écrite par cette application.
  static Swing depuisPourcentage(int? pourcentage) {
    if (pourcentage == null || pourcentage < 0 || pourcentage > 100) {
      return Swing.droit;
    }

    // L'ancien réglage allait du milieu (0,5) aux deux tiers, en droite ligne.
    final double part = 0.5 + (1 / 6) * (pourcentage / 100);

    Swing proche = Swing.droit;
    for (final Swing cran in Swing.values) {
      if ((cran._part - part).abs() <= (proche._part - part).abs()) {
        proche = cran;
      }
    }
    return proche;
  }
}

/// Balancement, ce que le jazz appelle le « swing » : une note sur deux
/// arrive un peu en retard, sans que la précédente ni la suivante ne bougent.
///
/// Au cran droit le morceau est joué tel qu'il est écrit. Aux autres, la note
/// faible tombe plus tard dans la paire — jusqu'aux trois quarts au pointé.
///
/// [fenetre] dit sur quelle durée porte une paire de notes. Elle vaut une
/// noire par défaut (deux croches), mais l'atelier la déduit du morceau :
/// balancer des croches dans un morceau écrit en noires ne s'entendrait pas,
/// puisqu'il n'y aurait aucune note entre les temps.
///
/// Rien n'est modifié dans les notes : seul l'instant où on les joue change,
/// exactement comme le tempo ne change pas les durées écrites.
class Balancement {
  /// Le cran choisi.
  final Swing swing;

  /// Durée d'une paire de notes balancée, en temps (1,0 = une noire).
  final double fenetre;

  const Balancement([this.swing = Swing.droit, this.fenetre = 1.0]);

  /// La paire que balance un morceau dont les notes vont à cette [pulsation] :
  /// deux fois celle-ci. Balancer des croches dans un morceau écrit en noires
  /// ne s'entendrait pas, faute de note entre les temps. Bornée pour rester
  /// musicale — on ne balance ni des rondes, ni des quadruples croches.
  static double fenetrePour(double pulsation) =>
      (pulsation * 2).clamp(0.5, 2.0);

  /// Faux quand le balancement n'aurait aucune prise : quand la pulsation est
  /// aussi longue que la fenêtre — un morceau en blanches, ou plus lent —,
  /// toutes les notes tombent sur un début de paire et rien ne bougerait.
  static bool sEntendSur(double pulsation) =>
      pulsation < fenetrePour(pulsation);

  bool get estDroit => swing == Swing.droit;

  /// Où tombe la note faible dans la fenêtre : au milieu quand c'est droit,
  /// d'autant plus tard que le cran est balancé.
  //
  // TODO(rubato) : au-delà de Swing.leger, le rubato devra être bridé à son
  // cran « leger » — voir docs/rubato.md. Le rubato n'existe pas encore.
  double get pivot => swing._part;

  /// Le même réglage appliqué à un autre morceau.
  Balancement surFenetre(double valeur) => Balancement(swing, valeur);

  /// Déplace un instant, exprimé en temps (1,0 = une noire).
  ///
  /// Les débuts de fenêtre ne bougent jamais — sinon le morceau entier
  /// glisserait — et ce qui se trouve à l'intérieur est étiré avant la note
  /// faible, resserré après. Les notes plus brèves suivent donc d'elles-mêmes,
  /// sans avoir à les traiter à part.
  ///
  /// Le calcul part toujours de l'instant écrit : appliqué à un matériau
  /// inchangé, il rend toujours la même chose, sans rien accumuler.
  double applique(double instant) {
    if (estDroit || fenetre <= 0) return instant;

    final double debut = (instant / fenetre).floorToDouble() * fenetre;
    final double reste = (instant - debut) / fenetre;

    final double place = reste < 0.5
        ? reste / 0.5 * pivot
        : pivot + (reste - 0.5) / 0.5 * (1 - pivot);

    return debut + place * fenetre;
  }
}
