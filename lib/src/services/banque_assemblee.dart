import 'dart:typed_data';

import 'sf2.dart';

/// Recolle plusieurs banques de sons en une seule, celle que le synthétiseur
/// charge.
///
/// C'est l'inverse de [BanqueReduite] : là où elle taille une banque à ce
/// qu'une recette réclame, l'assemblée réunit ce que l'utilisateur possède —
/// les sonorités embarquées dans l'appli et celles qu'il a téléchargées une
/// à une — pour que les menus n'aient qu'une banque à lire.
///
/// Rien n'est rééchantillonné ni filtré : les points sonores sont recopiés
/// tels quels, les générateurs aussi. Seuls les numéros changent, puisque
/// presets, instruments et échantillons de chaque source se retrouvent à la
/// suite les uns des autres.
///
/// Deux sources qui offrent la même sonorité (même banque, même programme)
/// ne la donnent qu'une fois : la première l'emporte, et le doublon est
/// noté dans [ignores] — de quoi le dire, plutôt que de laisser le
/// synthétiseur choisir en silence.
///
/// **Les échantillons identiques ne sont gardés qu'une fois**, d'où qu'ils
/// viennent. Ce n'est pas une économie théorique : dans MuseScore_General,
/// les cordes lentes, rapides et en trémolo (programmes 49, 48 et 44)
/// partagent exactement les mêmes 5,6 Mo de son, et ne se distinguent que par
/// leurs enveloppes. Sans cela, en télécharger trois coûterait trois fois le
/// prix d'une.
///
/// Comme pour [BanqueReduite], [octets] et [ecrire] sortent du même choix :
/// le poids annoncé est celui du fichier produit.
class BanqueAssemblee {
  /// Prépare l'assemblage des [sources], dans l'ordre donné, sans encore
  /// rien fabriquer.
  ///
  /// Lève [FormatException] si l'une d'elles n'est pas un SoundFont lisible.
  factory BanqueAssemblee.de(List<ByteData> sources) =>
      BanqueAssemblee._([for (final ByteData s in sources) Sf2.lire(s)]);

  BanqueAssemblee._(this._sources) {
    _choisir();
  }

  final List<Sf2> _sources;

  /// Ce qui est retenu, source par source.
  final List<_Part> _parts = [];

  /// Les échantillons retenus, dans l'ordre : d'où ils viennent et quel rang
  /// ils y portaient. C'est la table commune à toutes les sources, celle qui
  /// permet à deux banques de se partager un son.
  final List<({Sf2 source, int rang})> _echantillons = [];

  /// Pour retrouver vite un échantillon déjà pris : son empreinte mène aux
  /// rangs candidats, qu'on compare ensuite octet par octet.
  final Map<int, List<int>> _parEmpreinte = {};

  /// Les sonorités rencontrées une seconde fois, donc laissées de côté.
  final List<int> ignores = [];

  /// Combien d'échantillons ont été reconnus comme déjà présents. Zéro quand
  /// les sources n'ont rien en commun.
  int _partages = 0;
  int get echantillonsPartages => _partages;

  /// Les programmes de la banque 0 que l'assemblée offre, triés.
  List<int> get programmes => [
    for (final _Part part in _parts)
      for (final int p in part.presets)
        if (part.source.presets[p].banque == 0)
          part.source.presets[p].programme,
  ]..sort();

  void _choisir() {
    final Set<(int, int)> vus = {};

    for (final Sf2 source in _sources) {
      final _Part part = _Part(source);

      for (int p = 0; p < source.presets.length; p++) {
        final PresetInfo info = source.presets[p];
        if (!vus.add((info.banque, info.programme))) {
          ignores.add(info.programme);
          continue;
        }
        part.presets.add(p);

        for (int z = info.premiereZone; z < info.derniereZone; z++) {
          final int? instrument = source.instrumentDeZonePreset(z);
          if (instrument != null) _garderInstrument(part, instrument);
        }
      }

      _parts.add(part);
    }
  }

  /// Retient un instrument et les échantillons qu'il atteint, en réutilisant
  /// ceux qu'une source précédente a déjà apportés.
  void _garderInstrument(_Part part, int instrument) {
    if (part.instruments.contains(instrument)) return;
    part.instruments.add(instrument);

    final InstrumentInfo info = part.source.instruments[instrument];
    for (int z = info.premiereZone; z < info.derniereZone; z++) {
      final int? e = part.source.echantillonDeZoneInstrument(z);
      if (e == null || part.echantillonVers.containsKey(e)) continue;
      part.echantillonVers[e] = _rangGlobal(part.source, e);
    }
  }

