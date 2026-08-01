import '../model/armure.dart';
import '../model/melodie.dart';
import '../model/mesure.dart';
import '../model/note.dart';

/// Parseur LilyPond (.ly) → [Melodie].
///
/// Reconnu : hauteurs en plusieurs langues (\language nederlands, english,
/// deutsch, italiano...), mode \relative (y compris imbriqué), durées avec
/// points et héritage, silences r/R/s, accords `<c e g>` et leur rappel q,
/// voix parallèles `<<...>>` fusionnées, répétitions \repeat
/// volta/unfold/percent/tremolo déroulées avec leurs \alternative, triolets
/// \tuplet et \times, \transpose, variables et leur assemblage par le
/// \score, fichiers \include (via [inclure]), \time, \tempo chiffré,
/// \header pour l'attribution Mutopia.
///
/// Ignoré sans erreur : nuances, liaisons, articulations, commandes de mise
/// en page, paroles, ornements (\grace...).
///
/// Le morceau reste joué par un seul instrument : les portées d'un \score
/// sont fusionnées dans la même mélodie, conformément à l'esprit de l'appli.
///
/// Stratégie d'extraction : on joue le premier \score qui contient des notes
/// (c'est le morceau assemblé) ; à défaut, la première variable qui en
/// contient (les paroles et les variables muettes sont ignorées).
class LilypondParser {
  /// Demi-tons de chaque degré diatonique au-dessus du do.
  static const List<int> _demiTons = [0, 2, 4, 5, 7, 9, 11];

  /// Modes dont le contenu n'est pas de la musique jouable telle quelle.
  static const Set<String> _modesExclus = {
    'lyricmode', 'addlyrics', 'chordmode', 'drummode', 'figuremode', 'markup',
    'markuplist',
  };

  /// Commandes suivies d'un bloc {...} à sauter intégralement : leur contenu
  /// ressemble à des notes sans en être (paroles...) ou n'en est pas.
  static const Set<String> _commandesAvecBloc = {
    'lyricmode', 'addlyrics', 'lyricsto', 'chordmode', 'drummode',
    'figuremode', 'markup', 'markuplist', 'with', 'header', 'layout',
    'midi', 'paper', 'context', 'alternative',
  };

  /// Ornements : le groupe (ou la note isolée) qui suit est ignoré.
  static const Set<String> _ornements = {
    'grace', 'appoggiatura', 'acciaccatura', 'afterGrace',
  };

  /// Noms de nuances et d'articulations courants : jamais des variables à
  /// dérouler, même si le fichier définit une variable du même nom.
  static const Set<String> _nuances = {
    'p', 'pp', 'ppp', 'pppp', 'f', 'ff', 'fff', 'ffff', 'mp', 'mf',
    'fp', 'sf', 'sfz', 'rfz', 'espressivo', 'breve', 'longa',
  };

  /// Fichiers \include qui définissent les noms de notes : remplacés par la
  /// commande \language équivalente (ancienne syntaxe LilyPond).
  static const Map<String, String> _fichiersLangue = {
    'english.ly': 'english',
    'deutsch.ly': 'deutsch',
    'italiano.ly': 'italiano',
    'nederlands.ly': 'nederlands',
    'espanol.ly': 'espanol',
    'catalan.ly': 'catalan',
    'norsk.ly': 'norsk',
    'portugues.ly': 'portugues',
    'suomi.ly': 'suomi',
    'svenska.ly': 'svenska',
    'vlaams.ly': 'vlaams',
  };

  /// Fichiers \include de la distribution LilyPond, sans musique : ignorés
  /// s'ils ne sont pas fournis par [inclure].
  static const Set<String> _inclusionsIgnorables = {
    'articulate.ly', 'predefined-guitar-fretboards.ly',
    'predefined-ukulele-fretboards.ly', 'predefined-mandolin-fretboards.ly',
    'lilypond-book-preamble.ly', 'event-listener.ly', 'gregorian.ly',
    'makam.ly', 'arabic.ly', 'festival.ly',
  };

  static const double _eps = 1e-6;

  static final RegExp _regexSilence =
      RegExp(r"([rRs])(\d+)?(\.*)(?:\*(\d+))?(?![A-Za-z])");
  static final RegExp _regexRappelAccord =
      RegExp(r"q(\d+)?(\.*)(?:\*(\d+))?(?![A-Za-z])");
  static final RegExp _regexMot = RegExp(r'[A-Za-z]+');
  static final RegExp _regexTempo =
      RegExp(r'\\tempo\s+(?:"[^"]*"\s+)?(\d+)(\.?)\s*=\s*(\d+)');
  static final RegExp _regexTime = RegExp(r'\\time\s+(\d+)\s*/\s*(\d+)');
  static final RegExp _regexKey = RegExp(
      r'\\key\s+([a-z]+)\s*\\(major|minor|aeolian|dorian|mixolydian|lydian'
      r'|phrygian|locrian|ionian)');
  static final RegExp _regexRepeat =
      RegExp(r'\\repeat\s+(volta|unfold|percent|tremolo)\s+(\d+)\s*');
  static final RegExp _regexFraction = RegExp(r'\s*(\d+)\s*/\s*(\d+)');
  static final RegExp _regexDureeSeule = RegExp(r'(\d+)?(\.*)(?:\*(\d+))?');
  static final RegExp _regexInclude = RegExp(r'\\include\s*"([^"]+)"');
  static final RegExp _regexLangue = RegExp(r'\\language\s*"([a-z]+)"');

