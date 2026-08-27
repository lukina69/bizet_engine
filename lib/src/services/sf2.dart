import 'dart:typed_data';

/// Le format SoundFont 2, tel que le moteur le lit et l'écrit : le lecteur
/// qui garde les générateurs tels quels, l'écrivain RIFF, et les deux
/// écritures communes à toute banque produite ici (la liste INFO, les zones).
///
/// Interne au paquet — rien d'ici n'est exporté. [BanqueReduite] s'en sert
/// pour tailler une banque, [BanqueAssemblee] pour en recoller plusieurs.

/// La liste INFO d'une banque produite ici : version, moteur, nom.
void ecrireInfo(EcrivainSf2 f, String nom) {
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

/// Les zones d'un niveau — presets ou instruments — et leurs générateurs,
/// sans modulateurs.
void ecrireZones(
  EcrivainSf2 f,
  String bag,
  String mod,
  String gen,
  List<List<Generateur>> zones,
) {
  f.fourCC(bag);
  f.entier32((zones.length + 1) * 4);
  int generateurs = 0;
  for (final List<Generateur> zone in zones) {
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
  for (final List<Generateur> zone in zones) {
    for (final Generateur g in zone) {
      f.entier16(g.type);
      f.entier16(g.valeur);
    }
  }
  f.entier16(0);
  f.entier16(0);
}

/// La norme réclame de la place perdue entre deux échantillons, pour que
/// l'interpolation du synthétiseur ne morde pas sur le voisin.
const int silenceEntreEchantillons = 46;

/// « RIFF », sa taille, « sfbk ».
const int enteteFichier = 12;

/// Le nom d'un chunk et sa taille.
const int enteteChunk = 8;

/// Idem, plus le genre de la liste — « sdta », « pdta ».
const int enteteListe = 12;

/// La liste INFO telle qu'on l'écrit : version, moteur, nom.
const int tailleInfo =
    enteteListe + (enteteChunk + 4) + (enteteChunk + 8) + (enteteChunk + 32);

/// Un sous-chunk de modulateurs réduit à son enregistrement terminal.
const int modulateurVide = enteteChunk + 10;

/// Numéros des générateurs SoundFont dont on a besoin.
const int generateurAmbitus = 43;
const int generateurInstrument = 41;
const int generateurEchantillon = 53;

bool estDecalageAdresse(int type) => type <= 3;

class Generateur {
  final int type;
  final int valeur;

  const Generateur(this.type, this.valeur);
}

class PresetInfo {
  final String nom;
  final int programme;
  final int banque;
  final int premiereZone;
  final int derniereZone;
  final int bibliotheque;
  final int genre;
  final int morphologie;

  const PresetInfo({
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

class InstrumentInfo {
  final String nom;
  final int premiereZone;
  final int derniereZone;

  const InstrumentInfo(this.nom, this.premiereZone, this.derniereZone);
}

class EchantillonInfo {
  final String nom;
  final int debut;
  final int fin;
  final int debutBoucle;
  final int finBoucle;
  final int frequence;
  final int hauteurOrigine;
  final int correction;

  const EchantillonInfo({
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
class Sf2 {
  Sf2._({
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

  final List<PresetInfo> presets;
  final List<InstrumentInfo> instruments;
  final List<EchantillonInfo> echantillons;

  /// Pour chaque zone, l'indice de son premier générateur. La liste porte
  /// une entrée de plus que de zones, qui dit où s'arrête la dernière.
  final List<int> _zonesPreset;
  final List<int> _zonesInstrument;

  final List<Generateur> _generateursPreset;
  final List<Generateur> _generateursInstrument;

  List<Generateur> generateursDeZonePreset(int zone) =>
      _generateursPreset.sublist(_zonesPreset[zone], _zonesPreset[zone + 1]);

  List<Generateur> generateursDeZoneInstrument(int zone) =>
      _generateursInstrument.sublist(
        _zonesInstrument[zone],
        _zonesInstrument[zone + 1],
      );

  /// L'instrument que désigne une zone de preset, ou nul s'il s'agit de la
  /// zone globale — c'est ainsi qu'on les distingue : le générateur
  /// « instrument » doit être le dernier d'une vraie zone.
  int? instrumentDeZonePreset(int zone) {
    final List<Generateur> g = generateursDeZonePreset(zone);
    if (g.isEmpty || g.last.type != generateurInstrument) return null;
    return g.last.valeur;
  }

  /// De même pour l'échantillon d'une zone d'instrument.
  int? echantillonDeZoneInstrument(int zone) {
    final List<Generateur> g = generateursDeZoneInstrument(zone);
    if (g.isEmpty || g.last.type != generateurEchantillon) return null;
    return g.last.valeur;
  }

  (int, int)? ambitusDeZoneInstrument(int zone) {
    for (final Generateur g in generateursDeZoneInstrument(zone)) {
      if (g.type == generateurAmbitus) {
        return (g.valeur & 0xFF, (g.valeur >> 8) & 0xFF);
      }
    }
    return null;
  }

  static Sf2 lire(ByteData donnees) {
    final LecteurSf2 l = LecteurSf2(donnees);

    if (l.fourCC() != 'RIFF') throw const FormatException('Pas un RIFF.');
    l.entier32();
    if (l.fourCC() != 'sfbk') {
      throw const FormatException('Pas un SoundFont.');
    }

    int? debutPoints;
    List<PresetInfo>? presets;
    List<InstrumentInfo>? instruments;
    List<EchantillonInfo>? echantillons;
    List<int>? zonesPreset;
    List<int>? zonesInstrument;
    List<Generateur>? generateursPreset;
    List<Generateur>? generateursInstrument;

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

    return Sf2._(
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

  static List<PresetInfo> _lirePresets(LecteurSf2 l, int taille) {
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
        PresetInfo(
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

  static List<InstrumentInfo> _lireInstruments(LecteurSf2 l, int taille) {
    final int n = taille ~/ 22;
    final List<String> noms = [];
    final List<int> zones = [];

    for (int i = 0; i < n; i++) {
      noms.add(l.texte(20));
      zones.add(l.entier16());
    }

    return [
      for (int i = 0; i < n - 1; i++)
        InstrumentInfo(noms[i], zones[i], zones[i + 1]),
    ];
  }

  /// Les bornes de générateurs de chaque zone : une entrée de plus que de
  /// zones, la dernière disant où s'arrête la précédente.
  static List<int> _lireZones(LecteurSf2 l, int taille) {
    final int n = taille ~/ 4;
    final List<int> debuts = [];
    for (int i = 0; i < n; i++) {
      debuts.add(l.entier16());
      l.entier16();
    }
    return debuts;
  }

  static List<Generateur> _lireGenerateurs(LecteurSf2 l, int taille) {
    final int n = taille ~/ 4;
    return [for (int i = 0; i < n; i++) Generateur(l.entier16(), l.entier16())];
  }

  static List<EchantillonInfo> _lireEchantillons(LecteurSf2 l, int taille) {
    final int n = taille ~/ 46;
    final List<EchantillonInfo> liste = [];

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

      liste.add(
        EchantillonInfo(
          nom: nom,
          debut: debut,
          fin: fin,
          debutBoucle: debutBoucle,
          finBoucle: finBoucle,
          frequence: frequence,
          hauteurOrigine: hauteur,
          correction: correction,
        ),
      );
    }

    // Le dernier n'est qu'un jalon de fin.
    return liste.sublist(0, n - 1);
  }
}

/// Lecture d'octets en petit-boutiste, l'ordre du format RIFF.
class LecteurSf2 {
  LecteurSf2(this._donnees);

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
class EcrivainSf2 {
  EcrivainSf2(int taille) : _octets = Uint8List(taille), _vue = ByteData(0) {
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
