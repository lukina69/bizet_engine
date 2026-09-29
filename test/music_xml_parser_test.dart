import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:bizet_engine/bizet_engine.dart';
import 'package:test/test.dart';

void main() {
  Uint8List xml(String texte) => Uint8List.fromList(utf8.encode(texte));

  /// Une partition d'une partie, dont on donne le corps des mesures.
  Uint8List partition(String mesures, {String entete = ''}) => xml('''
    <?xml version="1.0" encoding="UTF-8"?>
    <score-partwise version="4.0">
      $entete
      <part-list>
        <score-part id="P1"><part-name>Musique</part-name></score-part>
      </part-list>
      <part id="P1">$mesures</part>
    </score-partwise>
  '''
      .trim());

  String note(String pas, int octave, int duree,
          {String extras = '', int? alter}) =>
      '<note><pitch><step>$pas</step>'
      '${alter == null ? '' : '<alter>$alter</alter>'}'
      '<octave>$octave</octave></pitch>'
      '<duration>$duree</duration>$extras</note>';

  group('une partition simple se lit entière', () {
    late Melodie melodie;

    setUp(() {
      melodie = MusicXmlParser().parse(partition('''
        <measure number="1">
          <attributes>
            <divisions>2</divisions>
            <key><fifths>2</fifths><mode>major</mode></key>
            <time><beats>3</beats><beat-type>4</beat-type></time>
          </attributes>
          <direction><sound tempo="88"/></direction>
          ${note('D', 4, 2)}
          ${note('F', 4, 2, alter: 1)}
          ${note('A', 4, 2)}
        </measure>
        <measure number="2">
          ${note('D', 5, 6)}
        </measure>
      ''', entete: '''
        <work><work-title>Petite marche</work-title></work>
        <identification>
          <creator type="composer">C. Testeur</creator>
        </identification>
      '''));
    });

    test('titre, compositeur, tempo et armure écrits noir sur blanc', () {
      expect(melodie.titre, 'Petite marche');
      expect(melodie.source, 'C. Testeur');
      expect(melodie.tempo, 88);
      expect(melodie.armure!.tonique, 2, reason: 'deux dièses : ré majeur');
      expect(melodie.armure!.majeur, isTrue);
    });

    test('les mesures suivent la signature, les notes leur place', () {
      expect(melodie.mesures.length, 2);
      expect(melodie.mesures.first.duree, 3.0);
      final List<Note> premiere = melodie.mesures.first.notes;
      expect(premiere.map((n) => n.hauteur), [62, 66, 69]);
      expect(premiere[1].position, closeTo(1.0, 1e-9));
      expect(melodie.mesures.last.notes.single.duree, closeTo(3.0, 1e-9));
    });
  });

  test('le titre du fichier prime, le nom du fichier ne sert qu\'à défaut',
      () {
    final Uint8List sansTitre = partition(
        '<measure number="1"><attributes><divisions>1</divisions></attributes>'
        '${note('C', 4, 4)}</measure>');
    expect(MusicXmlParser().parse(sansTitre, titre: 'mon-fichier').titre,
        'mon-fichier');
  });

  test('un accord sonne d\'un coup, sans avancer deux fois', () {
    final Melodie melodie = MusicXmlParser().parse(partition('''
      <measure number="1">
        <attributes><divisions>1</divisions></attributes>
        ${note('C', 4, 2)}
        ${note('E', 4, 2, extras: '<chord/>')}
        ${note('G', 4, 2)}
      </measure>
    '''));
    final List<Note> notes = melodie.mesures.single.notes;
    expect(notes.map((n) => n.hauteur), [60, 64, 67]);
    expect(notes[1].position, 0.0, reason: 'l\'accord partage son instant');
    expect(notes[2].position, closeTo(2.0, 1e-9));
  });

  test('backup : une seconde voix s\'écrit en revenant en arrière', () {
    final Melodie melodie = MusicXmlParser().parse(partition('''
      <measure number="1">
        <attributes><divisions>1</divisions></attributes>
        ${note('E', 5, 4)}
        <backup><duration>4</duration></backup>
        ${note('C', 3, 2)}
        ${note('G', 3, 2)}
      </measure>
    '''));
    final List<Note> notes = melodie.mesures.single.notes;
    expect(notes.length, 3);
    expect(notes.where((n) => n.position == 0.0).map((n) => n.hauteur),
        containsAll([76, 48]));
  });

  test('une liaison de tenue fait une seule note, même à cheval', () {
    final Melodie melodie = MusicXmlParser().parse(partition('''
      <measure number="1">
        <attributes><divisions>1</divisions>
          <time><beats>4</beats><beat-type>4</beat-type></time></attributes>
        ${note('C', 4, 2)}
        ${note('G', 4, 2, extras: '<tie type="start"/>')}
      </measure>
      <measure number="2">
        ${note('G', 4, 2, extras: '<tie type="stop"/>')}
        ${note('C', 4, 2)}
      </measure>
    '''));
    final Note tenue = melodie.mesures.first.notes.last;
    expect(tenue.hauteur, 67);
    expect(tenue.duree, closeTo(4.0, 1e-9),
        reason: 'deux blanches liées font une ronde');
    expect(melodie.mesures.last.notes.map((n) => n.hauteur), [60],
        reason: 'la note liée n\'est pas refrappée');
  });

  test('les silences comptent dans le temps sans devenir des notes', () {
    final Melodie melodie = MusicXmlParser().parse(partition('''
      <measure number="1">
        <attributes><divisions>1</divisions></attributes>
        <note><rest/><duration>2</duration></note>
        ${note('C', 4, 2)}
      </measure>
    '''));
    final Note seule = melodie.mesures.single.notes.single;
    expect(seule.position, closeTo(2.0, 1e-9));
  });

  test('une levée garde sa vraie longueur de mesure', () {
    final Melodie melodie = MusicXmlParser().parse(partition('''
      <measure number="0" implicit="yes">
        <attributes><divisions>1</divisions>
          <time><beats>4</beats><beat-type>4</beat-type></time></attributes>
        ${note('G', 4, 1)}
      </measure>
      <measure number="1">
        ${note('C', 5, 4)}
      </measure>
    '''));
    expect(melodie.mesures.first.duree, closeTo(1.0, 1e-9));
    expect(melodie.mesures.last.notes.single.position, closeTo(0.0, 1e-9));
  });

  test('deux parties se fondent en un seul morceau', () {
    final Melodie melodie = MusicXmlParser().parse(xml('''
      <score-partwise version="4.0">
        <part-list>
          <score-part id="P1"><part-name>Chant</part-name>
            <midi-instrument id="P1-I1"><midi-program>74</midi-program>
            </midi-instrument>
          </score-part>
          <score-part id="P2"><part-name>Basse</part-name></score-part>
        </part-list>
        <part id="P1">
          <measure number="1">
            <attributes><divisions>1</divisions></attributes>
            ${note('E', 5, 4)}
          </measure>
        </part>
        <part id="P2">
          <measure number="1">
            <attributes><divisions>2</divisions></attributes>
            ${note('C', 3, 4)}
            ${note('G', 3, 4)}
          </measure>
        </part>
      </score-partwise>
    '''));
    // Les divisions diffèrent d'une partie à l'autre : quatre unités valent
    // ici une ronde, là une blanche.
    final List<Note> notes = melodie.mesures.single.notes;
    expect(notes.length, 3);
    expect(notes.firstWhere((n) => n.hauteur == 55).position,
        closeTo(2.0, 1e-9));
    expect(melodie.instrumentMidi, 73,
        reason: 'MusicXML compte de 1 à 128, le moteur de 0 à 127');
  });

  test('le conteneur .mxl se déballe et se lit', () {
    final Uint8List nue = partition(
        '<measure number="1"><attributes><divisions>1</divisions></attributes>'
        '${note('C', 4, 4)}</measure>');
    final Archive archive = Archive()
      ..add(ArchiveFile.bytes(
          'META-INF/container.xml',
          utf8.encode('<?xml version="1.0"?><container><rootfiles>'
              '<rootfile full-path="partition.xml"/>'
              '</rootfiles></container>')))
      ..add(ArchiveFile.bytes('partition.xml', nue));
    final Uint8List mxl =
        Uint8List.fromList(ZipEncoder().encodeBytes(archive));

    expect(MusicXmlParser().parse(mxl).mesures.single.notes.single.hauteur,
        60);
  });

  group('les fichiers refusés le sont clairement', () {
    test('pas du XML', () {
      expect(
          () => MusicXmlParser().parse(xml('des notes sur un papier')),
          throwsFormatException);
    });

    test('du XML qui n\'est pas une partition', () {
      expect(() => MusicXmlParser().parse(xml('<recette><oeufs/></recette>')),
          throwsFormatException);
    });

    test('la variante mesure par mesure (timewise)', () {
      expect(
          () => MusicXmlParser()
              .parse(xml('<score-timewise version="4.0"></score-timewise>')),
          throwsFormatException);
    });

    test('une partition sans aucune note', () {
      expect(
          () => MusicXmlParser().parse(partition(
              '<measure number="1"><attributes><divisions>1</divisions>'
              '</attributes><note><rest/><duration>4</duration></note>'
              '</measure>')),
          throwsFormatException);
    });
  });
}