  /// Parse un fichier LilyPond complet. [inclure] fournit le contenu des
  /// fichiers \include (nom tel qu'écrit dans le fichier) ; sans lui, un
  /// \include inconnu est refusé avec un message clair.
  Melodie parse(String contenu, {String? Function(String nom)? inclure}) {
    String texte = _sansCommentaires(contenu);
    texte = _inclureFichiers(texte, inclure);
    final _Langue langue =
        _Langue.pour(_regexLangue.firstMatch(texte)?.group(1) ?? 'nederlands');
    texte = _deroulerRepetitions(texte);

    final Map<String, String> champs = _champsEntete(texte);
    final int tempo = _tempoGlobal(texte) ?? 120;
    final double dureeMesureInitiale = _signatureGlobale(texte) ?? 4.0;
    final Armure? armure = _armureEcrite(texte, langue);
    final Map<String, String> variables = _variables(texte);

    // Les candidats, par ordre de préférence : chaque \score (le morceau
    // assemblé, toutes portées réunies), puis chaque variable musicale.
    final List<String> candidats = [
      for (final m in RegExp(r'\\score\s*\{').allMatches(texte))
        _blocAccolades(texte, m.end - 1),
      for (final corps in variables.values)
        if (corps.trim().isNotEmpty) corps,
    ];

    FormatException? dernierEchec;
    for (final String corps in candidats) {
      try {
        final List<Mesure> mesures = _parserVoix(
          corps,
          langue: langue,
          variables: variables,
          dureeMesureInitiale: dureeMesureInitiale,
        );
        if (mesures.any((mes) => mes.notes.isNotEmpty)) {
          return Melodie(
            titre: champs['title'] ?? champs['mutopiatitle'] ?? champs['piece'] ?? '',
            source: _attribution(champs),
            tempo: tempo,
            instrumentMidi: 0,
            mesures: mesures,
            armure: armure,
          );
        }
      } on FormatException catch (e) {
        dernierEchec = e; // candidat inexploitable, on essaie le suivant
      }
    }

    throw dernierEchec ??
        const FormatException(
            'Aucune voix mélodique trouvée dans ce fichier LilyPond.');
  }

  // ----------------------------------------------------------- inclusions

  /// Remplace chaque \include par le contenu du fichier. Les fichiers de
  /// langue deviennent la commande \language correspondante ; les fichiers
  /// utilitaires de LilyPond sont ignorés.
  String _inclureFichiers(String texte, String? Function(String)? inclure) {
    int garde = 0;
    while (true) {
      final Match? m = _regexInclude.firstMatch(texte);
      if (m == null) return texte;
      if (++garde > 100 || texte.length > 4000000) {
        throw const FormatException('Inclusions de fichiers sans fin.');
      }

      final String nom = m.group(1)!;
      final String? langue = _fichiersLangue[nom.toLowerCase()];
      String remplacement;
      if (langue != null) {
        remplacement = '\\language "$langue" ';
      } else {
        final String? contenu = inclure?.call(nom);
        if (contenu != null) {
          remplacement = _sansCommentaires(contenu);
        } else if (_inclusionsIgnorables.contains(nom.toLowerCase())) {
          remplacement = ' ';
        } else {
          throw FormatException('Fichier inclus non disponible : $nom');
        }
      }
      texte = texte.replaceRange(m.start, m.end, remplacement);
    }
  }

  // ---------------------------------------------------------------- entête

  String _sansCommentaires(String s) => s
      .replaceAll(RegExp(r'%\{[\s\S]*?%\}'), ' ')
      .replaceAll(RegExp(r'%[^\n]*'), ' ');

  Map<String, String> _champsEntete(String texte) {
    final int debut = texte.indexOf(r'\header');
    if (debut < 0) return {};
    final int ouverture = texte.indexOf('{', debut);
    if (ouverture < 0) return {};
    final String corps = _blocAccolades(texte, ouverture);
    final Map<String, String> champs = {};
    for (final m in RegExp(r'([A-Za-z]+)\s*=\s*"([^"]*)"').allMatches(corps)) {
      champs[m.group(1)!] = m.group(2)!;
    }
    return champs;
  }

  /// Attribution exigée par la licence Mutopia : compositeur, typographe...
  String _attribution(Map<String, String> champs) {
    final List<String> parties = [];
    final String? compositeur = champs['composer'];
    if (compositeur != null && compositeur.isNotEmpty) parties.add(compositeur);
    final bool mutopia = champs.keys.any((k) => k.startsWith('mutopia')) ||
        (champs['footer']?.contains('Mutopia') ?? false);
    if (mutopia) parties.add('Mutopia Project');
    final String? typographe = champs['maintainer'];
    if (typographe != null && typographe.isNotEmpty) {
      parties.add('typographie : $typographe');
    }
    final String? licence = champs['license'];
    if (licence != null && licence.isNotEmpty) parties.add(licence);
    return parties.join(' — ');
  }

  /// Premier \tempo chiffré du fichier, converti en noires par minute.
  /// Exemple : « \tempo 2 = 54 » vaut 108 à la noire.
  int? _tempoGlobal(String texte) {
    final m = _regexTempo.firstMatch(texte);
    if (m == null) return null;
    final int unite = int.parse(m.group(1)!);
    final double noiresParBattement =
        4.0 / unite * (m.group(2)!.isEmpty ? 1.0 : 1.5);
    return (int.parse(m.group(3)!) * noiresParBattement).round();
  }

  /// Première signature rythmique du fichier, en noires par mesure.
  double? _signatureGlobale(String texte) {
    final m = _regexTime.firstMatch(texte);
    if (m == null) return null;
    return int.parse(m.group(1)!) * 4.0 / int.parse(m.group(2)!);
  }

