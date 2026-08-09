import 'dart:typed_data';

/// Fabrique une banque de sons réduite à ce qu'une recette réclame vraiment.
///
/// Trois leviers, du plus payant au moins payant, mesurés sur `Bizet_v4.sf2`
/// (29,6 Mo, 20 sonorités) :
///
/// 1. **Ne garder que les sonorités citées.** De loin le plus fort : trois
///    instruments sur vingt font tomber la banque à 3,8 Mo. Quatre sonorités
///    (cordes, chœur, orgue, pizzicato) pèsent à elles seules plus de la
///    moitié du fichier.
/// 2. **Ramener les échantillons à 22 050 Hz.** Encore un facteur deux. Les
///    échantillons arrivent dans un état hétéroclite — 44 100, 32 000, et
///    déjà 22 050 pour certains.
/// 3. **Ne garder que l'ambitus joué.** Le moins payant en pratique : dès que
///    le morceau couvre trois octaves, que l'épaisseur double à l'octave et
///    que la transposition élargit encore, il ne reste presque rien à jeter.
///
/// **Une seule fonction pour chiffrer et pour fabriquer**, comme l'exige le
/// § 6 bis du document de conception : [octets] annonce le poids dans
/// l'atelier, [ecrire] produit les octets livrés. Deux implémentations
/// dériveraient et le chiffre affiché deviendrait un mensonge — le pire
/// résultat possible pour un outil censé aider à arbitrer.
///
/// La sélection est faite dès la construction et ne coûte presque rien : la
/// partie « intelligence » d'un SoundFont pèse une vingtaine de kilo-octets.
/// Seul [ecrire] fait le gros travail, en rééchantillonnant.
class BanqueReduite {
  /// Prépare la réduction d'une banque, sans encore rien fabriquer.
  ///
  /// [programmes] sont les numéros General MIDI à conserver ; [noteMin] et
  /// [noteMax] l'ambitus réellement joué, transposition et doublages
  /// compris ; [frequence] la fréquence d'échantillonnage maximale voulue.
  ///
  /// Lève [FormatException] si les octets ne sont pas un SoundFont lisible.
  factory BanqueReduite.pour(
    ByteData sf2, {
    required Set<int> programmes,
    int noteMin = 0,
    int noteMax = 127,
    int frequence = frequenceParDefaut,
  }) {
    final _Sf2 source = _Sf2.lire(sf2);
    return BanqueReduite._(source, programmes, noteMin, noteMax, frequence);
  }

  /// La qualité retenue par défaut : la moitié de la qualité CD. Au-delà, on
  /// paie du brillant que la musique de fond d'un jeu n'exploite pas.
  static const int frequenceParDefaut = 22050;

  BanqueReduite._(
    this._source,
    this.programmes,
    this.noteMin,
    this.noteMax,
    this.frequence,
  ) {
    _choisir();
  }

  final _Sf2 _source;

  final Set<int> programmes;
  final int noteMin;
  final int noteMax;
  final int frequence;

  /// Les presets retenus, dans l'ordre du fichier d'origine.
  final List<int> _presets = [];

  /// Les instruments retenus, et pour chacun les zones gardées.
  final List<int> _instruments = [];
  final Map<int, List<int>> _zonesInstrument = {};

  /// Les zones de preset gardées, par preset.
  final Map<int, List<int>> _zonesPreset = {};

  /// Les échantillons retenus, dans l'ordre, et leur longueur une fois
  /// rééchantillonnés.
  final List<int> _echantillons = [];
  final Map<int, int> _longueurReduite = {};

  /// Les sonorités réclamées que la banque ne possède pas. Un jeu qui en
  /// demanderait une entendrait le synthétiseur lui substituer autre chose
  /// en silence : mieux vaut le savoir dans l'atelier.
  late final List<int> manquants = (programmes
        ..toList())
      .where((p) => !_source.presets
          .any((info) => info.banque == 0 && info.programme == p))
      .toList()
    ..sort();

