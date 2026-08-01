/// Une note de musique.
///
/// Représentation volontairement minimale : hauteur (numéro MIDI), durée et
/// position dans la mesure. Cohérent avec l'esprit simple du projet.
class Note {
  /// Hauteur au format MIDI (60 = do central).
  final int hauteur;

  /// Durée en temps (1.0 = une noire).
  final double duree;

  /// Position dans la mesure (0.0 = tout début de la mesure).
  final double position;

  Note({required this.hauteur, required this.duree, required this.position});

  /// Renvoie une nouvelle note transposée de [intervalle] demi-tons.
  /// La même note, à une autre hauteur : sert aux transformations qui gardent
  /// le rythme intact (bascule majeur/mineur).
  Note avecHauteur(int valeur) =>
      Note(hauteur: valeur, duree: duree, position: position);

  Note transposee(int intervalle) =>
      Note(hauteur: hauteur + intervalle, duree: duree, position: position);

  Map<String, dynamic> toJson() =>
      {'hauteur': hauteur, 'duree': duree, 'position': position};

  factory Note.fromJson(Map<String, dynamic> j) => Note(
        hauteur: j['hauteur'] as int,
        duree: (j['duree'] as num).toDouble(),
        position: (j['position'] as num).toDouble(),
      );
}
