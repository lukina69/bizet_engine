/// Le bourdon : une note tenue sous la mélodie, du premier temps au dernier.
///
/// C'est la poche de la cornemuse, la corde à vide de la vielle, la pédale de
/// l'orgue : la tonique qui sonne en continu pendant que la mélodie se promène
/// au-dessus. Le plus vieux des accompagnements — il n'y a rien à savoir pour
/// l'aimer, et rien à calculer pour le jouer : une seule note, la bonne.
///
/// Il exige de connaître la tonique, donc l'armure. Sans elle, tenir une note
/// au hasard ne ferait pas un bourdon, mais une fausse note interminable.
enum Bourdon {
  /// Pas de bourdon : la mélodie seule.
  aucun([]),

  /// La tonique tenue, seule.
  tonique([0]),

  /// Tonique et quinte, comme les deux tuyaux d'une cornemuse.
  quinte([0, 7]);

  const Bourdon(this.intervalles);

  /// Intervalles tenus, en demi-tons au-dessus de la note du bourdon.
  final List<int> intervalles;

  /// La sonorité du bourdon : le violoncelle. Choisi à la mesure **et à
  /// l'oreille** — l'orgue décroît au fil des secondes (un bourdon qui
  /// s'éteint n'est pas un bourdon), le tuba tient parfaitement mais sa nappe
  /// figée « ronfle » plus qu'elle n'accompagne ; le violoncelle tient aussi
  /// bien (~275 constant sur douze secondes) avec de la chaleur en plus.
  static const int programme = 42;

  /// Vélocité des voix tenues.
  ///
  /// Calibrée contre le **morceau entier**, pas contre une note isolée — la
  /// leçon d'un premier réglage : ~180 de puissance, parfait à côté d'une
  /// note seule, inaudible sous la Vocalise complète, chant et piano
  /// confondus (550-1400). À 50, le violoncelle pèse ~275 : le quart du
  /// volume de la pièce, réglage validé à l'oreille par Ludo — on le sent
  /// plus qu'on ne l'écoute.
  static const int velocite = 50;

  /// Nombre de canaux MIDI occupés.
  int get canaux => intervalles.length;

  /// Où poser le bourdon : la plus haute tonique qui reste au moins une
  /// quinte sous la note la plus grave du morceau — assez loin pour ne pas
  /// s'y mêler, assez près pour qu'on entende qu'ils se parlent.
  ///
  /// Mais jamais sous le sol 2. Un morceau avec accompagnement descend déjà
  /// dans le grave, et une quinte plus bas on quitte ce qu'un haut-parleur de
  /// téléphone sait rendre : le bourdon jouerait dans le vide — vérifié sur la
  /// Vocalise, dont la main gauche descend au do 2 et envoyait le bourdon à
  /// 33 Hz, inaudible. Quand la place manque en dessous, le bourdon s'installe
  /// donc dans le grave audible, au milieu de la texture s'il le faut : c'est
  /// le registre de la vielle à roue, et une pédale au milieu des voix est
  /// aussi vieille que la musique.
  ///
  /// [toniqueEcrite] est une classe de hauteur (0 = do … 11 = si),
  /// [plusBasse] la note la plus grave du morceau tel qu'il est joué,
  /// transposition comprise.
  static int hauteur(int toniqueEcrite, int plusBasse) {
    const int plancher = 43; // sol 2, ~98 Hz : le grave qui sort d'un téléphone

    int note = toniqueEcrite % 12;
    while (note + 12 <= plusBasse - 7) {
      note += 12;
    }
    while (note < plancher) {
      note += 12;
    }
    return note;
  }

  /// Les voix à tenir, chacune sur son canal à partir de [canalDepart].
  /// Vide si la mélodie est vide ou si l'armure manque.
  List<({int canal, int hauteur})> voix(
    int? toniqueEcrite,
    int? plusBasse,
    int canalDepart,
  ) {
    if (toniqueEcrite == null || plusBasse == null) return const [];

    final int base = hauteur(toniqueEcrite, plusBasse);
    return [
      for (int i = 0; i < intervalles.length; i++)
        (canal: canalDepart + i, hauteur: base + intervalles[i]),
    ];
  }

  /// Relit un nom enregistré ; un nom inconnu retombe sur l'absence.
  static Bourdon depuisNom(String? nom) =>
      Bourdon.values.firstWhere((b) => b.name == nom,
          orElse: () => Bourdon.aucun);
}