  void _choisir() {
    for (int p = 0; p < _source.presets.length; p++) {
      final _PresetInfo info = _source.presets[p];
      if (info.banque != 0 || !programmes.contains(info.programme)) continue;

      final List<int> zones = [];
      for (int z = info.premiereZone; z < info.derniereZone; z++) {
        final int? instrument = _source.instrumentDeZonePreset(z);
        if (instrument == null) {
          // Zone globale du preset : elle règle les suivantes, on la garde.
          zones.add(z);
          continue;
        }
        if (_garderInstrument(instrument)) zones.add(z);
      }

      if (zones.isEmpty) continue;
      _presets.add(p);
      _zonesPreset[p] = zones;
    }

    // Les échantillons prennent l'ordre des instruments qui les emploient :
    // le fichier produit se lit alors dans le même ordre qu'il s'écrit.
    for (final int i in _instruments) {
      for (final int z in _zonesInstrument[i]!) {
        final int? echantillon = _source.echantillonDeZoneInstrument(z);
        if (echantillon == null) continue;
        if (_echantillons.contains(echantillon)) continue;
        _echantillons.add(echantillon);
        _longueurReduite[echantillon] = _longueurApres(echantillon);
      }
    }
  }

  /// Garde un instrument et les seules zones dont l'ambitus croise celui du
  /// morceau. Renvoie faux s'il ne reste rien à jouer.
  bool _garderInstrument(int instrument) {
    if (_zonesInstrument.containsKey(instrument)) {
      return _zonesInstrument[instrument]!.isNotEmpty;
    }

    final _InstrumentInfo info = _source.instruments[instrument];
    final List<int> zones = [];
    bool sonne = false;

    for (int z = info.premiereZone; z < info.derniereZone; z++) {
      if (_source.echantillonDeZoneInstrument(z) == null) {
        // Zone globale de l'instrument.
        zones.add(z);
        continue;
      }
      final (int bas, int haut)? ambitus = _source.ambitusDeZoneInstrument(z);
      // Sans ambitus déclaré, la zone vaut pour tout le clavier.
      if (ambitus != null && (ambitus.$2 < noteMin || ambitus.$1 > noteMax)) {
        continue;
      }
      zones.add(z);
      sonne = true;
    }

    _zonesInstrument[instrument] = sonne ? zones : const [];
    if (sonne) _instruments.add(instrument);
    return sonne;
  }

  int _longueurApres(int echantillon) {
    final _EchantillonInfo e = _source.echantillons[echantillon];
    final int longueur = e.fin - e.debut;
    if (e.frequence <= frequence) return longueur;
    return (longueur * frequence / e.frequence).round();
  }

  /// Le poids du fichier qui sera produit, en octets. C'est le chiffre à
  /// afficher : il sort du même choix que les octets eux-mêmes.
  int get octets {
    // Les données sonores, chacune suivie des 46 points de silence que la
    // norme réclame entre deux échantillons.
    int sons = 0;
    for (final int e in _echantillons) {
      sons += (_longueurReduite[e]! + _silenceEntreEchantillons) * 2;
    }

    int zonesPreset = 0;
    int generateursPreset = 0;
    for (final int p in _presets) {
      zonesPreset += _zonesPreset[p]!.length;
      for (final int z in _zonesPreset[p]!) {
        generateursPreset += _source.generateursDeZonePreset(z).length;
      }
    }

    int zonesInstrument = 0;
    int generateursInstrument = 0;
    for (final int i in _instruments) {
      zonesInstrument += _zonesInstrument[i]!.length;
      for (final int z in _zonesInstrument[i]!) {
        generateursInstrument += _source.generateursDeZoneInstrument(z).length;
      }
    }

    // L'en-tête RIFF, les trois listes, et les neuf sous-chunks de la
    // dernière — chacun avec son en-tête de huit octets et son
    // enregistrement terminal, celui qui dit où s'arrête le précédent.
    return _enteteFichier +
        _tailleInfo +
        _enteteListe +
        _enteteChunk +
        sons +
        _enteteListe +
        _enteteChunk +
        (_presets.length + 1) * 38 +
        _enteteChunk +
        (zonesPreset + 1) * 4 +
        _modulateurVide +
        _enteteChunk +
        (generateursPreset + 1) * 4 +
        _enteteChunk +
        (_instruments.length + 1) * 22 +
        _enteteChunk +
        (zonesInstrument + 1) * 4 +
        _modulateurVide +
        _enteteChunk +
        (generateursInstrument + 1) * 4 +
        _enteteChunk +
        (_echantillons.length + 1) * 46;
  }

