import 'dart:typed_data';

import '../model/armure.dart';
import '../model/melodie.dart';
import '../model/mesure.dart';
import '../model/note.dart';

/// Lit un fichier MIDI standard (.mid, .midi) et en fait une [Melodie].
///
/// C'est la porte d'entrée des partitions que l'utilisateur apporte lui-même :
/// le MIDI est le format le plus répandu du monde pour la musique écrite en
/// notes, et notre modèle en est déjà très proche (hauteurs MIDI, durées en
/// noires).
///
/// Même esprit que le parseur LilyPond : toutes les pistes sont réunies en un
/// seul morceau, joué par un seul instrument. Ce qui ne rentre pas dans le
/// modèle est laissé de côté sans faire échouer la lecture :
///
/// * les changements de tempo en cours de morceau (le premier tempo vaut pour
///   tout, le tempo est un réglage global de l'appli) ;
/// * les vélocités note à note (les nuances sont recréées par les réglages) ;
/// * le canal 10, celui des percussions : une batterie n'est pas une mélodie.
class MidiParser {
  /// [titre] est le nom à donner au morceau, en pratique le nom du fichier :
  /// les noms de piste écrits dans les fichiers MIDI sont rarement fiables
  /// (« Track 1 », « Grand Piano »), on ne s'en sert qu'à défaut.
  Melodie parse(Uint8List octets, {String titre = ''}) {
    final _Lecteur lecteur = _Lecteur(octets);

    // ----- l'en-tête MThd : format, nombre de pistes, division du temps
    if (lecteur.texte(4) != 'MThd' || lecteur.entier32() != 6) {
      throw const FormatException('Ce fichier n\'est pas un fichier MIDI.');
    }
    final int format = lecteur.entier16();
    if (format > 1) {
      // Le type 2 (pistes indépendantes jouées séparément) est rarissime et
      // n'a pas de traduction en un seul morceau.
      throw const FormatException(
          'Ce fichier MIDI est d\'un type que l\'appli ne sait pas lire.');
    }
    final int nombreDePistes = lecteur.entier16();
    final int division = lecteur.entier16();
    if (division == 0 || (division & 0x8000) != 0) {
      // Le bit haut indique un temps en images par seconde (SMPTE), un format
      // de synchronisation vidéo sans notion de noire.
      throw const FormatException(
          'Ce fichier MIDI compte le temps en images vidéo, pas en notes.');
    }

    // ----- les pistes, fusionnées en une seule ligne d'événements
    final _Collecte collecte = _Collecte();
    for (int p = 0; p < nombreDePistes && !lecteur.fini; p++) {
      _lirePiste(lecteur, division, collecte, premierePiste: p == 0);
    }
    if (collecte.notes.isEmpty) {
      throw const FormatException('Aucune note dans ce fichier MIDI.');
    }

    return Melodie(
      titre: titre.isNotEmpty ? titre : collecte.nomDePiste ?? '',
      source: '',
      tempo: collecte.tempo ?? 120,
      instrumentMidi: collecte.programme ?? 0,
      mesures: _enMesures(collecte),
      armure: collecte.armure,
    );
  }

