/// La réverbération : le lieu où le morceau semble joué, du studio feutré à
/// la cathédrale.
///
/// Le moteur SoundFont embarque déjà une réverbération (un Freeverb) ; elle se
/// dose par canal avec la commande MIDI 91, de 0 (aucun écho) à 127 (noyé
/// dedans). Quatre lieux nommés suffisent : un curseur en pourcentage ne
/// parlerait à personne.
enum Reverberation {
  studio(0),
  salon(40),
  salle(85),
  eglise(127);

  /// Dose envoyée à la commande MIDI 91.
  ///
  /// [salon] vaut exactement la valeur par défaut du synthétiseur : c'est le
  /// son que l'appli a toujours eu, et donc le réglage de départ.
  final int envoi;

  const Reverberation(this.envoi);

  /// Relit un nom enregistré ; un nom inconnu retombe sur le son habituel.
  static Reverberation depuisNom(String? nom) => Reverberation.values
      .firstWhere((r) => r.name == nom, orElse: () => Reverberation.salon);
}
