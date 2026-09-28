/// Les sonorités des voix ajoutées, et rien d'autre.
///
/// **C'est ce qui reste d'un objet qui en faisait bien plus.** Il portait le
/// calage d'octave, l'égalisation des niveaux et la vélocité de chaque voix
/// ajoutée. Tout cela appartient maintenant à `Voix`, qui traite les trois
/// voix de la même façon au lieu de mettre la mélodie à part, et le garder ici
/// revenait à tenir deux comportements dont l'un ne servait plus.
///
/// Il subsiste pour deux raisons, l'une et l'autre temporaires : la scène règle
/// encore un morceau d'un bloc et sa recette parle de compagnons, et le fichier
/// de travail garde une liste de programmes sous ce nom, qu'il faut savoir
/// relire.
class Compagnons {
  /// Nombre de voix ajoutables. Deux suffisent : au-delà, l'oreille n'entend
  /// plus des timbres distincts mais une bouillie.
  static const int maximum = 2;

  /// Programme General MIDI de chaque voix ajoutée, nul quand la voix est
  /// éteinte. Toujours [maximum] entrées, dans un ordre fixe : chaque rang
  /// garde ainsi son canal MIDI, si bien qu'éteindre le premier ne déplace
  /// pas le second au milieu d'un morceau.
  final List<int?> rangs;

  const Compagnons._(this.rangs);

  /// La mélodie seule, sans voix ajoutée.
  static const Compagnons aucun = Compagnons._([null, null]);

  /// Construit à partir d'une liste de programmes, complétée ou tronquée à
  /// [maximum] : un fichier de travail écrit par une autre version ne peut
  /// donc pas fabriquer un objet bancal.
  factory Compagnons(List<int?> rangs) => Compagnons._([
        for (int i = 0; i < maximum; i++) i < rangs.length ? rangs[i] : null,
      ]);

  /// Vrai quand aucune voix n'est allumée.
  bool get vide => rangs.every((r) => r == null);

  /// Une copie où le rang [index] joue [programme] — nul pour l'éteindre.
  Compagnons avec(int index, int? programme) => Compagnons([
        for (int i = 0; i < maximum; i++) i == index ? programme : rangs[i],
      ]);

  List<int?> toJson() => List<int?>.of(rangs);

  /// Relit ce qu'a écrit [toJson]. Tout ce qui n'est pas une liste de nombres
  /// retombe sur la mélodie seule : un fichier plus ancien s'ouvre sans erreur.
  static Compagnons depuisJson(Object? brut) {
    if (brut is! List) return aucun;
    return Compagnons([
      for (final Object? valeur in brut) valeur is num ? valeur.toInt() : null,
    ]);
  }
}