  /// Première armure du fichier : « \key mi \minor » donne la tonique mi et
  /// le mode mineur.
  ///
  /// Les modes anciens sont ramenés à celui des deux dont ils sont le plus
  /// proche : l'appli ne propose que joyeux ou triste, et une dizaine de
  /// morceaux du catalogue sont concernés.
  Armure? _armureEcrite(String texte, _Langue langue) {
    final Match? m = _regexKey.firstMatch(texte);
    if (m == null) return null;

    final ({int degre, int alteration})? note = langue.noms[m.group(1)];
    if (note == null) return null;

    const Set<String> mineurs = {
      'minor', 'aeolian', 'dorian', 'phrygian', 'locrian',
    };

    return Armure(
      tonique: (_demiTons[note.degre] + note.alteration) % 12,
      majeur: !mineurs.contains(m.group(2)),
    );
  }

  // -------------------------------------------------------------- variables

  /// Repère les définitions « nom = expression » et garde le texte des
  /// expressions musicales, préfixes compris (\new Voice = "x" \relative g''
  /// {...}). Les variables sans musique (paroles, markup...) sont notées
  /// vides : une référence \nom vers elles ne jouera rien.
  Map<String, String> _variables(String texte) {
    final Map<String, String> defs = {};
    final int n = texte.length;

    // Le nom doit commencer un mot : « beatStructure = » dans un \set ou
    // « positions = » dans un \override ne sont pas des variables.
    for (final m in RegExp(r'(?:^|[ \t\n{}])([A-Za-z]+)\s*=', multiLine: true)
        .allMatches(texte)) {
      final String nom = m.group(1)!;
      int i = m.end;
      bool exclu = false;

      while (i < n && i - m.end < 400) {
        final String c = texte[i];
        if (c.trim().isEmpty || c == '=' || c == "'" || c == ',') {
          i++;
          continue;
        }
        if (c == '{') {
          defs[nom] =
              exclu ? ' ' : texte.substring(m.end, _finBloc(texte, i));
          break;
        }
        if (c == '<' && i + 1 < n && texte[i + 1] == '<') {
          defs[nom] =
              exclu ? ' ' : texte.substring(m.end, _finChevrons(texte, i));
          break;
        }
        if (c == '"') {
          i++;
          while (i < n && texte[i] != '"') {
            if (texte[i] == '\\') i++;
            i++;
          }
          i++;
          continue;
        }
        if (c == '\\') {
          final Match? mot = _regexMot.matchAsPrefix(texte, i + 1);
          if (mot == null) break;
          if (_modesExclus.contains(mot.group(0)!)) exclu = true;
          i = mot.end;
          continue;
        }
        final Match? mot = _regexMot.matchAsPrefix(texte, i);
        if (mot != null) {
          i = mot.end;
          continue;
        }
        break; // chiffre, #... : pas une expression musicale
      }
      if (!defs.containsKey(nom) && exclu) defs[nom] = ' ';
    }
    return defs;
  }

  // ----------------------------------------------------------- répétitions

  /// Déroule les \repeat en recopiant leur corps : « \repeat volta 2 {A}
  /// \alternative {{X}{Y}} » devient « A X A Y ». C'est ce qu'un auditeur
  /// entend, et le reste du parseur n'a plus à connaître les répétitions.
  ///
  /// S'applique aussi à unfold (même principe), percent (mesures répétées)
  /// et tremolo (le motif est réellement joué n fois). Une forme non
  /// reconnue est jouée une seule fois plutôt que refusée.
  String _deroulerRepetitions(String texte) {
    int garde = 0;
    while (true) {
      final Match? m = _regexRepeat.firstMatch(texte);
      if (m == null) return texte;
      if (++garde > 500 || texte.length > 4000000) {
        throw const FormatException(
            'Répétitions trop nombreuses ou trop imbriquées.');
      }

      final int fois = int.parse(m.group(2)!);
      int i = m.end;
      String corps;
      if (i < texte.length && texte[i] == '{') {
        final int fin = _finBloc(texte, i);
        corps = texte.substring(i, fin); // accolades comprises
        i = fin;
      } else {
        // Répétition d'une seule note ou d'un seul accord (forme rare).
        final Match? note = texte[i] == '<'
            ? RegExp(r'<[^<>]*>\d*\.*(?:\*\d+)?').matchAsPrefix(texte, i)
            : RegExp(r"[a-z]+(?:'+|,+)?\d*\.*(?:\*\d+)?")
                .matchAsPrefix(texte, i);
        if (note == null) {
          // Forme inconnue : on retire la commande, le corps jouera une fois.
          texte = texte.replaceRange(m.start, m.end, ' ');
          continue;
        }
        corps = texte.substring(i, note.end);
        i = note.end;
      }

      // \alternative éventuel : ses blocs de premier niveau sont les fins
      // successives (« première fois », « seconde fois »).
      final List<String> alternatives = [];
      final Match? alt =
          RegExp(r'\s*\\alternative\s*\{').matchAsPrefix(texte, i);
      if (alt != null) {
        final int finAlt = _finBloc(texte, alt.end - 1);
        int j = alt.end;
        while (j < finAlt - 1) {
          if (texte[j] == '{') {
            final int finB = _finBloc(texte, j);
            alternatives.add(texte.substring(j, finB));
            j = finB;
          } else {
            j++;
          }
        }
        i = finAlt;
      }

      final StringBuffer deroule = StringBuffer();
      for (int k = 0; k < fois; k++) {
        deroule
          ..write(corps)
          ..write(' ');
        if (alternatives.isNotEmpty) {
          // S'il y a moins d'alternatives que de passages, la première sert
          // pour tous les premiers passages (règle LilyPond).
          final int idx = (k - (fois - alternatives.length))
              .clamp(0, alternatives.length - 1);
          deroule
            ..write(alternatives[idx])
            ..write(' ');
        }
      }
      texte = texte.replaceRange(m.start, i, deroule.toString());
    }
  }

