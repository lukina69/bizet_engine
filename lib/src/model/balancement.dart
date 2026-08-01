/// Balancement, ce que le jazz appelle le « swing » : une note sur deux
/// arrive un peu en retard, sans que la précédente ni la suivante ne bougent.
///
/// À 0 % le morceau est droit, tel qu'il est écrit. À 100 % la note faible
/// tombe aux deux tiers de la paire — la croche du triolet, le balancement du
/// jazz et du blues.
///
/// [fenetre] dit sur quelle durée porte une paire de notes. Elle vaut une
/// noire par défaut (deux croches), mais l'atelier la déduit du morceau :
/// balancer des croches dans un morceau écrit en noires ne s'entendrait pas,
/// puisqu'il n'y aurait aucune note entre les temps.
///
/// Rien n'est modifié dans les notes : seul l'instant où on les joue change,
/// exactement comme le tempo ne change pas les durées écrites.
class Balancement {
  static const int maximum = 100;

  /// Retard de la note faible au balancement maximal, en fraction de fenêtre :
  /// elle passe du milieu (0,5) aux deux tiers.
  static const double _retardMaximal = 1 / 6;

  /// Réglage affiché à l'utilisateur, de 0 à [maximum].
  final int pourcentage;

  /// Durée d'une paire de notes balancée, en temps (1,0 = une noire).
  final double fenetre;

  const Balancement([this.pourcentage = 0, this.fenetre = 1.0]);

  bool get estDroit => pourcentage <= 0;

  /// Où tombe la note faible dans la fenêtre : au milieu quand c'est droit,
  /// aux deux tiers au balancement maximal.
  double get pivot => 0.5 + _retardMaximal * (pourcentage / maximum);

  /// Le même réglage appliqué à un autre morceau.
  Balancement surFenetre(double valeur) => Balancement(pourcentage, valeur);

  /// Déplace un instant, exprimé en temps (1,0 = une noire).
  ///
  /// Les débuts de fenêtre ne bougent jamais — sinon le morceau entier
  /// glisserait — et ce qui se trouve à l'intérieur est étiré avant la note
  /// faible, resserré après. Les notes plus brèves suivent donc d'elles-mêmes,
  /// sans avoir à les traiter à part.
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