  /// Le détail par sonorité : de quoi dire, au moment du choix, ce que
  /// chacune coûte. C'est là que se joue l'arbitrage — un « Strings Fast »
  /// pèse soixante-dix fois une « Music Box ».
  List<({int programme, String nom, int echantillons, int octets})>
      get detail {
    final List<({int programme, String nom, int echantillons, int octets})>
        lignes = [];

    for (final int p in _presets) {
      final Set<int> vus = {};
      int poids = 0;
      for (final int z in _zonesPreset[p]!) {
        final int? instrument = _source.instrumentDeZonePreset(z);
        if (instrument == null) continue;
        for (final int zi in _zonesInstrument[instrument] ?? const <int>[]) {
          final int? e = _source.echantillonDeZoneInstrument(zi);
          if (e == null || !vus.add(e)) continue;
          poids += (_longueurReduite[e]! + _silenceEntreEchantillons) * 2;
        }
      }
      lignes.add((
        programme: _source.presets[p].programme,
        nom: _source.presets[p].nom,
        echantillons: vus.length,
        octets: poids,
      ));
    }

    lignes.sort((a, b) => b.octets.compareTo(a.octets));
    return lignes;
  }

  /// Fabrique la banque réduite. C'est ici que le rééchantillonnage a lieu,
  /// et c'est le seul moment coûteux.
  Uint8List ecrire({String nom = 'Bizet Scene'}) {
    final _Ecrivain f = _Ecrivain(octets);

    f.fourCC('RIFF');
    final int tailleFichier = f.reserverTaille();
    f.fourCC('sfbk');

    _ecrireInfo(f, nom);
    _ecrireSons(f);
    _ecrireParametres(f);

    f.poserTaille(tailleFichier);
    return f.octets();
  }

  void _ecrireInfo(_Ecrivain f, String nom) {
    f.fourCC('LIST');
    final int taille = f.reserverTaille();
    f.fourCC('INFO');

    f.fourCC('ifil');
    f.entier32(4);
    f.entier16(2);
    f.entier16(1);

    f.fourCC('isng');
    f.entier32(8);
    f.texte('EMU8000', 8);

    f.fourCC('INAM');
    f.entier32(32);
    f.texte(nom, 32);

    f.poserTaille(taille);
  }

  void _ecrireSons(_Ecrivain f) {
    f.fourCC('LIST');
    final int taille = f.reserverTaille();
    f.fourCC('sdta');

    f.fourCC('smpl');
    int total = 0;
    for (final int e in _echantillons) {
      total += (_longueurReduite[e]! + _silenceEntreEchantillons) * 2;
    }
    f.entier32(total);

    for (final int e in _echantillons) {
      f.points(_reechantillonner(e));
      f.silence(_silenceEntreEchantillons);
    }

    f.poserTaille(taille);
  }

  /// Un échantillon ramené à la fréquence voulue, par interpolation
  /// linéaire. Rien de savant : à ces rapports-là, l'oreille ne distingue
  /// pas une interpolation soignée d'une interpolation droite.
  Int16List _reechantillonner(int echantillon) {
    final _EchantillonInfo e = _source.echantillons[echantillon];
    final int longueur = e.fin - e.debut;
    final int voulue = _longueurReduite[echantillon]!;

    if (voulue == longueur) {
      return Int16List.fromList([
        for (int i = e.debut; i < e.fin; i++) _source.point(i),
      ]);
    }

    final Int16List sortie = Int16List(voulue);
    final double pas = longueur / voulue;
    for (int i = 0; i < voulue; i++) {
      final double place = i * pas;
      final int gauche = place.floor();
      final double reste = place - gauche;
      final int a = _source.point(e.debut + gauche);
      final int b = e.debut + gauche + 1 < e.fin
          ? _source.point(e.debut + gauche + 1)
          : a;
      sortie[i] = (a + (b - a) * reste).round().clamp(-32768, 32767);
    }
    return sortie;
  }