  // ------------------------------------------------------------- hauteurs

  static int _versMidi(int position, int alteration) {
    final int octave = (position / 7).floor();
    final int degre = position - octave * 7;
    return ((octave + 1) * 12 + _demiTons[degre] + alteration).clamp(0, 127);
  }

  // ----------------------------------------------------------------- voix

  /// Passe 1 : la voix devient une liste de notes datées (temps absolu) et
  /// de changements de signature. Passe 2 : découpe en mesures.
  List<Mesure> _parserVoix(
    String corps, {
    required _Langue langue,
    required Map<String, String> variables,
    required double dureeMesureInitiale,
  }) {
    final _Voix voix = _Voix(langue: langue, variables: variables);
    final double fin =
        voix.sequence(corps, 0, corps.length, 0.0, 1.0, simultane: false);
    return _decouperEnMesures(voix, fin, dureeMesureInitiale);
  }

  /// Découpe les notes datées en mesures, en suivant les changements de
  /// signature. Les mesures entamées sont créées avec leur durée pleine —
  /// un morceau qui finit par des silences garde ainsi ses mesures vides.
  List<Mesure> _decouperEnMesures(
      _Voix voix, double fin, double dureeMesureInitiale) {
    // Tri stable des signatures : à position égale, l'ordre du texte gagne.
    final List<int> ordreSig = List.generate(voix.signatures.length, (k) => k);
    ordreSig.sort((a, b) {
      final int c =
          voix.signatures[a].position.compareTo(voix.signatures[b].position);
      return c != 0 ? c : a.compareTo(b);
    });
    final List<_Signature> signatures = [
      for (final k in ordreSig) voix.signatures[k]
    ];

    // Bornes des mesures. Une signature qui tombe au milieu d'une mesure
    // change la durée de cette mesure depuis son début.
    final List<double> debuts = [];
    final List<double> durees = [];
    double debut = 0.0;
    double duree = dureeMesureInitiale;
    int si = 0;
    while (debut < fin - _eps) {
      while (si < signatures.length &&
          signatures[si].position < debut + duree - _eps) {
        if (signatures[si].duree > _eps) duree = signatures[si].duree;
        si++;
      }
      debuts.add(debut);
      durees.add(duree);
      debut += duree;
    }
    if (debuts.isEmpty) return const [];

    // Chaque note rejoint la mesure qui contient son départ. Tri stable par
    // position : les voix fusionnées s'entrelacent chronologiquement, mais
    // les notes d'un même accord gardent l'ordre du texte.
    final List<int> ordre = List.generate(voix.notes.length, (k) => k);
    ordre.sort((a, b) {
      final int c = voix.notes[a].position.compareTo(voix.notes[b].position);
      return c != 0 ? c : a.compareTo(b);
    });

    final List<List<Note>> parMesure = [for (final _ in debuts) <Note>[]];
    int m = 0;
    for (final k in ordre) {
      final Note n = voix.notes[k];
      while (m < debuts.length - 1 &&
          n.position >= debuts[m] + durees[m] - _eps) {
        m++;
      }
      final double relative = n.position - debuts[m];
      parMesure[m].add(Note(
        hauteur: n.hauteur,
        duree: n.duree,
        position: relative < 0 ? 0.0 : relative,
      ));
    }

    return [
      for (int k = 0; k < debuts.length; k++)
        Mesure(notes: parMesure[k], duree: durees[k]),
    ];
  }

  // --------------------------------------------------------------- durées

  /// Durée en noires d'une écriture chiffrée avec points : « 4. » → 1.5.
  static double? _dureeExplicite(String? chiffres, String? points) {
    if (chiffres == null) return null;
    final int valeur = int.parse(chiffres);
    if (valeur == 0) return null;
    double duree = 4.0 / valeur;
    double ajout = duree / 2;
    for (int k = 0; k < (points?.length ?? 0); k++) {
      duree += ajout;
      ajout /= 2;
    }
    return duree;
  }

  static int _multiplicateur(String? m) => m == null ? 1 : int.parse(m);

  // --------------------------------------------------------------- blocs

  /// Contenu d'un bloc {...}, accolades imbriquées et chaînes respectées.
  String _blocAccolades(String texte, int ouverture) =>
      texte.substring(ouverture + 1, _finBloc(texte, ouverture) - 1);

  /// Indice juste après l'accolade fermante correspondant à [ouverture].
  static int _finBloc(String texte, int ouverture) {
    int profondeur = 0;
    int i = ouverture;
    final int n = texte.length;
    while (i < n) {
      final String c = texte[i];
      if (c == '"') {
        i++;
        while (i < n && texte[i] != '"') {
          if (texte[i] == '\\') i++;
          i++;
        }
      } else if (c == '{') {
        profondeur++;
      } else if (c == '}') {
        profondeur--;
        if (profondeur == 0) return i + 1;
      }
      i++;
    }
    throw const FormatException(
        'Accolade non refermée dans le fichier LilyPond.');
  }

