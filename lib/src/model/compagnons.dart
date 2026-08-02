/// Un ou deux instruments qui doublent la mélodie **à l'unisson**, pour
/// enrichir le timbre d'un morceau qui n'a qu'une voix.
///
/// Là où [Epaisseur] ajoute des hauteurs (octave, quinte) du même instrument,
/// les compagnons ajoutent des couleurs : la même note jouée en même temps par
/// une flûte et une guitare ne sonne ni comme l'une, ni comme l'autre. C'est
/// un réglage de restitution, comme le tempo — la mélodie elle-même n'est
/// jamais modifiée.
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

  /// Vélocité de chaque voix ajoutée. Nettement en retrait des 100 de la
  /// mélodie : à l'unisson, deux timbres à volume égal ne s'additionnent pas,
  /// ils se masquent, et la mélodie perd son dessin.
  ///
  /// Valeurs de départ, à retoucher à l'oreille : c'est le seul chiffre à
  /// bouger si les compagnons couvrent la mélodie ou s'entendent à peine.
  static const List<int> _velocites = [60, 45];

  /// Vrai quand aucune voix n'est allumée.
  bool get vide => rangs.every((r) => r == null);

  /// Une copie où le rang [index] joue [programme] — nul pour l'éteindre.
  Compagnons avec(int index, int? programme) => Compagnons([
        for (int i = 0; i < maximum; i++)
          i == index ? programme : rangs[i],
      ]);

  /// Les canaux MIDI à préparer, à partir de [premierCanal] : celui qui suit
  /// les canaux déjà pris par l'épaisseur.
  ///
  /// Le rang détermine le canal, allumé ou non : deux voix ne peuvent pas
  /// atterrir sur le même canal, quel que soit l'ordre dans lequel
  /// l'utilisateur les allume.
  List<({int canal, int programme})> canaux(int premierCanal) => [
        for (int i = 0; i < maximum; i++)
          if (rangs[i] case final int programme)
            (canal: premierCanal + i, programme: programme),
      ];

  /// Les voix à faire sonner pour une note donnée, à la même hauteur qu'elle.
  List<({int canal, int hauteur, int velocite})> voix(
    int hauteur,
    int premierCanal,
  ) =>
      [
        for (int i = 0; i < maximum; i++)
          if (rangs[i] != null)
            (
              canal: premierCanal + i,
              hauteur: hauteur,
              velocite: _velocites[i],
            ),
      ];

  List<int?> toJson() => List<int?>.of(rangs);

  /// Relit ce qu'a écrit [toJson]. Tout ce qui n'est pas une liste de nombres
  /// retombe sur la mélodie seule : un fichier plus ancien s'ouvre sans erreur.
  static Compagnons depuisJson(Object? brut) {
    if (brut is! List) return aucun;
    return Compagnons([
      for (final Object? valeur in brut)
        valeur is num ? valeur.toInt() : null,
    ]);
  }
}
