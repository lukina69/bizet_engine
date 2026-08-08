import 'melodie.dart';

/// La recette : le contrat entre l'atelier qui fabrique les bornes (Bizet)
/// et le module `bizet_scene` qui tirera au sort dedans.
///
/// Un fichier autonome : il embarque tout, partitions comprises, pour que
/// l'hôte (un jeu, une appli) n'ait besoin que de lui et de la banque de
/// sons. Le module tire d'abord quel morceau jouer — selon les poids, jamais
/// deux fois de suite le même — puis tire chaque réglage dans les bornes de
/// ce morceau, une fois par boucle.
///
/// Le format est figé dans `docs/bizet_scene.md`, § 5 bis.
class Recette {
  /// La version d'écriture de ce code. Un fichier plus récent est refusé
  /// plutôt que lu de travers.
  static const int versionCourante = 1;

  final int version;

  /// Libre, pour s'y retrouver — « Capture — niveau 1 ».
  final String nom;

  final List<MorceauRecette> morceaux;

  const Recette({
    this.version = versionCourante,
    required this.nom,
    required this.morceaux,
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'nom': nom,
        'morceaux': morceaux.map((m) => m.toJson()).toList(),
      };

  factory Recette.fromJson(Map<String, dynamic> j) {
    final int version = j['version'] as int;
    if (version > versionCourante) {
      throw FormatException('Recette de version $version, inconnue ici.');
    }
    return Recette(
      version: version,
      nom: j['nom'] as String,
      morceaux: (j['morceaux'] as List)
          .map((m) => MorceauRecette.fromJson(m as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Une entrée de la recette : sa partition, son poids de tirage, et les
/// bornes qui n'ont de sens que rapportées à elle — une plage de tempo
/// 80–150 ne dit pas la même chose sur une gigue et sur un air lent.
class MorceauRecette {
  /// La partition embarquée, attribution Mutopia comprise (son champ
  /// `source`) : la licence CC BY-SA suit le morceau où qu'il aille.
  final Melodie partition;

  /// Poids de tirage face aux autres morceaux : à 3, il sort trois fois
  /// plus souvent qu'un poids 1.
  final int poids;

  final BornesRecette bornes;
  final InstrumentationRecette instrumentation;

  const MorceauRecette({
    required this.partition,
    this.poids = 1,
    required this.bornes,
    required this.instrumentation,
  });

  Map<String, dynamic> toJson() => {
        'partition': partition.toJson(),
        'poids': poids,
        'bornes': bornes.toJson(),
        'instrumentation': instrumentation.toJson(),
      };

  factory MorceauRecette.fromJson(Map<String, dynamic> j) => MorceauRecette(
        partition: Melodie.fromJson(j['partition'] as Map<String, dynamic>),
        poids: j['poids'] as int,
        bornes: BornesRecette.fromJson(j['bornes'] as Map<String, dynamic>),
        instrumentation: InstrumentationRecette.fromJson(
            j['instrumentation'] as Map<String, dynamic>),
      );
}

/// Un intervalle fermé sur l'échelle d'un réglage. Bornes égales : la valeur
/// est figée, le tirage n'a rien à choisir.
class Intervalle {
  final int min;
  final int max;

  const Intervalle(this.min, this.max) : assert(min <= max);

  /// Un intervalle réduit à une seule valeur.
  const Intervalle.fixe(int valeur) : this(valeur, valeur);

  List<int> toJson() => [min, max];

  factory Intervalle.fromJson(List<dynamic> j) =>
      Intervalle(j[0] as int, j[1] as int);
}

/// Les bornes de tirage d'un morceau, chacune sur l'échelle que l'appli
/// utilise déjà : les crans y sont désignés par leur rang dans l'ordre des
/// valeurs (`Swing.values`, `Rubato.values`, `Nuances.values`,
/// `Epaisseur.values`).
class BornesRecette {
  /// En noires par minute.
  final Intervalle tempo;

  /// De 0 (le plus piqué) à 100 (lié), l'échelle du curseur de l'appli.
  final Intervalle articulation;

  final Intervalle swing;
  final Intervalle rubato;
  final Intervalle nuances;
  final Intervalle epaisseur;

  /// Transposition en octaves, de part et d'autre de la hauteur écrite.
  final Intervalle octave;

  /// Présence de l'accompagnement, en crans de 4 dB, zéro étant l'équilibre
  /// automatique et le haut de la course.
  final Intervalle accompagnement;

  /// Le caractère n'est pas un intervalle mais une pondération : la part des
  /// tirages, sur 100, joués dans le mode écrit du morceau — le reste passe
  /// dans l'autre mode.
  final int caractereOrigine;

  const BornesRecette({
    required this.tempo,
    required this.articulation,
    required this.swing,
    required this.rubato,
    required this.nuances,
    required this.epaisseur,
    required this.octave,
    required this.accompagnement,
    this.caractereOrigine = 100,
  });

  Map<String, dynamic> toJson() => {
        'tempo': tempo.toJson(),
        'articulation': articulation.toJson(),
        'swing': swing.toJson(),
        'rubato': rubato.toJson(),
        'nuances': nuances.toJson(),
        'epaisseur': epaisseur.toJson(),
        'octave': octave.toJson(),
        'accompagnement': accompagnement.toJson(),
        'caractereOrigine': caractereOrigine,
      };

  factory BornesRecette.fromJson(Map<String, dynamic> j) => BornesRecette(
        tempo: Intervalle.fromJson(j['tempo'] as List),
        articulation: Intervalle.fromJson(j['articulation'] as List),
        swing: Intervalle.fromJson(j['swing'] as List),
        rubato: Intervalle.fromJson(j['rubato'] as List),
        nuances: Intervalle.fromJson(j['nuances'] as List),
        epaisseur: Intervalle.fromJson(j['epaisseur'] as List),
        octave: Intervalle.fromJson(j['octave'] as List),
        accompagnement: Intervalle.fromJson(j['accompagnement'] as List),
        caractereOrigine: j['caractereOrigine'] as int,
      );
}

/// Les deux façons de choisir qui joue.
enum ModeInstrumentation { couples, libre }

/// Un mariage composé à la main : un principal, ses accompagnants, un poids.
/// Rien ne sonne qui n'ait été écouté.
class CoupleInstruments {
  /// Programme General MIDI de l'instrument qui porte la mélodie.
  final int principal;

  /// Les instruments qui la doublent à l'unisson — les compagnons de
  /// l'appli. Zéro à deux.
  final List<int> accompagnants;

  final int poids;

  const CoupleInstruments({
    required this.principal,
    this.accompagnants = const [],
    this.poids = 1,
  });

  Map<String, dynamic> toJson() => {
        'principal': principal,
        'accompagnants': accompagnants,
        'poids': poids,
      };

  factory CoupleInstruments.fromJson(Map<String, dynamic> j) =>
      CoupleInstruments(
        principal: j['principal'] as int,
        accompagnants: (j['accompagnants'] as List).cast<int>(),
        poids: j['poids'] as int,
      );
}

/// Qui a le droit de sortir. En mode couples, le tirage choisit un couple
/// selon les poids ; en mode libre, il choisit un principal puis un
/// accompagnant, chacun dans sa liste, et le hasard fait les mariages.
class InstrumentationRecette {
  final ModeInstrumentation mode;

  /// Mode couples : les mariages permis.
  final List<CoupleInstruments> couples;

  /// Mode libre : les programmes permis comme principal. Nul : tous ceux que
  /// la banque de sons livrée sait jouer.
  final List<int>? principaux;

  /// Mode libre : les programmes permis comme accompagnant. Nul : tous ;
  /// vide : la mélodie joue seule.
  final List<int>? accompagnants;

  const InstrumentationRecette.enCouples(this.couples)
      : mode = ModeInstrumentation.couples,
        principaux = null,
        accompagnants = null;

  const InstrumentationRecette.libre({this.principaux, this.accompagnants})
      : mode = ModeInstrumentation.libre,
        couples = const [];

  Map<String, dynamic> toJson() => switch (mode) {
        ModeInstrumentation.couples => {
            'mode': 'couples',
            'couples': couples.map((c) => c.toJson()).toList(),
          },
        // « Tous » s'écrit par l'absence de la liste, comme en mémoire.
        ModeInstrumentation.libre => {
            'mode': 'libre',
            if (principaux != null) 'principaux': principaux,
            if (accompagnants != null) 'accompagnants': accompagnants,
          },
      };

  factory InstrumentationRecette.fromJson(Map<String, dynamic> j) =>
      switch (j['mode'] as String) {
        'couples' => InstrumentationRecette.enCouples([
            for (final c in j['couples'] as List)
              CoupleInstruments.fromJson(c as Map<String, dynamic>),
          ]),
        'libre' => InstrumentationRecette.libre(
            principaux: (j['principaux'] as List?)?.cast<int>(),
            accompagnants: (j['accompagnants'] as List?)?.cast<int>(),
          ),
        final autre =>
          throw FormatException('Mode d\'instrumentation inconnu : $autre'),
      };
}