  /// Parcourt une piste MTrk et verse ce qu'elle contient dans [collecte].
  void _lirePiste(
    _Lecteur lecteur,
    int division,
    _Collecte collecte, {
    required bool premierePiste,
  }) {
    if (lecteur.texte(4) != 'MTrk') {
      throw const FormatException('Ce fichier MIDI est abîmé.');
    }
    final int longueurDePiste = lecteur.entier32();
    final int fin = lecteur.position + longueurDePiste;

    // Notes en train de sonner : par canal et hauteur, les instants de début.
    // Une pile, car un fichier peut rejouer une note avant de l'avoir éteinte.
    final Map<int, List<double>> ouvertes = {};
    int tic = 0;
    int statut = 0;

    while (lecteur.position < fin && !lecteur.fini) {
      tic += lecteur.dureeVariable();
      int octet = lecteur.entier8();

      if (octet < 0x80) {
        // Statut répété (« running status ») : l'octet lu est déjà une donnée.
        lecteur.reculer();
        octet = statut;
        if (octet < 0x80) {
          throw const FormatException('Ce fichier MIDI est abîmé.');
        }
      }

      if (octet == 0xFF) {
        // Événement méta : type, longueur, contenu.
        final int type = lecteur.entier8();
        final int longueur = lecteur.dureeVariable();
        final Uint8List donnees = lecteur.tranche(longueur);
        _lireMeta(type, donnees, tic, collecte, premierePiste: premierePiste);
        continue;
      }
      if (octet == 0xF0 || octet == 0xF7) {
        // Message système exclusif : sans intérêt ici, on l'enjambe.
        lecteur.tranche(lecteur.dureeVariable());
        continue;
      }

      statut = octet;
      final int genre = octet & 0xF0;
      final int canal = octet & 0x0F;
      final int donnee1 = lecteur.entier8();
      final int donnee2 =
          (genre == 0xC0 || genre == 0xD0) ? 0 : lecteur.entier8();

      if (canal == 9) continue; // percussions

      final double temps = tic / division;
      if (genre == 0x90 && donnee2 > 0) {
        ouvertes.putIfAbsent(canal << 8 | donnee1, () => []).add(temps);
      } else if (genre == 0x80 || (genre == 0x90 && donnee2 == 0)) {
        final List<double>? piles = ouvertes[canal << 8 | donnee1];
        if (piles != null && piles.isNotEmpty) {
          final double debut = piles.removeAt(0);
          if (temps > debut) {
            collecte.notes.add(_NoteBrute(debut, temps - debut, donnee1));
          }
        }
      } else if (genre == 0xC0) {
        collecte.programme ??= donnee1 & 0x7F;
      }
    }

    // Une note jamais éteinte s'arrête à la fin de la piste : mieux vaut une
    // fin abrupte qu'une note perdue ou une durée infinie.
    final double bout = tic / division;
    ouvertes.forEach((cle, debuts) {
      for (final double debut in debuts) {
        if (bout > debut) {
          collecte.notes.add(_NoteBrute(debut, bout - debut, cle & 0xFF));
        }
      }
    });
    lecteur.position = fin;
  }

  void _lireMeta(
    int type,
    Uint8List donnees,
    int tic,
    _Collecte collecte, {
    required bool premierePiste,
  }) {
    switch (type) {
      case 0x51: // tempo, en microsecondes par noire
        if (collecte.tempo == null && donnees.length == 3) {
          final int microsecondes =
              donnees[0] << 16 | donnees[1] << 8 | donnees[2];
          if (microsecondes > 0) {
            collecte.tempo = (60000000 / microsecondes).round().clamp(1, 400);
          }
        }
      case 0x58: // signature temporelle : numérateur, dénominateur en 2^n
        if (donnees.length >= 2) {
          final double dureeMesure = donnees[0] * 4.0 / (1 << donnees[1]);
          if (dureeMesure > 0) collecte.signatures[tic] = dureeMesure;
        }
      case 0x59: // armure : dièses (ou bémols en négatif), puis le mode
        if (collecte.armure == null && donnees.length == 2) {
          final int alterations = donnees[0].toSigned(8);
          final bool majeur = donnees[1] == 0;
          collecte.armure = Armure(
            tonique: ((alterations * 7) + (majeur ? 0 : 9)) % 12,
            majeur: majeur,
          );
        }
      case 0x03: // nom de piste
        if (premierePiste && collecte.nomDePiste == null) {
          final String nom = String.fromCharCodes(donnees).trim();
          if (nom.isNotEmpty) collecte.nomDePiste = nom;
        }
    }
  }