  /// Indice juste après le « >> » fermant le « << » ouvert à [ouverture].
  static int _finChevrons(String texte, int ouverture) {
    int profondeur = 0;
    int i = ouverture;
    final int n = texte.length;
    while (i < n) {
      final String c = texte[i];
      if (c == '"') {
        i++;
        while (i < n && texte[i] != '"') {
          if (texte[i] == '\\') i++;
          i++;
        }
        i++;
      } else if (c == '\\') {
        i += 2; // \< \> \\ : jamais des chevrons de polyphonie
      } else if (c == '<' && i + 1 < n && texte[i + 1] == '<') {
        profondeur++;
        i += 2;
      } else if (c == '>' && i + 1 < n && texte[i + 1] == '>') {
        profondeur--;
        i += 2;
        if (profondeur == 0) return i;
      } else {
        i++;
      }
    }
    throw const FormatException(
        '« << » non refermé dans le fichier LilyPond.');
  }
}

/// Une langue de noms de notes : la table nom → (degré, altération) et les
/// expressions régulières construites dessus.
class _Langue {
  final Map<String, ({int degre, int alteration})> noms;

  /// Note complète : nom, octaves, durée, points, multiplicateur.
  late final RegExp note;

  /// Nom et octaves seuls (notes d'accord).
  late final RegExp accordNote;

  /// Hauteur isolée précédée d'espaces (arguments de \relative, \key...).
  late final RegExp hauteurSeule;

  _Langue(this.noms) {
    final String alternance =
        (noms.keys.toList()..sort((a, b) => b.length.compareTo(a.length)))
            .join('|');
    note = RegExp(
        "($alternance)('+|,+)?(\\d+)?(\\.*)(?:\\*(\\d+))?(?![A-Za-z])");
    accordNote = RegExp("($alternance)('+|,+)?(?![A-Za-z])");
    hauteurSeule = RegExp("\\s*($alternance)('+|,+)?(?![A-Za-z])");
  }

  static final Map<String, _Langue> _cache = {};

  static _Langue pour(String nom) {
    final String cle = const {
          'norsk': 'deutsch',
          'suomi': 'deutsch',
          'svenska': 'deutsch',
          'catalan': 'italiano',
          'portugues': 'italiano',
        }[nom] ??
        nom;
    return _cache.putIfAbsent(
        cle, () => _Langue(_tables[cle] ?? _tables['nederlands']!));
  }

  /// Construit les noms d'une langue « lettres + suffixes », avec d'éventuels
  /// noms irréguliers ajoutés ensuite.
  static Map<String, ({int degre, int alteration})> _table(
    List<String> lettres,
    Map<String, int> suffixes,
  ) {
    final Map<String, ({int degre, int alteration})> m = {};
    for (int d = 0; d < lettres.length; d++) {
      m[lettres[d]] = (degre: d, alteration: 0);
      suffixes.forEach((suffixe, alteration) {
        m['${lettres[d]}$suffixe'] = (degre: d, alteration: alteration);
      });
    }
    return m;
  }

  static final Map<String, Map<String, ({int degre, int alteration})>>
      _tables = {
    'nederlands': _table(
      const ['c', 'd', 'e', 'f', 'g', 'a', 'b'],
      const {'is': 1, 'isis': 2, 'es': -1, 'eses': -2},
    )..addAll({
        'as': (degre: 5, alteration: -1), // la bémol s'écrit aussi « as »
        'ases': (degre: 5, alteration: -2),
        'es': (degre: 2, alteration: -1), // mi bémol s'écrit aussi « es »
        'eses': (degre: 2, alteration: -2),
      }),
    'english': _table(
      const ['c', 'd', 'e', 'f', 'g', 'a', 'b'],
      const {'s': 1, 'ss': 2, 'x': 2, 'f': -1, 'ff': -2},
    ),
    'deutsch': _table(
      const ['c', 'd', 'e', 'f', 'g', 'a'],
      const {'is': 1, 'isis': 2, 'es': -1, 'eses': -2},
    )..addAll({
        'as': (degre: 5, alteration: -1),
        'ases': (degre: 5, alteration: -2),
        'asas': (degre: 5, alteration: -2),
        'es': (degre: 2, alteration: -1),
        'eses': (degre: 2, alteration: -2),
        'h': (degre: 6, alteration: 0), // si bécarre
        'his': (degre: 6, alteration: 1),
        'hisis': (degre: 6, alteration: 2),
        'b': (degre: 6, alteration: -1), // si bémol
        'heses': (degre: 6, alteration: -2),
      }),
    'italiano': _table(
      const ['do', 're', 'mi', 'fa', 'sol', 'la', 'si'],
      const {'d': 1, 'dd': 2, 'b': -1, 'bb': -2},
    ),
    'espanol': _table(
      const ['do', 're', 'mi', 'fa', 'sol', 'la', 'si'],
      const {'s': 1, 'ss': 2, 'b': -1, 'bb': -2},
    ),
  };
}

/// Un changement de signature rythmique, daté en temps absolu.
class _Signature {
  final double position;
  final double duree; // noires par mesure

  _Signature(this.position, this.duree);
}

/// L'état de lecture d'une voix : le parcours du texte en ordre d'écriture,
/// comme le fait LilyPond (le mode relatif et l'héritage des durées suivent
/// l'ordre du texte, y compris à travers les voix parallèles).
class _Voix {
  _Voix({required this.langue, required this.variables});

  final _Langue langue;

  /// Les variables du fichier : une référence \nom déroule son texte.
  final Map<String, String> variables;

