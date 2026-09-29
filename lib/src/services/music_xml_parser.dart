import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../model/armure.dart';
import '../model/melodie.dart';
import '../model/mesure.dart';
import '../model/note.dart';

/// Lit une partition MusicXML et en fait une [Melodie].
///
/// MusicXML est le format d'échange des logiciels de partition : MuseScore,
/// Finale, Sibelius savent tous l'écrire. C'est la deuxième porte d'entrée
/// des partitions que l'utilisateur apporte lui-même, après le MIDI, et la
/// plus riche : les mesures, l'armure et le titre y sont écrits noir sur
/// blanc au lieu d'être devinés.
///
/// Les deux formes du format se lisent : le fichier texte (.musicxml, .xml)
/// et le conteneur compressé (.mxl), qui est ce que MuseScore exporte par
/// défaut.
///
/// Même esprit que les autres lecteurs : toutes les parties sont réunies en
/// un seul morceau, joué par un seul instrument. Les reprises écrites ne sont
/// pas déroulées (le morceau se joue une fois, d'un bout à l'autre), les
/// petites notes d'ornement sans durée sont laissées de côté, et les
/// percussions sans hauteur aussi.
class MusicXmlParser {
  /// [titre] sert de secours quand la partition ne déclare pas le sien, en
  /// pratique le nom du fichier.
  Melodie parse(Uint8List octets, {String titre = ''}) {
    final XmlDocument document = _document(octets);
    final XmlElement racine = document.rootElement;
    if (racine.name.local == 'score-timewise') {
      // La variante « une mesure contenant les parties » : permise par la
      // norme mais introuvable en pratique, aucun logiciel courant ne l'écrit.
      throw const FormatException(
          'Cette partition MusicXML est rangée mesure par mesure, '
          'une variante que l\'appli ne sait pas lire.');
    }
    if (racine.name.local != 'score-partwise') {
      throw const FormatException('Ce fichier n\'est pas du MusicXML.');
    }

    // ----- chaque partie se lit seule : des notes en temps absolu
    final List<_Partie> parties = [
      for (final part in racine.findElements('part')) _lirePartie(part),
    ];
    if (parties.every((p) => p.notes.isEmpty)) {
      throw const FormatException('Aucune note dans cette partition.');
    }

    return Melodie(
      titre: _titreEcrit(racine) ?? titre,
      source: _compositeur(racine) ?? '',
      tempo: _premierTempo(racine) ?? 120,
      instrumentMidi: _premierProgramme(racine) ?? 0,
      mesures: _fusionner(parties),
      armure: _armureEcrite(racine),
    );
  }

  /// Le document XML, tiré du texte nu ou du conteneur compressé .mxl (une
  /// archive zip dont META-INF/container.xml désigne la vraie partition).
  XmlDocument _document(Uint8List octets) {
    Uint8List contenu = octets;
    if (octets.length >= 2 && octets[0] == 0x50 && octets[1] == 0x4B) {
      contenu = _depuisMxl(octets);
    }
    try {
      return XmlDocument.parse(utf8.decode(contenu, allowMalformed: true));
    } on XmlException {
      throw const FormatException('Ce fichier n\'est pas du MusicXML.');
    }
  }