  /// Range les notes dans des mesures, découpées selon les signatures
  /// temporelles du fichier (4/4 à défaut). Une note à cheval reste dans la
  /// mesure où elle commence : le modèle sait la faire déborder à la lecture.
  List<Mesure> _enMesures(_Collecte collecte) {
    final List<_NoteBrute> notes = collecte.notes
      ..sort((a, b) => a.debut.compareTo(b.debut));
    final double finDuMorceau =
        notes.map((n) => n.debut + n.duree).reduce((a, b) => a > b ? a : b);

    // Les changements de signature, convertis du tic au temps.
    final List<({double temps, double duree})> signatures = [
      for (final entree in collecte.signatures.entries)
        (temps: entree.key / 1, duree: entree.value),
    ]..sort((a, b) => a.temps.compareTo(b.temps));

    final List<Mesure> mesures = [];
    double debutMesure = 0.0;
    double dureeMesure = 4.0;
    int prochaine = 0;
    int rang = 0;
    const double epsilon = 1e-6;

    while (debutMesure < finDuMorceau - epsilon) {
      // Garde-fou : un fichier délirant ne doit pas fabriquer un morceau sans
      // fin (le même esprit que les répétitions bornées du parseur LilyPond).
      if (mesures.length >= 4096) {
        throw const FormatException('Ce fichier MIDI est trop long.');
      }
      while (prochaine < signatures.length &&
          signatures[prochaine].temps <= debutMesure + epsilon) {
        dureeMesure = signatures[prochaine].duree;
        prochaine++;
      }
      final double finMesure = debutMesure + dureeMesure;
      final List<Note> dedans = [];
      while (rang < notes.length && notes[rang].debut < finMesure - epsilon) {
        dedans.add(Note(
          hauteur: notes[rang].hauteur,
          duree: notes[rang].duree,
          position: notes[rang].debut - debutMesure,
        ));
        rang++;
      }
      mesures.add(Mesure(notes: dedans, duree: dureeMesure));
      debutMesure = finMesure;
    }
    return mesures;
  }
}

/// Ce que les pistes déposent en passant : la première valeur rencontrée fait
/// foi pour le tempo, l'instrument et l'armure, à l'image d'un morceau qui
/// commence.
class _Collecte {
  final List<_NoteBrute> notes = [];

  /// Changements de signature, du tic où ils tombent à la durée de mesure.
  /// En tics et non en temps : les signatures viennent souvent d'une piste
  /// lue avant celles qui portent les notes.
  final Map<int, double> signatures = {};

  int? tempo;
  int? programme;
  Armure? armure;
  String? nomDePiste;
}

/// Une note à plat, en temps absolu (1,0 = une noire), avant la mise en
/// mesures.
class _NoteBrute {
  final double debut;
  final double duree;
  final int hauteur;
  _NoteBrute(this.debut, this.duree, this.hauteur);
}

/// Un curseur sur les octets du fichier, qui refuse de lire au-delà du bout :
/// un fichier tronqué donne une erreur claire, pas un plantage.
class _Lecteur {
  final Uint8List octets;
  int position = 0;

  _Lecteur(this.octets);

  bool get fini => position >= octets.length;

  int entier8() {
    if (position >= octets.length) {
      throw const FormatException('Ce fichier MIDI est tronqué.');
    }
    return octets[position++];
  }

  int entier16() => entier8() << 8 | entier8();
  int entier32() => entier16() << 16 | entier16();

  void reculer() => position--;

  String texte(int longueur) => String.fromCharCodes(tranche(longueur));

  Uint8List tranche(int longueur) {
    if (longueur < 0 || position + longueur > octets.length) {
      throw const FormatException('Ce fichier MIDI est tronqué.');
    }
    final Uint8List vue = octets.sublist(position, position + longueur);
    position += longueur;
    return vue;
  }

  /// La « quantité de longueur variable » du format : sept bits utiles par
  /// octet, le huitième indiquant qu'un octet suit.
  int dureeVariable() {
    int valeur = 0;
    for (int i = 0; i < 4; i++) {
      final int octet = entier8();
      valeur = valeur << 7 | (octet & 0x7F);
      if (octet & 0x80 == 0) return valeur;
    }
    throw const FormatException('Ce fichier MIDI est abîmé.');
  }
}