  /// Le rang de cet échantillon dans la table commune : celui d'un jumeau
  /// déjà présent, ou un nouveau rang.
  int _rangGlobal(Sf2 source, int rang) {
    final int empreinte = _empreinte(source, rang);
    for (final int candidat in _parEmpreinte[empreinte] ?? const <int>[]) {
      final ({Sf2 source, int rang}) autre = _echantillons[candidat];
      if (_memeSon(source, rang, autre.source, autre.rang)) {
        _partages++;
        return candidat;
      }
    }

    _echantillons.add((source: source, rang: rang));
    final int nouveau = _echantillons.length - 1;
    (_parEmpreinte[empreinte] ??= []).add(nouveau);
    return nouveau;
  }

  /// Une empreinte bon marché d'un échantillon : ses réglages, sa longueur, et
  /// un point sur cent. Deux sons différents peuvent la partager — c'est
  /// pourquoi [_memeSon] tranche ensuite.
  int _empreinte(Sf2 source, int rang) {
    final EchantillonInfo e = source.echantillons[rang];
    int h = 0x811c9dc5;
    void melanger(int v) {
      h = ((h ^ (v & 0xFFFFFFFF)) * 0x01000193) & 0xFFFFFFFF;
    }

    melanger(e.fin - e.debut);
    melanger(e.frequence);
    melanger(e.hauteurOrigine);
    melanger(e.correction);
    melanger(e.debutBoucle - e.debut);
    melanger(e.finBoucle - e.debut);
    for (int i = e.debut; i < e.fin; i += 101) {
      melanger(source.point(i));
    }
    return h;
  }

  /// Deux échantillons sont le même son s'ils ont les mêmes réglages **et**
  /// exactement les mêmes points. On ne se fie pas à l'empreinte seule :
  /// garder par erreur deux sons pour un est un gâchis, en confondre deux
  /// différents ferait jouer faux.
  bool _memeSon(Sf2 a, int ra, Sf2 b, int rb) {
    final EchantillonInfo x = a.echantillons[ra];
    final EchantillonInfo y = b.echantillons[rb];

    final int longueur = x.fin - x.debut;
    if (longueur != y.fin - y.debut ||
        x.frequence != y.frequence ||
        x.hauteurOrigine != y.hauteurOrigine ||
        x.correction != y.correction ||
        x.debutBoucle - x.debut != y.debutBoucle - y.debut ||
        x.finBoucle - x.debut != y.finBoucle - y.debut) {
      return false;
    }

    for (int i = 0; i < longueur; i++) {
      if (a.point(x.debut + i) != b.point(y.debut + i)) return false;
    }
    return true;
  }

  /// Le poids du fichier qui sera produit, en octets.
  int get octets {
    int sons = 0;
    int presets = 0;
    int zonesPreset = 0;
    int generateursPreset = 0;
    int instruments = 0;
    int zonesInstrument = 0;
    int generateursInstrument = 0;
    int echantillons = 0;

    for (final ({Sf2 source, int rang}) e in _echantillons) {
      final EchantillonInfo info = e.source.echantillons[e.rang];
      sons += (info.fin - info.debut + silenceEntreEchantillons) * 2;
    }
    echantillons = _echantillons.length;

    for (final _Part part in _parts) {
      final Sf2 s = part.source;
      presets += part.presets.length;
      for (final int p in part.presets) {
        final PresetInfo info = s.presets[p];
        zonesPreset += info.derniereZone - info.premiereZone;
        for (int z = info.premiereZone; z < info.derniereZone; z++) {
          generateursPreset += s.generateursDeZonePreset(z).length;
        }
      }
      instruments += part.instruments.length;
      for (final int i in part.instruments) {
        final InstrumentInfo info = s.instruments[i];
        zonesInstrument += info.derniereZone - info.premiereZone;
        for (int z = info.premiereZone; z < info.derniereZone; z++) {
          generateursInstrument += s.generateursDeZoneInstrument(z).length;
        }
      }
    }

    return enteteFichier +
        tailleInfo +
        enteteListe +
        enteteChunk +
        sons +
        enteteListe +
        enteteChunk +
        (presets + 1) * 38 +
        enteteChunk +
        (zonesPreset + 1) * 4 +
        modulateurVide +
        enteteChunk +
        (generateursPreset + 1) * 4 +
        enteteChunk +
        (instruments + 1) * 22 +
        enteteChunk +
        (zonesInstrument + 1) * 4 +
        modulateurVide +
        enteteChunk +
        (generateursInstrument + 1) * 4 +
        enteteChunk +
        (echantillons + 1) * 46;
  }