  void _ecrireParametres(_Ecrivain f) {
    f.fourCC('LIST');
    final int taille = f.reserverTaille();
    f.fourCC('pdta');

    // Les nouveaux numéros : tout ce qui référençait l'ancien fichier doit
    // désigner le nouveau.
    final Map<int, int> instrumentVers = {
      for (int i = 0; i < _instruments.length; i++) _instruments[i]: i,
    };
    final Map<int, int> echantillonVers = {
      for (int i = 0; i < _echantillons.length; i++) _echantillons[i]: i,
    };

    // ---- phdr et ses zones
    final List<List<_Generateur>> zonesPreset = [];
    f.fourCC('phdr');
    f.entier32((_presets.length + 1) * 38);
    for (final int p in _presets) {
      final _PresetInfo info = _source.presets[p];
      f.texte(info.nom, 20);
      f.entier16(info.programme);
      f.entier16(info.banque);
      f.entier16(zonesPreset.length);
      f.entier32(info.bibliotheque);
      f.entier32(info.genre);
      f.entier32(info.morphologie);

      for (final int z in _zonesPreset[p]!) {
        zonesPreset.add([
          for (final _Generateur g in _source.generateursDeZonePreset(z))
            g.type == _generateurInstrument
                ? _Generateur(g.type, instrumentVers[g.valeur]!)
                : g,
        ]);
      }
    }
    // L'enregistrement terminal, qui dit où s'arrête le dernier preset.
    f.texte('EOP', 20);
    f.entier16(0);
    f.entier16(0);
    f.entier16(zonesPreset.length);
    f.entier32(0);
    f.entier32(0);
    f.entier32(0);

    _ecrireZones(f, 'pbag', 'pmod', 'pgen', zonesPreset);

    // ---- inst et ses zones
    final List<List<_Generateur>> zonesInstrument = [];
    f.fourCC('inst');
    f.entier32((_instruments.length + 1) * 22);
    for (final int i in _instruments) {
      f.texte(_source.instruments[i].nom, 20);
      f.entier16(zonesInstrument.length);

      for (final int z in _zonesInstrument[i]!) {
        zonesInstrument.add([
          for (final _Generateur g in _source.generateursDeZoneInstrument(z))
            switch (g.type) {
              _generateurEchantillon =>
                _Generateur(g.type, echantillonVers[g.valeur]!),
              // Les décalages d'adresse comptent en points : ils suivent le
              // rééchantillonnage, sans quoi la note démarrerait ailleurs.
              _ when _estDecalageAdresse(g.type) =>
                _Generateur(g.type, _decalageReduit(z, g)),
              _ => g,
            },
        ]);
      }
    }
    f.texte('EOI', 20);
    f.entier16(zonesInstrument.length);

    _ecrireZones(f, 'ibag', 'imod', 'igen', zonesInstrument);

    // ---- shdr
    f.fourCC('shdr');
    f.entier32((_echantillons.length + 1) * 46);
    int position = 0;
    for (final int e in _echantillons) {
      final _EchantillonInfo info = _source.echantillons[e];
      final int longueur = _longueurReduite[e]!;
      final double rapport = longueur / (info.fin - info.debut);
      final int frequenceFinale =
          info.frequence <= frequence ? info.frequence : frequence;

      f.texte(info.nom, 20);
      f.entier32(position);
      f.entier32(position + longueur);
      f.entier32(position + ((info.debutBoucle - info.debut) * rapport).round());
      f.entier32(position + ((info.finBoucle - info.debut) * rapport).round());
      f.entier32(frequenceFinale);
      f.octet(info.hauteurOrigine);
      f.octet(info.correction & 0xFF);
      // Tout est mono : aucun échantillon n'a de jumeau à désigner.
      f.entier16(0);
      f.entier16(1);

      position += longueur + _silenceEntreEchantillons;
    }
    f.texte('EOS', 20);
    for (int i = 0; i < 5; i++) {
      f.entier32(0);
    }
    f.octet(0);
    f.octet(0);
    f.entier16(0);
    f.entier16(0);

    f.poserTaille(taille);
  }

