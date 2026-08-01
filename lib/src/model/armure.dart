/// L'armure du morceau : sa tonique et son mode, tels qu'ils sont écrits sur
/// la partition (`\key do \major`).
///
/// C'est ce qui permet de faire basculer un morceau du joyeux au triste :
/// sans savoir sur quelle note il est bâti, on ne saurait pas quelles notes
/// abaisser.
class Armure {
  /// Tonique en classe de hauteur : 0 = do, 1 = do dièse… 11 = si.
  final int tonique;

  /// Vrai en majeur, faux en mineur.
  final bool majeur;

  const Armure({required this.tonique, required this.majeur});

  /// Degrés qui séparent le majeur du mineur : la tierce, la sixte et la
  /// septième. Comptés en demi-tons depuis la tonique.
  static const List<int> _degresMajeurs = [4, 9, 11];
  static const List<int> _degresMineurs = [3, 8, 10];

  /// La même hauteur, entendue dans l'autre mode.
  ///
  /// Le reste de la gamme ne bouge pas : c'est justement parce que seules
  /// trois notes changent que la mélodie reste reconnaissable tout en changeant
  /// complètement d'humeur.
  int versMode(int hauteur, bool versMajeur) {
    if (versMajeur == majeur) return hauteur;

    final int degre = (hauteur - tonique) % 12;
    if (majeur && _degresMajeurs.contains(degre)) return hauteur - 1;
    if (!majeur && _degresMineurs.contains(degre)) return hauteur + 1;
    return hauteur;
  }

  Map<String, dynamic> toJson() => {'tonique': tonique, 'majeur': majeur};

  factory Armure.fromJson(Map<String, dynamic> j) => Armure(
        tonique: (j['tonique'] as num).toInt(),
        majeur: j['majeur'] as bool,
      );
}
