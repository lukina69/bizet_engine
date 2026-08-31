/// Comportement du son après l'attaque.
///
/// C'est la distinction la plus utile pour prédire si deux instruments se
/// complètent : un son qui s'éteint et un son qui se tient occupent des rôles
/// différents et cohabitent presque toujours bien.
enum Enveloppe {
  /// Le son décroît seul : percuté, pincé, frappé.
  resonant,

  /// Le son se maintient tant que la note dure : archet, souffle, orgue.
  entretenu,
}

/// Famille de timbre. Sert uniquement à détecter la redondance
/// (deux instruments qui font la même chose).
enum Famille {
  piano,
  clavierElectrique,
  clavecin,
  metallophone,
  percussionBois,
  pince,
  harpe,
  frotte,
  bois,
  cuivre,
  orgue,
  voix,
}

/// Où vit le gros de la tessiture. Dérivé du centre, jamais stocké.
enum Registre { grave, medium, aigu }

/// Ce que le catalogue sait d'un instrument : sa sonorité, sa tessiture
/// musicale, et de quoi prédire ses bonnes associations.
///
/// Le poids naturel n'est pas ici : il se mesure pour les cent vingt
/// sonorités de la banque, dont le catalogue n'en décrit qu'une poignée. Il
/// vit donc dans sa propre table — voir `poidsNaturel` dans `poids.dart`.
class Instrument {
  /// Numéro de programme General MIDI, indexé à partir de 0,
  /// tel qu'attendu par dart_melty_soundfont.
  final int programme;

  /// Le nom du preset dans la banque embarquée. L'appli affiche ses propres
  /// libellés traduits : celui-ci sert au débogage et aux tests.
  final String nom;

  /// Tessiture MUSICALE (note MIDI, do central = 60) : la plage où
  /// l'instrument sonne juste, pas la plage de samples du fichier .sf2 —
  /// celle-ci est presque toujours étirée sur tout le clavier, ce qui ne
  /// veut pas dire que le résultat s'écoute.
  final int noteMin;
  final int noteMax;

  final Enveloppe enveloppe;
  final Famille famille;

  const Instrument({
    required this.programme,
    required this.nom,
    required this.noteMin,
    required this.noteMax,
    required this.enveloppe,
    required this.famille,
  });

  int get centre => (noteMin + noteMax) ~/ 2;
  int get etendue => noteMax - noteMin;

  Registre get registre {
    if (centre < 52) return Registre.grave;
    if (centre < 72) return Registre.medium;
    return Registre.aigu;
  }

  bool contient(int note) => note >= noteMin && note <= noteMax;
}