  /// Un décalage d'adresse ramené au nouvel échantillonnage.
  int _decalageReduit(int zone, _Generateur g) {
    final int? e = _source.echantillonDeZoneInstrument(zone);
    if (e == null) return g.valeur;
    final _EchantillonInfo info = _source.echantillons[e];
    if (info.frequence <= frequence) return g.valeur;

    // La valeur est un entier signé sur 16 bits.
    final int signe = g.valeur >= 0x8000 ? g.valeur - 0x10000 : g.valeur;
    final int reduit = (signe * frequence / info.frequence).round();
    return reduit < 0 ? reduit + 0x10000 : reduit;
  }

  void _ecrireZones(
    _Ecrivain f,
    String bag,
    String mod,
    String gen,
    List<List<_Generateur>> zones,
  ) {
    f.fourCC(bag);
    f.entier32((zones.length + 1) * 4);
    int generateurs = 0;
    for (final List<_Generateur> zone in zones) {
      f.entier16(generateurs);
      f.entier16(0);
      generateurs += zone.length;
    }
    f.entier16(generateurs);
    f.entier16(0);

    // Aucun modulateur : ils ne pèsent rien mais ne servent à rien ici, et
    // le synthétiseur les ignore déjà.
    f.fourCC(mod);
    f.entier32(10);
    f.entier16(0);
    f.entier16(0);
    f.entier16(0);
    f.entier16(0);
    f.entier16(0);

    f.fourCC(gen);
    f.entier32((generateurs + 1) * 4);
    for (final List<_Generateur> zone in zones) {
      for (final _Generateur g in zone) {
        f.entier16(g.type);
        f.entier16(g.valeur);
      }
    }
    f.entier16(0);
    f.entier16(0);
  }
}

/// La norme réclame de la place perdue entre deux échantillons, pour que
/// l'interpolation du synthétiseur ne morde pas sur le voisin.
const int _silenceEntreEchantillons = 46;

/// « RIFF », sa taille, « sfbk ».
const int _enteteFichier = 12;

/// Le nom d'un chunk et sa taille.
const int _enteteChunk = 8;

/// Idem, plus le genre de la liste — « sdta », « pdta ».
const int _enteteListe = 12;

/// La liste INFO telle qu'on l'écrit : version, moteur, nom.
const int _tailleInfo =
    _enteteListe + (_enteteChunk + 4) + (_enteteChunk + 8) + (_enteteChunk + 32);

/// Un sous-chunk de modulateurs réduit à son enregistrement terminal.
const int _modulateurVide = _enteteChunk + 10;

/// Numéros des générateurs SoundFont dont on a besoin.
const int _generateurAmbitus = 43;
const int _generateurInstrument = 41;
const int _generateurEchantillon = 53;

bool _estDecalageAdresse(int type) => type <= 3;

class _Generateur {
  final int type;
  final int valeur;

  const _Generateur(this.type, this.valeur);
}

class _PresetInfo {
  final String nom;
  final int programme;
  final int banque;
  final int premiereZone;
  final int derniereZone;
  final int bibliotheque;
  final int genre;
  final int morphologie;

  const _PresetInfo({
    required this.nom,
    required this.programme,
    required this.banque,
    required this.premiereZone,
    required this.derniereZone,
    required this.bibliotheque,
    required this.genre,
    required this.morphologie,
  });
}

class _InstrumentInfo {
  final String nom;
  final int premiereZone;
  final int derniereZone;

  const _InstrumentInfo(this.nom, this.premiereZone, this.derniereZone);
}

