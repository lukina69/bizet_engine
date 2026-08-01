import 'note.dart';

/// Une mesure : une liste de notes, sa durée, plus un état de sélection
/// utilisé par l'atelier de découpe.
class Mesure {
  final List<Note> notes;

  /// Durée de la mesure en temps (4.0 = quatre noires).
  ///
  /// Nécessaire car une mesure peut se terminer par un silence : les notes
  /// seules ne suffisent alors pas à savoir où elle s'arrête. Optionnelle :
  /// si elle vaut null, on retombe sur [dureeDeduite].
  final double? duree;

  /// Cochée/décochée dans l'atelier de découpe. La découpe filtre sur ce
  /// booléen mais ne détruit rien tant que l'utilisateur n'a pas validé.
  final bool selectionnee;

  Mesure({required this.notes, this.duree, this.selectionnee = true});

  /// Durée déduite des notes : fin de la note qui se termine le plus tard.
  /// Ignore un éventuel silence final, d'où l'intérêt de [duree].
  double get dureeDeduite {
    double fin = 0.0;
    for (final note in notes) {
      final double finNote = note.position + note.duree;
      if (finNote > fin) fin = finNote;
    }
    return fin;
  }

  /// Durée à utiliser pour la lecture : celle qui est renseignée, sinon celle
  /// que l'on déduit des notes.
  double get dureeEffective => duree ?? dureeDeduite;

  /// Renvoie une mesure dont chaque hauteur est passée par [transformation],
  /// le rythme et la sélection restant les mêmes.
  Mesure hauteursPar(int Function(int hauteur) transformation) => Mesure(
        notes: [
          for (final n in notes) n.avecHauteur(transformation(n.hauteur)),
        ],
        duree: duree,
        selectionnee: selectionnee,
      );

  /// Renvoie une nouvelle mesure dont toutes les notes sont transposées.
  Mesure transposee(int intervalle) => Mesure(
        notes: notes.map((n) => n.transposee(intervalle)).toList(),
        duree: duree,
        selectionnee: selectionnee,
      );

  /// Renvoie une copie de la mesure avec l'état de sélection donné.
  Mesure avecSelection(bool valeur) =>
      Mesure(notes: notes, duree: duree, selectionnee: valeur);

  /// On sérialise [selectionnee] pour que l'état coché/décoché soit conservé
  /// dans le fichier de travail (option B : on se souvient de la sélection).
  Map<String, dynamic> toJson() => {
        'notes': notes.map((n) => n.toJson()).toList(),
        'duree': duree,
        'selectionnee': selectionnee,
      };

  /// Les champs absents d'un ancien fichier retombent sur leur valeur par
  /// défaut : durée déduite des notes, et mesure sélectionnée.
  factory Mesure.fromJson(Map<String, dynamic> j) => Mesure(
        notes: (j['notes'] as List)
            .map((n) => Note.fromJson(n as Map<String, dynamic>))
            .toList(),
        duree: (j['duree'] as num?)?.toDouble(),
        selectionnee: j['selectionnee'] as bool? ?? true,
      );
}
