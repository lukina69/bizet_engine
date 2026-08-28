import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:bizet_engine/bizet_engine.dart';
import 'package:dart_melty_soundfont/dart_melty_soundfont.dart';

/// Fabrique ce que l'appli télécharge « à la carte » : une banque par
/// sonorité, son extrait à écouter avant de choisir, et le manifeste qui
/// dit à l'appli ce qui existe et ce que ça pèse.
///
///     dart run tool/publier_instruments.dart <General.sf2> <HQ.sf2> <dossier>
///
/// Pour chaque programme General MIDI mélodique (0 à 119 — les huit effets
/// sonores, 120 à 127, n'ont rien à faire dans une mélodie) :
///
/// - `pNNN.sf2` : la sonorité seule, taillée dans MuseScore_General sans
///   rien rééchantillonner (48 000 Hz est au-dessus de tout ce qu'elle
///   contient) ;
/// - `pNNN-hq.sf2` : la même taillée dans MuseScore_General-HQ, **seulement
///   si elle s'entend autrement** — même phrase rendue, autre son. Comparer
///   les octets des fichiers ne suffit pas : les deux banques diffèrent par
///   des champs réservés sans effet, et l'utilisateur n'a rien à choisir
///   entre deux fichiers qui sonnent pareil ;
/// - `pNNN.wav` (et `pNNN-hq.wav`) : la même petite phrase jouée par cette
///   sonorité, rendue par **notre** synthétiseur à 16 000 Hz mono, donc
///   exactement ce que l'utilisateur entendra une fois l'instrument
///   téléchargé — HQ comprise, dont certains presets comptent sur des
///   modulateurs que dart_melty_soundfont ignore ;
/// - `instruments.json` : le manifeste — programme, nom du preset, famille
///   GM, ambitus du fichier, et pour chaque version fichier, poids, extrait
///   et puissance mesurée (RMS d'une note à vélocité 60, comme
///   `mesure_poids.dart`, pour égaliser les voix plus tard).
///
/// Le dossier produit se publie tel quel dans une release GitHub.
void main(List<String> args) {
  if (args.length != 3) {
    print(
      'Usage : dart run tool/publier_instruments.dart '
      '<General.sf2> <HQ.sf2> <dossier de sortie>',
    );
    exit(1);
  }

  final ByteData general = _lire(args[0]);
  final ByteData hq = _lire(args[1]);
  final Directory sortie = Directory(args[2])..createSync(recursive: true);

  final List<Map<String, Object?>> instruments = [];
  int total = 0;

  for (int programme = 0; programme < 120; programme++) {
    final _Version? standard = _Version.tailler(
      general,
      programme,
      sortie,
      'p${_num(programme)}',
    );
    if (standard == null) {
      print('${_num(programme)}  absent de MuseScore_General, sauté');
      continue;
    }

    standard.ecrireExtrait();

    _Version? hqVersion = _Version.tailler(
      hq,
      programme,
      sortie,
      'p${_num(programme)}-hq',
    );
    if (hqVersion != null) {
      hqVersion.ecrireExtrait();
      if (hqVersion.sonneComme(standard)) {
        hqVersion.effacer();
        hqVersion = null;
      }
    }

    total += standard.octets + (hqVersion?.octets ?? 0);
    instruments.add({
      'programme': programme,
      'nom': standard.nom,
      'famille': programme ~/ 8,
      'ambitus': [standard.ambitus.$1, standard.ambitus.$2],
      'standard': standard.manifeste(),
      if (hqVersion != null) 'hq': hqVersion.manifeste(),
    });

    print(
      '${_num(programme)}  ${standard.nom.padRight(24)} '
      '${_mo(standard.octets).padLeft(8)}'
      '${hqVersion == null ? '        =' : _mo(hqVersion.octets).padLeft(9)}'
      '   rms ${standard.rms.toStringAsFixed(0).padLeft(5)}'
      '${hqVersion == null ? '' : ' / ${hqVersion.rms.toStringAsFixed(0)}'}',
    );
  }

  final Map<String, Object?> manifeste = {
    'version': 1,
    'sources': {'standard': _nomDeBanque(general), 'hq': _nomDeBanque(hq)},
    'extrait': {
      'frequence': _Version.frequenceExtrait,
      'phrase': 'do mi sol do ; sol mi do, 120 à la noire',
    },
    'instruments': instruments,
  };
  File(
    '${sortie.path}/instruments.json',
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifeste));

  print(
    '\n${instruments.length} sonorités, '
    '${instruments.where((i) => i.containsKey('hq')).length} avec une '
    'version HQ distincte, ${_mo(total)} de banques en tout.',
  );
}

ByteData _lire(String chemin) {
  final Uint8List o = File(chemin).readAsBytesSync();
  return ByteData.view(o.buffer, o.offsetInBytes);
}

String _num(int programme) => programme.toString().padLeft(3, '0');

String _mo(int octets) => '${(octets / 1e6).toStringAsFixed(2)} Mo';

/// Le nom que la banque se donne (INAM), pour tracer d'où vient chaque
/// fichier. Lu dans l'en-tête RIFF, sans charger la banque : la liste INFO
/// est la première du fichier.
String _nomDeBanque(ByteData donnees) {
  String quatre(int ou) => String.fromCharCodes([
    for (int i = 0; i < 4; i++) donnees.getUint8(ou + i),
  ]);
  int taille(int ou) => donnees.getUint32(ou, Endian.little);

  // RIFF, taille, sfbk, puis LIST, taille, INFO.
  int position = 12;
  if (quatre(position) != 'LIST' || quatre(position + 8) != 'INFO') {
    return '?';
  }
  final int fin = position + 8 + taille(position + 4);
  position += 12;
  while (position + 8 <= fin) {
    final String id = quatre(position);
    final int n = taille(position + 4);
    if (id == 'INAM') {
      return String.fromCharCodes([
        for (int i = 0; i < n; i++)
          if (donnees.getUint8(position + 8 + i) != 0)
            donnees.getUint8(position + 8 + i),
      ]);
    }
    position += 8 + n + (n.isOdd ? 1 : 0);
  }
  return '?';
}

