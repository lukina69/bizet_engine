import 'armure.dart';
import 'mesure.dart';

/// Le morceau complet, objet partagé en mémoire par tous les écrans/ateliers.
///
/// Tempo et instrument sont des propriétés **globales** (pas par note) :
/// on ne fait pas un séquenceur multi-piste, on reste sur une mélodie simple.
class Melodie {
  String titre;

  /// Référence Mutopia (attribution), portée nativement dès l'import pour être
  /// disponible partout (affichage, rappel de licence à l'export).
  String source;

  /// Tempo en BPM.
  int tempo;

  /// Programme General MIDI (choix de sonorité / instrument).
  int instrumentMidi;

  List<Mesure> mesures;

  /// Tonique et mode écrits sur la partition, quand le fichier les déclare.
  /// Nul sinon : la bascule joyeux/triste est alors impossible, faute de
  /// savoir quelles notes abaisser.
  final Armure? armure;

  Melodie({
    required this.titre,
    required this.source,
    required this.tempo,
    required this.instrumentMidi,
    required this.mesures,
    this.armure,
  });

  /// Écart le plus fréquent entre deux notes qui se suivent, en temps : la
  /// pulsation que l'oreille entend réellement, et non celle que la mesure
  /// annonce.
  ///
  /// Un morceau écrit en noires a une pulsation de 1,0 même en 4/4 ; un
  /// morceau en croches, de 0,5. C'est ce qui permet de balancer un morceau
  /// sans supposer d'avance à quelle vitesse il défile. Vaut 1,0 par défaut,
  /// faute de quoi mesurer.
  double get pulsation {
    final Set<double> depuisLeDebut = {};
    double debutMesure = 0.0;
    for (final mesure in mesures) {
      for (final note in mesure.notes) {
        depuisLeDebut.add(debutMesure + note.position);
      }
      debutMesure += mesure.dureeEffective;
    }

    final List<double> debuts = depuisLeDebut.toList()..sort();
    final Map<String, int> ecarts = {};
    for (int i = 1; i < debuts.length; i++) {
      // Arrondi au millième : deux écarts identiques ne doivent pas être
      // comptés à part pour une poussière de virgule flottante.
      final String ecart = (debuts[i] - debuts[i - 1]).toStringAsFixed(3);
      ecarts[ecart] = (ecarts[ecart] ?? 0) + 1;
    }
    if (ecarts.isEmpty) return 1.0;

    String plusFrequent = ecarts.keys.first;
    for (final e in ecarts.entries) {
      if (e.value > ecarts[plusFrequent]!) plusFrequent = e.key;
    }
    final double valeur = double.parse(plusFrequent);
    return valeur > 0 ? valeur : 1.0;
  }

  /// Transposition globale du morceau de [intervalle] demi-tons.
  Melodie transposee(int intervalle) => Melodie(
        titre: titre,
        source: source,
        tempo: tempo,
        instrumentMidi: instrumentMidi,
        mesures: mesures.map((m) => m.transposee(intervalle)).toList(),
        armure: armure,
      );

  /// Le morceau basculé dans l'autre mode : joyeux s'il était triste, et
  /// l'inverse. Seules la tierce, la sixte et la septième changent — la
  /// mélodie reste reconnaissable.
  ///
  /// Renvoie le morceau tel quel si l'armure est inconnue ou si le mode
  /// demandé est déjà celui de la partition.
  Melodie enMode(bool majeur) {
    final Armure? a = armure;
    if (a == null || a.majeur == majeur) return this;

    return Melodie(
      titre: titre,
      source: source,
      tempo: tempo,
      instrumentMidi: instrumentMidi,
      mesures: [
        for (final m in mesures) m.hauteursPar((h) => a.versMode(h, majeur)),
      ],
      armure: Armure(tonique: a.tonique, majeur: majeur),
    );
  }

  /// Découpe : ne garde que les mesures sélectionnées. Renvoie une nouvelle
  /// mélodie, l'originale reste intacte (aller-retour libre entre ateliers).
  Melodie decoupee() => Melodie(
        titre: titre,
        source: source,
        tempo: tempo,
        instrumentMidi: instrumentMidi,
        mesures: mesures.where((m) => m.selectionnee).toList(),
        armure: armure,
      );

  Map<String, dynamic> toJson() => {
        'titre': titre,
        'source': source,
        'tempo': tempo,
        'instrumentMidi': instrumentMidi,
        'mesures': mesures.map((m) => m.toJson()).toList(),
        if (armure != null) 'armure': armure!.toJson(),
      };

  factory Melodie.fromJson(Map<String, dynamic> j) => Melodie(
        titre: j['titre'] as String,
        source: j['source'] as String,
        tempo: j['tempo'] as int,
        instrumentMidi: j['instrumentMidi'] as int,
        mesures: (j['mesures'] as List)
            .map((m) => Mesure.fromJson(m as Map<String, dynamic>))
            .toList(),
        armure: j['armure'] == null
            ? null
            : Armure.fromJson(j['armure'] as Map<String, dynamic>),
      );
}
