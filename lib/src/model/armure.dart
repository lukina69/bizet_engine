import 'dart:math' as math;

/// L'armure du morceau : sa tonique et son mode, tels qu'ils sont écrits sur
/// la partition (`\key do \major`), ou devinés quand le fichier n'en dit
/// rien (voir [Armure.devinee]).
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

  /// Le portrait type d'un morceau majeur, puis d'un mineur : le poids de
  /// chacun des douze degrés, depuis la tonique. Ce sont les profils de
  /// Krumhansl et Kessler, mesurés à l'oreille sur des auditeurs, la
  /// référence habituelle pour retrouver une tonalité.
  static const List<double> _profilMajeur = [
    6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88,
  ];
  static const List<double> _profilMineur = [
    6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17,
  ];

  /// En dessous, le morceau ne dit pas assez de lui-même pour qu'on devine.
  static const int _classesMinimum = 5;

  /// La tonalité la plus vraisemblable d'un morceau qui n'en déclare pas,
  /// d'après le temps passé sur chacune des douze notes ([durees], de do à
  /// si). Nulle quand le morceau en emploie trop peu pour trancher.
  ///
  /// Beaucoup de fichiers MIDI n'écrivent pas leur armure, et le MIDI est la
  /// porte de Bizet vers la pop : sans cela, le mode restait hors d'atteinte
  /// sur ces morceaux (Ludo, 06/10/2026). On compare le portrait du morceau
  /// aux vingt-quatre portraits types, le plus ressemblant gagne.
  ///
  /// Ce n'est qu'une estimation : elle confond parfois un majeur et son
  /// relatif mineur, qui partagent leurs notes. Une erreur ne touche pas le
  /// morceau tel qu'il est écrit, seulement ce que donne la bascule de mode.
  static Armure? devinee(List<double> durees) {
    assert(durees.length == 12);
    if (durees.where((d) => d > 0).length < _classesMinimum) return null;

    Armure? meilleure;
    double record = double.negativeInfinity;
    for (final bool majeur in const [true, false]) {
      final List<double> profil = majeur ? _profilMajeur : _profilMineur;
      for (int tonique = 0; tonique < 12; tonique++) {
        final double r = _ressemblance(
          durees,
          [for (int i = 0; i < 12; i++) profil[(i - tonique) % 12]],
        );
        if (r > record) {
          record = r;
          meilleure = Armure(tonique: tonique, majeur: majeur);
        }
      }
    }
    return meilleure;
  }

  /// À quel point deux portraits montent et descendent ensemble, de -1 à 1
  /// (corrélation de Pearson).
  static double _ressemblance(List<double> a, List<double> b) {
    final double ma = a.reduce((x, y) => x + y) / a.length;
    final double mb = b.reduce((x, y) => x + y) / b.length;
    double produit = 0, carreA = 0, carreB = 0;
    for (int i = 0; i < a.length; i++) {
      produit += (a[i] - ma) * (b[i] - mb);
      carreA += (a[i] - ma) * (a[i] - ma);
      carreB += (b[i] - mb) * (b[i] - mb);
    }
    final double norme = math.sqrt(carreA * carreB);
    return norme == 0 ? 0 : produit / norme;
  }

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