  /// Mode relatif courant (modifiable par un \relative imbriqué).
  bool relatif = false;

  /// Référence du mode relatif : position diatonique de la note précédente.
  int precedent = 28; // c'

  /// Durée écrite héritée (1.0 = noire, valeur par défaut de LilyPond).
  double dureeCourante = 1.0;

  /// Notes d'ornement à ignorer (après un \grace sans accolades).
  int hauteursAIgnorer = 0;

  /// Facteur de durée d'un \tuplet sans accolades : ne vaut que pour la
  /// prochaine note.
  double? facteurAtome;

  /// Décalage de \transpose en demi-tons, appliqué à l'émission.
  int transposition = 0;

  /// Décalage lu par \transpose, en attente de l'expression qu'il couvre.
  int transpositionAttente = 0;

  /// Le dernier accord émis, pour son rappel « q ».
  List<({int position, int alteration})> dernierAccord = const [];

  /// Garde-fou contre les variables qui se référencent en boucle.
  int profondeur = 0;

  /// Les notes émises, position en temps absolu depuis le début de la voix.
  final List<Note> notes = [];

  /// Les changements de signature rencontrés.
  final List<_Signature> signatures = [];

  /// Parse [corps] entre [i] et [n] à partir de l'instant [t0], toutes les
  /// durées multipliées par [facteur] (triolets). Renvoie l'instant de fin.
  ///
  /// En mode [simultane] (l'intérieur d'un `<<...>>`), chaque élément de
  /// premier niveau — bloc {...}, `<<...>>`, variable ou voix séparée par
  /// \\ — repart de [t0], et la fin est celle de l'élément le plus long.
  double sequence(
    String corps,
    int i,
    int n,
    double t0,
    double facteur, {
    required bool simultane,
  }) {
    double pos = t0;
    double posMax = t0;

    // Fin d'un élément simultané : on retient sa longueur et on repart.
    void finElement() {
      if (pos > posMax) posMax = pos;
      pos = t0;
    }

    // La transposition en attente est prise par la première expression qui
    // suit le \transpose (bloc, variable ou note isolée).
    int prendreTransposition() {
      final int t = transpositionAttente;
      transpositionAttente = 0;
      return t;
    }

    // Durée d'un atome (note, silence, accord) : lecture de la durée écrite,
    // héritage, multiplicateur, triolets.
    double dureeAtome(String? chiffres, String? points, String? mult) {
      final double? explicite =
          LilypondParser._dureeExplicite(chiffres, points);
      if (explicite != null) dureeCourante = explicite;
      double f = facteur;
      if (facteurAtome != null) {
        f *= facteurAtome!;
        facteurAtome = null;
      }
      return dureeCourante * LilypondParser._multiplicateur(mult) * f;
    }

    while (i < n) {
      final String c = corps[i];

      if (c.trim().isEmpty) {
        i++;
        continue;
      }

      // Chaîne entre guillemets : jamais de la musique.
      if (c == '"') {
        i++;
        while (i < n && corps[i] != '"') {
          if (corps[i] == '\\') i++;
          i++;
        }
        i++;
        continue;
      }

      // Bloc {...} : parsé en séquence, au même instant.
      if (c == '{') {
        final int fin = LilypondParser._finBloc(corps, i);
        final int t = prendreTransposition();
        transposition += t;
        pos = sequence(corps, i + 1, fin - 1, pos, facteur, simultane: false);
        transposition -= t;
        i = fin;
        if (simultane) finElement();
        continue;
      }

      if (c == '<') {
        // Voix parallèles <<...>> : chacune part du même instant, la plus
        // longue donne la durée de l'ensemble. Toutes sont fusionnées.
        if (i + 1 < n && corps[i + 1] == '<') {
          final int fin = LilypondParser._finChevrons(corps, i);
          final int t = prendreTransposition();
          transposition += t;
          pos = sequence(corps, i + 2, fin - 2, pos, facteur, simultane: true);
          transposition -= t;
          i = fin;
          if (simultane) finElement();
          continue;
        }
        // Accord <c e g>4 : toutes les notes à la même position.
        i = _accord(corps, i, n, () => pos, (d) => pos += d, dureeAtome,
            prendreTransposition);
        continue;
      }

      // Commande \xxx.
      if (c == '\\') {
        // Séparateur de voix \\ dans un <<...>>.
        if (i + 1 < n && corps[i + 1] == '\\') {
          i += 2;
          if (simultane) finElement();
          continue;
        }
        final Match? mot = LilypondParser._regexMot.matchAsPrefix(corps, i + 1);
        if (mot == null) {
          i += 2; // \! \< \> \( \) ...
          continue;
        }
        final String nom = mot.group(0)!;
        i = mot.end;

        if (nom == 'time') {
          final Match? t =
              LilypondParser._regexFraction.matchAsPrefix(corps, i);
          if (t != null) {
            signatures.add(_Signature(
                pos, int.parse(t.group(1)!) * 4.0 / int.parse(t.group(2)!)));
            i = t.end;
          }
          continue;
        }
        if (nom == 'tuplet' || nom == 'times') {
          // \tuplet 3/2 : 3 notes dans le temps de 2 → durées × 2/3.
          // \times 2/3 : la fraction est directement le facteur.
          final Match? fr =
              LilypondParser._regexFraction.matchAsPrefix(corps, i);
          if (fr == null) continue;
          i = fr.end;
          final double a = double.parse(fr.group(1)!);
          final double b = double.parse(fr.group(2)!);
          final double facteurTuplet = nom == 'tuplet' ? b / a : a / b;
          // \tuplet 3/2 4 {...} : une durée de groupement peut s'intercaler.
          final Match? groupement =
              RegExp(r'\s*\d+\.*').matchAsPrefix(corps, i);
          int j = groupement?.end ?? i;
          while (j < n && corps[j].trim().isEmpty) {
            j++;
          }
          if (j < n && corps[j] == '{') {
            final int fin = LilypondParser._finBloc(corps, j);
            pos = sequence(corps, j + 1, fin - 1, pos, facteur * facteurTuplet,
                simultane: false);
            i = fin;
            if (simultane) finElement();
          } else {
            facteurAtome = facteurTuplet; // \tuplet 3/2 c4 : une seule note
          }
          continue;
        }
        if (nom == 'relative') {
          // \relative c'' {...} imbriqué : nouveau point de départ, le mode
          // et la référence extérieurs sont restaurés à la fin du bloc.
          int ref = 28; // c'
          final Match? h = langue.hauteurSeule.matchAsPrefix(corps, i);
          if (h != null) {
            ref = _positionDeMatch(h);
            i = h.end;
          }
          int j = i;
          while (j < n && corps[j].trim().isEmpty) {
            j++;
          }
          if (j < n && corps[j] == '{') {
            final int fin = LilypondParser._finBloc(corps, j);
            final bool ancienRelatif = relatif;
            final int ancienPrecedent = precedent;
            relatif = true;
            precedent = ref;
            final int t = prendreTransposition();
            transposition += t;
            pos =
                sequence(corps, j + 1, fin - 1, pos, facteur, simultane: false);
            transposition -= t;
            relatif = ancienRelatif;
            precedent = ancienPrecedent;
            i = fin;
            if (simultane) finElement();
          }
          continue;
        }
        if (nom == 'key') {
          // \key sol \major : la hauteur qui suit n'est pas une note jouée.
          final Match? h = langue.hauteurSeule.matchAsPrefix(corps, i);
          if (h != null) i = h.end;
          continue;
        }
        if (nom == 'transpose') {
          // \transpose do fa : la musique qui suit monte d'une quarte.
          // L'écart est celui des deux hauteurs écrites, en demi-tons.
          int? de;
          int? vers;
          for (int k = 0; k < 2; k++) {
            final Match? h = langue.hauteurSeule.matchAsPrefix(corps, i);
            if (h == null) break;
            final int midi = LilypondParser._versMidi(
                _positionDeMatch(h), _alterationDeMatch(h));
            if (k == 0) {
              de = midi;
            } else {
              vers = midi;
            }
            i = h.end;
          }
          if (de != null && vers != null) transpositionAttente = vers - de;
          continue;
        }
        if (LilypondParser._ornements.contains(nom)) {
          int j = i;
          while (j < n && corps[j].trim().isEmpty) {
            j++;
          }
          if (j < n && corps[j] == '{') {
            i = LilypondParser._finBloc(corps, j); // groupe entier ignoré
          } else {
            hauteursAIgnorer = 1; // ornement d'une seule note
          }
          continue;
        }
        if (LilypondParser._commandesAvecBloc.contains(nom)) {
          // \lyricsto "mélodie" {...} : un nom éventuel précède le bloc.
          int j = i;
          while (j < n && corps[j].trim().isEmpty) {
            j++;
          }
          if (j < n && corps[j] == '=') j++;
          while (j < n && corps[j].trim().isEmpty) {
            j++;
          }
          if (j < n && corps[j] == '"') {
            j++;
            while (j < n && corps[j] != '"') {
              if (corps[j] == '\\') j++;
              j++;
            }
            j++;
          }
          while (j < n && corps[j].trim().isEmpty) {
            j++;
          }
          if (j < n && corps[j] == '{') i = LilypondParser._finBloc(corps, j);
          continue;
        }

        // Référence à une variable du fichier : son texte est joué ici.
        final String? def = variables[nom];
        if (def != null &&
            def.trim().isNotEmpty &&
            !LilypondParser._nuances.contains(nom)) {
          if (++profondeur > 32) {
            throw const FormatException(
                'Variables LilyPond imbriquées sans fin.');
          }
          final int t = prendreTransposition();
          transposition += t;
          pos = sequence(def, 0, def.length, pos, facteur, simultane: false);
          transposition -= t;
          profondeur--;
          if (simultane) finElement();
          continue;
        }

        continue; // toute autre commande est ignorée
      }

      // Expression Scheme : #'positions, ##f, #'(5 . 5)...
      if (c == '#') {
        i++;
        if (i < n && corps[i] == "'") i++;
        if (i < n && corps[i] == '(') {
          int profondeurParentheses = 0;
          while (i < n) {
            if (corps[i] == '(') profondeurParentheses++;
            if (corps[i] == ')') {
              profondeurParentheses--;
              if (profondeurParentheses == 0) {
                i++;
                break;
              }
            }
            i++;
          }
        } else {
          while (i < n &&
              corps[i].trim().isNotEmpty &&
              corps[i] != '{' &&
              corps[i] != '}') {
            i++;
          }
        }
        continue;
      }

      // Silence (r), silence multi-mesures (R) ou silence invisible (s).
      final Match? silence =
          LilypondParser._regexSilence.matchAsPrefix(corps, i);
      if (silence != null) {
        i = silence.end;
        pos += dureeAtome(silence.group(2), silence.group(3), silence.group(4));
        continue;
      }

      // Rappel du dernier accord : q.
      final Match? rappel =
          LilypondParser._regexRappelAccord.matchAsPrefix(corps, i);
      if (rappel != null && dernierAccord.isNotEmpty) {
        i = rappel.end;
        final double duree =
            dureeAtome(rappel.group(1), rappel.group(2), rappel.group(3));
        for (final p in dernierAccord) {
          notes.add(Note(
            hauteur: _midi(p.position, p.alteration),
            duree: duree,
            position: pos,
          ));
        }
        if (relatif) precedent = dernierAccord.first.position;
        pos += duree;
        continue;
      }

      // Note.
      final Match? note = langue.note.matchAsPrefix(corps, i);
      if (note != null) {
        i = note.end;
        if (hauteursAIgnorer > 0) {
          hauteursAIgnorer--;
          continue;
        }
        final double duree =
            dureeAtome(note.group(3), note.group(4), note.group(5));

        final nomNote = langue.noms[note.group(1)!]!;
        final String octaves = note.group(2) ?? '';
        final int hauts = "'".allMatches(octaves).length;
        final int bas = ','.allMatches(octaves).length;
        final int t = prendreTransposition(); // \transpose d'une seule note

        notes.add(Note(
          hauteur:
              _midi(_position(nomNote.degre, hauts, bas), nomNote.alteration) +
                  t,
          duree: duree,
          position: pos,
        ));
        pos += duree;
        continue;
      }

      // Mot quelconque (Moderato, treble...) : ignoré d'un bloc.
      final Match? mot = LilypondParser._regexMot.matchAsPrefix(corps, i);
      if (mot != null) {
        i = mot.end;
        continue;
      }

      i++; // | ( ) ~ ^ > _ - . chiffres isolés, etc.
    }

    if (pos > posMax) posMax = pos;
    return posMax;
  }