/// Une sonorité taillée dans une banque, écrite sur le disque, mesurée.
class _Version {
  _Version._(this.fichier, this.octets, this.nom, this.ambitus, this._contenu);

  static const int frequenceExtrait = 16000;

  final File fichier;
  final int octets;
  final String nom;
  final (int, int) ambitus;
  final Uint8List _contenu;

  late final File extrait;
  late final ArrayInt16 _son;
  late final double rms;

  static _Version? tailler(
    ByteData banque,
    int programme,
    Directory sortie,
    String base,
  ) {
    final BanqueReduite reduite = BanqueReduite.pour(
      banque,
      programmes: {programme},
      frequence: 48000,
    );
    if (reduite.manquants.isNotEmpty || reduite.detail.isEmpty) return null;

    final Uint8List contenu = reduite.ecrire(nom: reduite.detail.first.nom);
    final File fichier = File('${sortie.path}/$base.sf2')
      ..writeAsBytesSync(contenu);

    return _Version._(
      fichier,
      contenu.lengthInBytes,
      reduite.detail.first.nom,
      reduite.ambitus[programme] ?? (0, 127),
      contenu,
    );
  }

  /// Même phrase, même son au point près : rien à choisir entre les deux.
  bool sonneComme(_Version autre) {
    final Uint8List a = Uint8List.sublistView(_son.bytes);
    final Uint8List b = Uint8List.sublistView(autre._son.bytes);
    if (a.lengthInBytes != b.lengthInBytes) return false;
    for (int i = 0; i < a.lengthInBytes; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void effacer() {
    fichier.deleteSync();
    extrait.deleteSync();
  }

  ByteData get _vue => ByteData.view(_contenu.buffer, _contenu.offsetInBytes);

  /// La phrase témoin, rendue à 16 000 Hz, et la puissance d'une note.
  void ecrireExtrait() {
    final int programme = int.parse(
      fichier.uri.pathSegments.last.substring(1, 4),
    );

    final RenduAudio rendu = RenduAudio(frequenceRendu: frequenceExtrait);
    rendu.chargerSoundFont(_vue);
    _son = rendu.rendre(
      _phrase(programme),
      reglages: Reglages(instrument: programme),
    );
    extrait = File(fichier.path.replaceFirst(RegExp(r'\.sf2$'), '.wav'))
      ..writeAsBytesSync(
        ExportMusical().versWav(_son, frequence: frequenceExtrait),
      );

    rms = _rms(programme);
  }

  /// RMS sur 0,75 s d'une note à vélocité 60, au do central s'il est dans
  /// l'ambitus, au centre de l'ambitus sinon — la mesure de
  /// `mesure_poids.dart`, sur la sonorité seule.
  double _rms(int programme) {
    final Synthesizer synth = Synthesizer.loadByteData(
      _vue,
      SynthesizerSettings(
        sampleRate: 44100,
        blockSize: 64,
        maximumPolyphony: 64,
        enableReverbAndChorus: true,
      ),
    );
    final int cle = (ambitus.$1 <= 60 && 60 <= ambitus.$2)
        ? 60
        : (ambitus.$1 + ambitus.$2) ~/ 2;

    synth.processMidiMessage(
      channel: 0,
      command: 0xC0,
      data1: programme,
      data2: 0,
    );
    const int points = 33075;
    final ArrayInt16 tampon = ArrayInt16.zeros(numShorts: points);
    synth.noteOn(channel: 0, key: cle, velocity: 60);
    synth.renderMonoInt16(tampon, offset: 0, length: points);
    double somme = 0;
    for (int i = 0; i < points; i++) {
      final int v = tampon[i] as int;
      somme += v * v;
    }
    return math.sqrt(somme / points);
  }

  Map<String, Object?> manifeste() => {
    'fichier': fichier.uri.pathSegments.last,
    'octets': octets,
    'extrait': extrait.uri.pathSegments.last,
    'rms': double.parse(rms.toStringAsFixed(1)),
  };
}

/// La phrase témoin : do mi sol do, sol mi do — arpège montant puis
/// redescente, une blanche pour finir. Quatre secondes à 120, plus la
/// seconde de résonance que le rendu ajoute.
Melodie _phrase(int programme) => Melodie(
  titre: 'témoin',
  source: '',
  tempo: 120,
  instrumentMidi: programme,
  mesures: [
    Mesure(
      notes: [
        Note(hauteur: 60, duree: 1.0, position: 0.0),
        Note(hauteur: 64, duree: 1.0, position: 1.0),
        Note(hauteur: 67, duree: 1.0, position: 2.0),
        Note(hauteur: 72, duree: 1.0, position: 3.0),
      ],
      duree: 4.0,
    ),
    Mesure(
      notes: [
        Note(hauteur: 67, duree: 1.0, position: 0.0),
        Note(hauteur: 64, duree: 1.0, position: 1.0),
        Note(hauteur: 60, duree: 2.0, position: 2.0),
      ],
      duree: 4.0,
    ),
  ],
);