class _EchantillonInfo {
  final String nom;
  final int debut;
  final int fin;
  final int debutBoucle;
  final int finBoucle;
  final int frequence;
  final int hauteurOrigine;
  final int correction;

  const _EchantillonInfo({
    required this.nom,
    required this.debut,
    required this.fin,
    required this.debutBoucle,
    required this.finBoucle,
    required this.frequence,
    required this.hauteurOrigine,
    required this.correction,
  });
}

/// Un lecteur de SoundFont qui garde les générateurs **tels qu'ils sont
/// écrits**.
///
/// `dart_melty_soundfont` en a bien un, mais il fond aussitôt les zones
/// globales dans les zones locales et complète les valeurs manquantes par
/// leurs défauts : de quoi jouer, pas de quoi réécrire. Or réécrire un
/// fichier à partir de valeurs complétées le ferait sonner autrement — les
/// générateurs d'un preset s'**ajoutent** à ceux de l'instrument.
class _Sf2 {
  _Sf2._({
    required this._donnees,
    required this._debutPoints,
    required this.presets,
    required this.instruments,
    required this.echantillons,
    required this._zonesPreset,
    required this._zonesInstrument,
    required this._generateursPreset,
    required this._generateursInstrument,
  });

  /// Le fichier d'origine, gardé tel quel : les points sonores ne sont lus
  /// qu'au moment d'écrire. Les recopier dès la lecture coûterait, sur une
  /// banque de 30 Mo, quinze millions de valeurs à chaque fois qu'on veut
  /// simplement afficher un poids.
  final ByteData _donnees;
  final int _debutPoints;

  /// Un point sonore du fichier, 16 bits signés.
  int point(int index) =>
      _donnees.getInt16(_debutPoints + index * 2, Endian.little);

  final List<_PresetInfo> presets;
  final List<_InstrumentInfo> instruments;
  final List<_EchantillonInfo> echantillons;

  /// Pour chaque zone, l'indice de son premier générateur. La liste porte
  /// une entrée de plus que de zones, qui dit où s'arrête la dernière.
  final List<int> _zonesPreset;
  final List<int> _zonesInstrument;

  final List<_Generateur> _generateursPreset;
  final List<_Generateur> _generateursInstrument;

  List<_Generateur> generateursDeZonePreset(int zone) => _generateursPreset
      .sublist(_zonesPreset[zone], _zonesPreset[zone + 1]);

  List<_Generateur> generateursDeZoneInstrument(int zone) =>
      _generateursInstrument.sublist(
          _zonesInstrument[zone], _zonesInstrument[zone + 1]);

  /// L'instrument que désigne une zone de preset, ou nul s'il s'agit de la
  /// zone globale — c'est ainsi qu'on les distingue : le générateur
  /// « instrument » doit être le dernier d'une vraie zone.
  int? instrumentDeZonePreset(int zone) {
    final List<_Generateur> g = generateursDeZonePreset(zone);
    if (g.isEmpty || g.last.type != _generateurInstrument) return null;
    return g.last.valeur;
  }

  /// De même pour l'échantillon d'une zone d'instrument.
  int? echantillonDeZoneInstrument(int zone) {
    final List<_Generateur> g = generateursDeZoneInstrument(zone);
    if (g.isEmpty || g.last.type != _generateurEchantillon) return null;
    return g.last.valeur;
  }

  (int, int)? ambitusDeZoneInstrument(int zone) {
    for (final _Generateur g in generateursDeZoneInstrument(zone)) {
      if (g.type == _generateurAmbitus) {
        return (g.valeur & 0xFF, (g.valeur >> 8) & 0xFF);
      }
    }
    return null;
  }