  /// Hauteur MIDI d'une position diatonique, transposition comprise.
  int _midi(int position, int alteration) =>
      (LilypondParser._versMidi(position, alteration) + transposition)
          .clamp(0, 127);

  /// Position diatonique de l'argument d'un \relative, \key ou \transpose.
  int _positionDeMatch(Match h) {
    final int degre = langue.noms[h.group(1)!]!.degre;
    final String octaves = h.group(2) ?? '';
    final int hauts = "'".allMatches(octaves).length;
    final int bas = ','.allMatches(octaves).length;
    return (3 + hauts - bas) * 7 + degre;
  }

  int _alterationDeMatch(Match h) => langue.noms[h.group(1)!]!.alteration;

  /// Position diatonique d'une note écrite, selon le mode courant. En mode
  /// relatif, la note se place à moins d'une quarte de la précédente, puis
  /// les marques ' et , la décalent d'octave en octave.
  int _position(int lettre, int hauts, int bas) {
    if (!relatif) return (3 + hauts - bas) * 7 + lettre;
    int ecart = (lettre - ((precedent % 7) + 7) % 7 + 7) % 7;
    if (ecart > 3) ecart -= 7;
    final int position = precedent + ecart + 7 * hauts - 7 * bas;
    precedent = position;
    return position;
  }

