import 'dart:typed_data';

import 'sf2.dart';

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
    final Sf2 source = Sf2.lire(sf2);
    return BanqueReduite._(source, programmes, noteMin, noteMax, frequence);
  }

  /// La qualité retenue par défaut, **calée à l'oreille** par Ludo le 9 août
  /// 2026 sur le même tirage rendu à cinq qualités.
  ///
  /// Son verdict : aucune différence audible jusqu'à 16 000 Hz sur de bonnes
  /// enceintes de salon, ni sur le téléphone ; à 11 025 Hz seulement, quelques
  /// détails commencent à manquer dans les aigus. 16 000 Hz garde donc une
  /// marge — il coupe à 8 kHz, juste au-dessus de ce qui s'est entendu.
  ///
  /// Ne pas remonter cette valeur « par prudence » sans réécouter : elle vaut
  /// 500 ko sur une recette de trois instruments, et elle a été gagnée par
  /// une écoute, pas par un calcul.
  static const int frequenceParDefaut = 16000;

  BanqueReduite._(
    this._source,
    this.programmes,
    this.noteMin,
    this.noteMax,
    this.frequence,
  ) {
    _choisir();
  }

  final Sf2 _source;

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
  late final List<int> manquants =
      (programmes..toList())
          .where(
            (p) => !_source.presets.any(
              (info) => info.banque == 0 && info.programme == p,
            ),
          )
          .toList()
        ..sort();

  void _choisir() {
    for (int p = 0; p < _source.presets.length; p++) {
      final PresetInfo info = _source.presets[p];
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

    final InstrumentInfo info = _source.instruments[instrument];
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
    final EchantillonInfo e = _source.echantillons[echantillon];
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
      sons += (_longueurReduite[e]! + silenceEntreEchantillons) * 2;
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
    return enteteFichier +
        tailleInfo +
        enteteListe +
        enteteChunk +
        sons +
        enteteListe +
        enteteChunk +
        (_presets.length + 1) * 38 +
        enteteChunk +
        (zonesPreset + 1) * 4 +
        modulateurVide +
        enteteChunk +
        (generateursPreset + 1) * 4 +
        enteteChunk +
        (_instruments.length + 1) * 22 +
        enteteChunk +
        (zonesInstrument + 1) * 4 +
        modulateurVide +
        enteteChunk +
        (generateursInstrument + 1) * 4 +
        enteteChunk +
        (_echantillons.length + 1) * 46;
  }

  /// Le détail par sonorité : de quoi dire, au moment du choix, ce que
  /// chacune coûte. C'est là que se joue l'arbitrage — un « Strings Fast »
  /// pèse soixante-dix fois une « Music Box ».
  List<({int programme, String nom, int echantillons, int octets})> get detail {
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
          poids += (_longueurReduite[e]! + silenceEntreEchantillons) * 2;
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
    final EcrivainSf2 f = EcrivainSf2(octets);

    f.fourCC('RIFF');
    final int tailleFichier = f.reserverTaille();
    f.fourCC('sfbk');

    ecrireInfo(f, nom);
    _ecrireSons(f);
    _ecrireParametres(f);

    f.poserTaille(tailleFichier);
    return f.octets();
  }

  void _ecrireSons(EcrivainSf2 f) {
    f.fourCC('LIST');
    final int taille = f.reserverTaille();
    f.fourCC('sdta');

    f.fourCC('smpl');
    int total = 0;
    for (final int e in _echantillons) {
      total += (_longueurReduite[e]! + silenceEntreEchantillons) * 2;
    }
    f.entier32(total);

    for (final int e in _echantillons) {
      f.points(_reechantillonner(e));
      f.silence(silenceEntreEchantillons);
    }

    f.poserTaille(taille);
  }

  /// Un échantillon ramené à la fréquence voulue, par interpolation
  /// linéaire. Rien de savant : à ces rapports-là, l'oreille ne distingue
  /// pas une interpolation soignée d'une interpolation droite.
  Int16List _reechantillonner(int echantillon) {
    final EchantillonInfo e = _source.echantillons[echantillon];
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

  void _ecrireParametres(EcrivainSf2 f) {
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
    final List<List<Generateur>> zonesPreset = [];
    f.fourCC('phdr');
    f.entier32((_presets.length + 1) * 38);
    for (final int p in _presets) {
      final PresetInfo info = _source.presets[p];
      f.texte(info.nom, 20);
      f.entier16(info.programme);
      f.entier16(info.banque);
      f.entier16(zonesPreset.length);
      f.entier32(info.bibliotheque);
      f.entier32(info.genre);
      f.entier32(info.morphologie);

      for (final int z in _zonesPreset[p]!) {
        zonesPreset.add([
          for (final Generateur g in _source.generateursDeZonePreset(z))
            g.type == generateurInstrument
                ? Generateur(g.type, instrumentVers[g.valeur]!)
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

    ecrireZones(f, 'pbag', 'pmod', 'pgen', zonesPreset);

    // ---- inst et ses zones
    final List<List<Generateur>> zonesInstrument = [];
    f.fourCC('inst');
    f.entier32((_instruments.length + 1) * 22);
    for (final int i in _instruments) {
      f.texte(_source.instruments[i].nom, 20);
      f.entier16(zonesInstrument.length);

      for (final int z in _zonesInstrument[i]!) {
        zonesInstrument.add([
          for (final Generateur g in _source.generateursDeZoneInstrument(z))
            switch (g.type) {
              generateurEchantillon => Generateur(
                g.type,
                echantillonVers[g.valeur]!,
              ),
              // Les décalages d'adresse comptent en points : ils suivent le
              // rééchantillonnage, sans quoi la note démarrerait ailleurs.
              _ when estDecalageAdresse(g.type) => Generateur(
                g.type,
                _decalageReduit(z, g),
              ),
              _ => g,
            },
        ]);
      }
    }
    f.texte('EOI', 20);
    f.entier16(zonesInstrument.length);

    ecrireZones(f, 'ibag', 'imod', 'igen', zonesInstrument);

    // ---- shdr
    f.fourCC('shdr');
    f.entier32((_echantillons.length + 1) * 46);
    int position = 0;
    for (final int e in _echantillons) {
      final EchantillonInfo info = _source.echantillons[e];
      final int longueur = _longueurReduite[e]!;
      final double rapport = longueur / (info.fin - info.debut);
      final int frequenceFinale = info.frequence <= frequence
          ? info.frequence
          : frequence;

      f.texte(info.nom, 20);
      f.entier32(position);
      f.entier32(position + longueur);
      f.entier32(
        position + ((info.debutBoucle - info.debut) * rapport).round(),
      );
      f.entier32(position + ((info.finBoucle - info.debut) * rapport).round());
      f.entier32(frequenceFinale);
      f.octet(info.hauteurOrigine);
      f.octet(info.correction & 0xFF);
      // Tout est mono : aucun échantillon n'a de jumeau à désigner.
      f.entier16(0);
      f.entier16(1);

      position += longueur + silenceEntreEchantillons;
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
  int _decalageReduit(int zone, Generateur g) {
    final int? e = _source.echantillonDeZoneInstrument(zone);
    if (e == null) return g.valeur;
    final EchantillonInfo info = _source.echantillons[e];
    if (info.frequence <= frequence) return g.valeur;

    // La valeur est un entier signé sur 16 bits.
    final int signe = g.valeur >= 0x8000 ? g.valeur - 0x10000 : g.valeur;
    final int reduit = (signe * frequence / info.frequence).round();
    return reduit < 0 ? reduit + 0x10000 : reduit;
  }
}