  /// Fabrique la banque assemblée.
  Uint8List ecrire({String nom = 'Bizet'}) {
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
    for (final ({Sf2 source, int rang}) e in _echantillons) {
      final EchantillonInfo info = e.source.echantillons[e.rang];
      total += (info.fin - info.debut + silenceEntreEchantillons) * 2;
    }
    f.entier32(total);

    for (final ({Sf2 source, int rang}) e in _echantillons) {
      final EchantillonInfo info = e.source.echantillons[e.rang];
      f.points(
        Int16List.fromList([
          for (int i = info.debut; i < info.fin; i++) e.source.point(i),
        ]),
      );
      f.silence(silenceEntreEchantillons);
    }

    f.poserTaille(taille);
  }

  void _ecrireParametres(EcrivainSf2 f) {
    f.fourCC('LIST');
    final int taille = f.reserverTaille();
    f.fourCC('pdta');

    // Les instruments de chaque source viennent après ceux de la précédente.
    // Les échantillons, eux, portent déjà leur rang définitif : c'est ce
    // partage qui fait toute l'économie.
    int decalageInstrument = 0;
    for (final _Part part in _parts) {
      part.instrumentVers = {
        for (int i = 0; i < part.instruments.length; i++)
          part.instruments[i]: decalageInstrument + i,
      };
      decalageInstrument += part.instruments.length;
    }

    // ---- phdr et ses zones
    final List<List<Generateur>> zonesPreset = [];
    int nombrePresets = 0;
    for (final _Part part in _parts) {
      nombrePresets += part.presets.length;
    }
    f.fourCC('phdr');
    f.entier32((nombrePresets + 1) * 38);
    for (final _Part part in _parts) {
      final Sf2 s = part.source;
      for (final int p in part.presets) {
        final PresetInfo info = s.presets[p];
        f.texte(info.nom, 20);
        f.entier16(info.programme);
        f.entier16(info.banque);
        f.entier16(zonesPreset.length);
        f.entier32(info.bibliotheque);
        f.entier32(info.genre);
        f.entier32(info.morphologie);

        for (int z = info.premiereZone; z < info.derniereZone; z++) {
          zonesPreset.add([
            for (final Generateur g in s.generateursDeZonePreset(z))
              g.type == generateurInstrument
                  ? Generateur(g.type, part.instrumentVers[g.valeur]!)
                  : g,
          ]);
        }
      }
    }
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
    f.entier32((decalageInstrument + 1) * 22);
    for (final _Part part in _parts) {
      final Sf2 s = part.source;
      for (final int i in part.instruments) {
        final InstrumentInfo info = s.instruments[i];
        f.texte(info.nom, 20);
        f.entier16(zonesInstrument.length);

        for (int z = info.premiereZone; z < info.derniereZone; z++) {
          zonesInstrument.add([
            for (final Generateur g in s.generateursDeZoneInstrument(z))
              g.type == generateurEchantillon
                  ? Generateur(g.type, part.echantillonVers[g.valeur]!)
                  : g,
          ]);
        }
      }
    }
    f.texte('EOI', 20);
    f.entier16(zonesInstrument.length);

    ecrireZones(f, 'ibag', 'imod', 'igen', zonesInstrument);

    // ---- shdr
    f.fourCC('shdr');
    f.entier32((_echantillons.length + 1) * 46);
    int position = 0;
    for (final ({Sf2 source, int rang}) e in _echantillons) {
      final EchantillonInfo info = e.source.echantillons[e.rang];
      final int longueur = info.fin - info.debut;

      f.texte(info.nom, 20);
      f.entier32(position);
      f.entier32(position + longueur);
      f.entier32(position + (info.debutBoucle - info.debut));
      f.entier32(position + (info.finBoucle - info.debut));
      f.entier32(info.frequence);
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
}

/// Ce qu'une source apporte à l'assemblée : ses presets retenus, et les
/// instruments qu'ils atteignent, dans l'ordre où on les rencontre.
///
/// Les échantillons, eux, ne lui appartiennent pas : ils vivent dans la table
/// commune de [BanqueAssemblee], et [echantillonVers] dit seulement où chacun
/// de ceux qu'elle utilise a atterri.
class _Part {
  _Part(this.source);

  final Sf2 source;
  final List<int> presets = [];
  final List<int> instruments = [];

  Map<int, int> instrumentVers = const {};
  final Map<int, int> echantillonVers = {};
}