  /// Accord `<c e g>4` : toutes les notes partagent position et durée. En
  /// mode relatif, la première note s'accroche à la précédente, les
  /// suivantes s'enchaînent dans l'accord, et la note de référence pour la
  /// suite est la première de l'accord (règle LilyPond).
  int _accord(
    String corps,
    int i,
    int n,
    double Function() position,
    void Function(double) avancer,
    double Function(String?, String?, String?) dureeAtome,
    int Function() prendreTransposition,
  ) {
    i++; // '<'
    final List<({int position, int alteration})> hauteurs = [];
    int? premiere;

    while (i < n && corps[i] != '>') {
      if (corps[i] == '"') {
        i++;
        while (i < n && corps[i] != '"') {
          if (corps[i] == '\\') i++;
          i++;
        }
        i++;
        continue;
      }
      if (corps[i] == '\\') {
        // \harmonic et autres modificateurs internes à l'accord.
        final Match? mot = LilypondParser._regexMot.matchAsPrefix(corps, i + 1);
        i = mot?.end ?? i + 2;
        continue;
      }
      final Match? h = langue.accordNote.matchAsPrefix(corps, i);
      if (h != null) {
        final nomNote = langue.noms[h.group(1)!]!;
        final String octaves = h.group(2) ?? '';
        final int hauts = "'".allMatches(octaves).length;
        final int bas = ','.allMatches(octaves).length;
        final int p = _position(nomNote.degre, hauts, bas);
        premiere ??= p;
        hauteurs.add((position: p, alteration: nomNote.alteration));
        i = h.end;
        continue;
      }
      i++; // doigtés, articulations, tenues...
    }
    i++; // '>'

    // Durée éventuelle après l'accord.
    final Match d = LilypondParser._regexDureeSeule.matchAsPrefix(corps, i)!;
    i = d.end;

    if (hauteursAIgnorer > 0) {
      // Accord d'ornement (\grace <...>) : consommé sans être joué.
      hauteursAIgnorer--;
      return i;
    }

    if (relatif && premiere != null) precedent = premiere;
    if (hauteurs.isEmpty) return i; // <> vide : rien à jouer

    final double duree = dureeAtome(d.group(1), d.group(2), d.group(3));
    final double debut = position();
    final int t = prendreTransposition(); // \transpose d'un seul accord
    for (final p in hauteurs) {
      notes.add(Note(
        hauteur: _midi(p.position, p.alteration) + t,
        duree: duree,
        position: debut,
      ));
    }
    dernierAccord = hauteurs;
    avancer(duree);
    return i;
  }
}