  static _Sf2 lire(ByteData donnees) {
    final _Lecteur l = _Lecteur(donnees);

    if (l.fourCC() != 'RIFF') throw const FormatException('Pas un RIFF.');
    l.entier32();
    if (l.fourCC() != 'sfbk') {
      throw const FormatException('Pas un SoundFont.');
    }

    int? debutPoints;
    List<_PresetInfo>? presets;
    List<_InstrumentInfo>? instruments;
    List<_EchantillonInfo>? echantillons;
    List<int>? zonesPreset;
    List<int>? zonesInstrument;
    List<_Generateur>? generateursPreset;
    List<_Generateur>? generateursInstrument;

    while (!l.fini) {
      if (l.fourCC() != 'LIST') break;
      final int taille = l.entier32();
      final int fin = l.position + taille;
      final String genre = l.fourCC();

      while (l.position < fin) {
        final String id = l.fourCC();
        final int n = l.entier32();
        final int apres = l.position + n;

        switch (id) {
          case 'smpl':
            debutPoints = l.position;
          case 'phdr':
            presets = _lirePresets(l, n);
          case 'pbag':
            zonesPreset = _lireZones(l, n);
          case 'pgen':
            generateursPreset = _lireGenerateurs(l, n);
          case 'inst':
            instruments = _lireInstruments(l, n);
          case 'ibag':
            zonesInstrument = _lireZones(l, n);
          case 'igen':
            generateursInstrument = _lireGenerateurs(l, n);
          case 'shdr':
            echantillons = _lireEchantillons(l, n);
        }

        // Les chunks qu'on ne lit pas — modulateurs, informations, données
        // 24 bits — sont simplement enjambés.
        l.aller(apres + (apres.isOdd ? 1 : 0));
      }

      if (genre.isEmpty) break;
    }

    if (debutPoints == null ||
        presets == null ||
        instruments == null ||
        echantillons == null ||
        zonesPreset == null ||
        zonesInstrument == null ||
        generateursPreset == null ||
        generateursInstrument == null) {
      throw const FormatException('SoundFont incomplet.');
    }

    return _Sf2._(
      donnees: donnees,
      debutPoints: debutPoints,
      presets: presets,
      instruments: instruments,
      echantillons: echantillons,
      zonesPreset: zonesPreset,
      zonesInstrument: zonesInstrument,
      generateursPreset: generateursPreset,
      generateursInstrument: generateursInstrument,
    );
  }

  static List<_PresetInfo> _lirePresets(_Lecteur l, int taille) {
    final int n = taille ~/ 38;
    final List<String> noms = [];
    final List<int> programmes = [];
    final List<int> banques = [];
    final List<int> zones = [];
    final List<int> bibliotheques = [];
    final List<int> genres = [];
    final List<int> morphologies = [];

    for (int i = 0; i < n; i++) {
      noms.add(l.texte(20));
      programmes.add(l.entier16());
      banques.add(l.entier16());
      zones.add(l.entier16());
      bibliotheques.add(l.entier32());
      genres.add(l.entier32());
      morphologies.add(l.entier32());
    }

    // Le dernier enregistrement n'est qu'un jalon de fin.
    return [
      for (int i = 0; i < n - 1; i++)
        _PresetInfo(
          nom: noms[i],
          programme: programmes[i],
          banque: banques[i],
          premiereZone: zones[i],
          derniereZone: zones[i + 1],
          bibliotheque: bibliotheques[i],
          genre: genres[i],
          morphologie: morphologies[i],
        ),
    ];
  }

  static List<_InstrumentInfo> _lireInstruments(_Lecteur l, int taille) {
    final int n = taille ~/ 22;
    final List<String> noms = [];
    final List<int> zones = [];

    for (int i = 0; i < n; i++) {
      noms.add(l.texte(20));
      zones.add(l.entier16());
    }

    return [
      for (int i = 0; i < n - 1; i++)
        _InstrumentInfo(noms[i], zones[i], zones[i + 1]),
    ];
  }

  /// Les bornes de générateurs de chaque zone : une entrée de plus que de
  /// zones, la dernière disant où s'arrête la précédente.
  static List<int> _lireZones(_Lecteur l, int taille) {
    final int n = taille ~/ 4;
    final List<int> debuts = [];
    for (int i = 0; i < n; i++) {
      debuts.add(l.entier16());
      l.entier16();
    }
    return debuts;
  }