  Uint8List _depuisMxl(Uint8List octets) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(octets);
    } catch (_) {
      throw const FormatException('Ce fichier .mxl est abîmé.');
    }

    Uint8List? lire(String chemin) {
      for (final ArchiveFile fichier in archive) {
        if (fichier.name == chemin) {
          return Uint8List.fromList(fichier.readBytes() ?? []);
        }
      }
      return null;
    }

    // Le sommaire du conteneur dit où est la partition.
    final Uint8List? sommaire = lire('META-INF/container.xml');
    if (sommaire != null) {
      try {
        final XmlDocument conteneur =
            XmlDocument.parse(utf8.decode(sommaire, allowMalformed: true));
        for (final rootfile in conteneur.findAllElements('rootfile')) {
          final String? chemin = rootfile.getAttribute('full-path');
          if (chemin == null) continue;
          final Uint8List? partition = lire(chemin);
          if (partition != null) return partition;
        }
      } on XmlException {
        // Sommaire illisible : on cherche la partition à l'aveugle.
      }
    }
    // À défaut de sommaire : le premier fichier XML hors META-INF.
    for (final ArchiveFile fichier in archive) {
      if (!fichier.name.startsWith('META-INF/') &&
          (fichier.name.endsWith('.xml') ||
              fichier.name.endsWith('.musicxml'))) {
        return Uint8List.fromList(fichier.readBytes() ?? []);
      }
    }
    throw const FormatException(
        'Ce fichier .mxl ne contient pas de partition.');
  }

  // ------------------------------------------------------------ une partie

  /// Parcourt les mesures d'une partie avec un curseur, comme le format le
  /// demande : les notes avancent le curseur, `<backup>` le recule (pour
  /// écrire une seconde voix), `<chord/>` pose la note sur la précédente.
  _Partie _lirePartie(XmlElement part) {
    final _Partie partie = _Partie();
    // Combien de « divisions » valent une noire : l'unité de durée du format,
    // déclarée par la partition et changeable en cours de route.
    double divisions = 1.0;
    double debutMesure = 0.0;
    // La note qu'une liaison attend de prolonger, par hauteur. Au niveau de
    // la partie : la liaison la plus courante traverse la barre de mesure.
    final Map<int, Note> aProlonger = {};

    for (final XmlElement mesure in part.findElements('measure')) {
      double curseur = debutMesure;
      double atteint = debutMesure;
      double precedente = debutMesure;

      for (final XmlElement element in mesure.childElements) {
        switch (element.name.local) {
          case 'attributes':
            final String? d = element.getElement('divisions')?.innerText;
            if (d != null) divisions = double.tryParse(d.trim()) ?? divisions;
            final XmlElement? signature = element.getElement('time');
            if (signature != null) {
              final double? haut = double.tryParse(
                  signature.getElement('beats')?.innerText.trim() ?? '');
              final double? bas = double.tryParse(
                  signature.getElement('beat-type')?.innerText.trim() ?? '');
              if (haut != null && bas != null && bas > 0) {
                partie.signatures[partie.mesures.length] = haut * 4.0 / bas;
              }
            }
          case 'backup':
            curseur -= _duree(element, divisions);
          case 'forward':
            curseur += _duree(element, divisions);
            if (curseur > atteint) atteint = curseur;
          case 'note':
            final double duree = _duree(element, divisions);
            final bool accord = element.getElement('chord') != null;
            final double debut = accord ? precedente : curseur;
            if (!accord) precedente = curseur;

            final int? hauteur = _hauteur(element);
            if (hauteur != null && duree > 0) {
              if (_prolonge(element)) {
                final Note? tenue = aProlonger[hauteur];
                if (tenue != null) {
                  // La note liée prolonge la précédente au lieu d'être
                  // refrappée : c'est toute la différence à l'oreille.
                  partie.allonger(tenue, duree);
                  if (_tient(element)) {
                    aProlonger[hauteur] = tenue;
                  } else {
                    aProlonger.remove(hauteur);
                  }
                } else {
                  final Note posee = partie.poser(debut, duree, hauteur);
                  if (_tient(element)) aProlonger[hauteur] = posee;
                }
              } else {
                final Note posee = partie.poser(debut, duree, hauteur);
                if (_tient(element)) aProlonger[hauteur] = posee;
              }
            }
            if (!accord) curseur += duree;
            if (curseur > atteint) atteint = curseur;
        }
      }

      partie.mesures.add(atteint - debutMesure);
      debutMesure = atteint;
    }
    return partie;
  }

  /// La durée d'un élément, convertie en noires. Une petite note d'ornement
  /// (`<grace/>`) n'a pas de durée : elle vaut zéro et sera laissée de côté.
  double _duree(XmlElement element, double divisions) {
    final String? texte = element.getElement('duration')?.innerText;
    if (texte == null || divisions <= 0) return 0.0;
    return (double.tryParse(texte.trim()) ?? 0.0) / divisions;
  }

  /// La hauteur MIDI d'une note, nulle pour un silence, une percussion sans
  /// hauteur ou une note hors du clavier.
  int? _hauteur(XmlElement note) {
    final XmlElement? pitch = note.getElement('pitch');
    if (pitch == null) return null;
    const Map<String, int> marches = {
      'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11,
    };
    final int? marche = marches[pitch.getElement('step')?.innerText.trim()];
    final int? octave =
        int.tryParse(pitch.getElement('octave')?.innerText.trim() ?? '');
    if (marche == null || octave == null) return null;
    final double alteration = double.tryParse(
            pitch.getElement('alter')?.innerText.trim() ?? '0') ??
        0.0;
    final int hauteur = (octave + 1) * 12 + marche + alteration.round();
    return (hauteur < 0 || hauteur > 127) ? null : hauteur;
  }

  bool _prolonge(XmlElement note) =>
      note.findElements('tie').any((t) => t.getAttribute('type') == 'stop');

  bool _tient(XmlElement note) =>
      note.findElements('tie').any((t) => t.getAttribute('type') == 'start');

  // ------------------------------------------------------- toute la partition

  /// Réunit les parties en une suite de [Mesure], alignées mesure à mesure :
  /// la n-ième mesure de chaque partie commence au même instant, et sa durée
  /// est la plus longue observée (les levées et mesures incomplètes gardent
  /// ainsi leur vraie longueur).
  List<Mesure> _fusionner(List<_Partie> parties) {
    final int nombre =
        parties.map((p) => p.mesures.length).reduce((a, b) => a > b ? a : b);

    final List<double> durees = List<double>.filled(nombre, 0.0);
    double signature = 4.0;
    for (int m = 0; m < nombre; m++) {
      for (final _Partie partie in parties) {
        signature = partie.signatures[m] ?? signature;
        if (m < partie.mesures.length && partie.mesures[m] > durees[m]) {
          durees[m] = partie.mesures[m];
        }
      }
      // Une mesure entièrement vide (aucune durée écrite) tient sa longueur
      // de la signature courante.
      if (durees[m] <= 0) durees[m] = signature;
    }

    // Où commence chaque mesure : chaque partie a rangé ses notes en temps
    // absolu selon SES mesures, qu'il faut recaler sur la grille commune.
    final List<Mesure> mesures = [
      for (int m = 0; m < nombre; m++) Mesure(notes: [], duree: durees[m]),
    ];
    final List<double> debuts = [0.0];
    for (int m = 1; m < nombre; m++) {
      debuts.add(debuts[m - 1] + durees[m - 1]);
    }

    for (final _Partie partie in parties) {
      double debutLocal = 0.0;
      int m = 0;
      for (final note in partie.notes) {
        while (m + 1 < partie.mesures.length &&
            note.debut >= debutLocal + partie.mesures[m] - 1e-6) {
          debutLocal += partie.mesures[m];
          m++;
        }
        mesures[m].notes.add(Note(
              hauteur: note.hauteur,
              duree: note.duree,
              position: note.debut - debutLocal,
            ));
      }
    }
    return mesures;
  }

  String? _premierTexte(XmlElement racine, String balise) {
    for (final XmlElement element in racine.findAllElements(balise)) {
      final String texte = element.innerText.trim();
      if (texte.isNotEmpty) return texte;
    }
    return null;
  }

  String? _titreEcrit(XmlElement racine) =>
      _premierTexte(racine, 'work-title') ??
      _premierTexte(racine, 'movement-title');

  String? _compositeur(XmlElement racine) {
    for (final XmlElement creator in racine.findAllElements('creator')) {
      if (creator.getAttribute('type') == 'composer') {
        final String nom = creator.innerText.trim();
        if (nom.isNotEmpty) return nom;
      }
    }
    return null;
  }

  int? _premierTempo(XmlElement racine) {
    for (final XmlElement sound in racine.findAllElements('sound')) {
      final double? tempo =
          double.tryParse(sound.getAttribute('tempo') ?? '');
      if (tempo != null && tempo > 0) return tempo.round().clamp(1, 400);
    }
    return null;
  }

  int? _premierProgramme(XmlElement racine) {
    for (final XmlElement programme
        in racine.findAllElements('midi-program')) {
      final int? valeur = int.tryParse(programme.innerText.trim());
      // MusicXML compte les programmes de 1 à 128, le moteur de 0 à 127.
      if (valeur != null && valeur >= 1 && valeur <= 128) return valeur - 1;
    }
    return null;
  }

  /// L'armure écrite : le nombre de dièses (ou de bémols, en négatif) et le
  /// mode donnent la tonique, comme pour un fichier MIDI.
  Armure? _armureEcrite(XmlElement racine) {
    for (final XmlElement key in racine.findAllElements('key')) {
      final int? alterations =
          int.tryParse(key.getElement('fifths')?.innerText.trim() ?? '');
      if (alterations == null) continue;
      final bool majeur =
          (key.getElement('mode')?.innerText.trim() ?? 'major') != 'minor';
      return Armure(
        tonique: ((alterations * 7) + (majeur ? 0 : 9)) % 12,
        majeur: majeur,
      );
    }
    return null;
  }
}

/// Une partie en cours de lecture : ses notes en temps absolu, la durée
/// réelle de chacune de ses mesures, et les signatures déclarées.
class _Partie {
  final List<_NotePosee> notes = [];
  final List<double> mesures = [];
  final Map<int, double> signatures = {};

  Note poser(double debut, double duree, int hauteur) {
    final _NotePosee posee = _NotePosee(debut, duree, hauteur);
    notes.add(posee);
    return posee.note;
  }

  /// Allonge une note déjà posée : les liaisons de tenue en font une seule
  /// note continue.
  void allonger(Note note, double duree) {
    for (final _NotePosee posee in notes.reversed) {
      if (identical(posee.note, note)) {
        posee.duree += duree;
        return;
      }
    }
  }
}

class _NotePosee {
  final double debut;
  double duree;
  final int hauteur;

  /// Témoin d'identité pour les liaisons : la vraie [Note] est refaite à la
  /// fusion, position recalée sur la grille commune.
  final Note note;

  _NotePosee(this.debut, this.duree, this.hauteur)
      : note = Note(hauteur: hauteur, duree: duree, position: debut);
}
