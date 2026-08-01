/// L'épaisseur du son : la mélodie doublée à l'octave et/ou à la quinte, pour
/// donner du corps à un morceau qui n'a qu'une voix.
///
/// C'est un réglage de restitution, au même titre que le tempo : la mélodie
/// elle-même n'est jamais modifiée, seules des voix s'ajoutent au moment de
/// jouer.
enum Epaisseur {
  /// La mélodie seule, telle qu'elle est écrite.
  simple([]),

  /// Une octave en dessous : du corps, du gras.
  chaud([-12]),

  /// Une octave de part et d'autre : brillant et ample.
  large([-12, 12]),

  /// Octave grave et quinte : la sonorité d'un organum ou d'une cornemuse.
  orgue([-12, 7]);

  /// Intervalles ajoutés, en demi-tons, dans l'ordre des canaux.
  final List<int> doublages;

  const Epaisseur(this.doublages);

  /// Vélocité de chaque voix. Les doublages restent en retrait, sinon la
  /// mélodie principale se noie dans la bouillie.
  static const List<int> _velocites = [100, 70, 55];

  /// Ambitus au-delà duquel un doublage n'a plus d'intérêt musical : les
  /// bornes d'un clavier de piano, la0 et do8. Une voix qui en sortirait est
  /// omise, pas repliée.
  static const int _plusGrave = 21;
  static const int _plusAigue = 108;

  /// Nombre de canaux MIDI occupés.
  int get canaux => doublages.length + 1;

  /// Les voix à faire sonner pour une note donnée.
  ///
  /// **Chaque voix a son propre canal, et ce n'est pas un détail.** Sur un
  /// même canal, une mélodie qui enchaîne sol4 puis sol3 ferait tomber le
  /// doublage du sol4 exactement sur le sol3 : la fin du premier couperait le
  /// second, qui vient de démarrer. Des notes s'éteindraient au hasard, sur
  /// certaines mélodies seulement. Ne jamais fusionner les canaux pour
  /// « simplifier ».
  List<({int canal, int hauteur, int velocite})> voix(int hauteur) {
    final List<({int canal, int hauteur, int velocite})> voix = [
      (canal: 0, hauteur: hauteur, velocite: _velocites[0]),
    ];

    for (int i = 0; i < doublages.length; i++) {
      final int doublee = hauteur + doublages[i];
      if (doublee < _plusGrave || doublee > _plusAigue) continue;
      voix.add((canal: i + 1, hauteur: doublee, velocite: _velocites[i + 1]));
    }

    return voix;
  }

  /// Relit un nom enregistré ; un nom inconnu retombe sur la mélodie seule.
  static Epaisseur depuisNom(String? nom) =>
      Epaisseur.values.firstWhere((e) => e.name == nom,
          orElse: () => Epaisseur.simple);
}