  static List<_Generateur> _lireGenerateurs(_Lecteur l, int taille) {
    final int n = taille ~/ 4;
    return [
      for (int i = 0; i < n; i++) _Generateur(l.entier16(), l.entier16()),
    ];
  }

  static List<_EchantillonInfo> _lireEchantillons(_Lecteur l, int taille) {
    final int n = taille ~/ 46;
    final List<_EchantillonInfo> liste = [];

    for (int i = 0; i < n; i++) {
      final String nom = l.texte(20);
      final int debut = l.entier32();
      final int fin = l.entier32();
      final int debutBoucle = l.entier32();
      final int finBoucle = l.entier32();
      final int frequence = l.entier32();
      final int hauteur = l.octet();
      final int correction = l.octet();
      l.entier16();
      l.entier16();

      liste.add(_EchantillonInfo(
        nom: nom,
        debut: debut,
        fin: fin,
        debutBoucle: debutBoucle,
        finBoucle: finBoucle,
        frequence: frequence,
        hauteurOrigine: hauteur,
        correction: correction,
      ));
    }

    // Le dernier n'est qu'un jalon de fin.
    return liste.sublist(0, n - 1);
  }
}

/// Lecture d'octets en petit-boutiste, l'ordre du format RIFF.
class _Lecteur {
  _Lecteur(this._donnees);

  final ByteData _donnees;
  int position = 0;

  bool get fini => position >= _donnees.lengthInBytes;

  void aller(int ou) => position = ou;

  int octet() => _donnees.getUint8(position++);

  int entier16() {
    final int v = _donnees.getUint16(position, Endian.little);
    position += 2;
    return v;
  }

  int entier32() {
    final int v = _donnees.getInt32(position, Endian.little);
    position += 4;
    return v;
  }

  String fourCC() {
    final StringBuffer b = StringBuffer();
    for (int i = 0; i < 4; i++) {
      b.writeCharCode(octet());
    }
    return b.toString();
  }

  String texte(int longueur) {
    final StringBuffer b = StringBuffer();
    for (int i = 0; i < longueur; i++) {
      final int c = octet();
      if (c != 0) b.writeCharCode(c);
    }
    return b.toString();
  }

  Int16List points(int combien) {
    final Int16List liste = Int16List(combien);
    for (int i = 0; i < combien; i++) {
      liste[i] = _donnees.getInt16(position + i * 2, Endian.little);
    }
    position += combien * 2;
    return liste;
  }
}

/// Écriture d'octets en petit-boutiste, avec de quoi revenir poser la taille
/// d'un chunk une fois qu'on en connaît la fin.
class _Ecrivain {
  _Ecrivain(int taille)
      : _octets = Uint8List(taille),
        _vue = ByteData(0) {
    _vue = ByteData.view(_octets.buffer);
  }

  final Uint8List _octets;
  ByteData _vue;
  int _position = 0;

  Uint8List octets() => Uint8List.sublistView(_octets, 0, _position);

  void octet(int v) => _octets[_position++] = v & 0xFF;

  void entier16(int v) {
    _vue.setUint16(_position, v & 0xFFFF, Endian.little);
    _position += 2;
  }

  void entier32(int v) {
    _vue.setInt32(_position, v, Endian.little);
    _position += 4;
  }

  void fourCC(String s) {
    for (int i = 0; i < 4; i++) {
      octet(s.codeUnitAt(i));
    }
  }

  void texte(String s, int longueur) {
    for (int i = 0; i < longueur; i++) {
      octet(i < s.length ? s.codeUnitAt(i) : 0);
    }
  }

  void points(Int16List valeurs) {
    for (final int v in valeurs) {
      _vue.setInt16(_position, v, Endian.little);
      _position += 2;
    }
  }

  void silence(int combien) => _position += combien * 2;

  /// Réserve la place d'une taille de chunk et renvoie où elle se trouve.
  int reserverTaille() {
    final int ou = _position;
    _position += 4;
    return ou;
  }

  /// Écrit après coup la taille du chunk ouvert à cet endroit.
  void poserTaille(int ou) =>
      _vue.setInt32(ou, _position - ou - 4, Endian.little);
}
