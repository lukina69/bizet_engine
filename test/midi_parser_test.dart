import 'dart:typed_data';

import 'package:bizet_engine/bizet_engine.dart';
import 'package:test/test.dart';

/// Les fichiers de ces épreuves sont fabriqués octet par octet : c'est le seul
/// moyen d'éprouver les recoins du format (statut répété, fichiers tronqués)
/// qu'un fichier propre ne montrerait jamais.
void main() {
  /// La « quantité de longueur variable » du format.
  List<int> vlq(int v) {
    final List<int> octets = [v & 0x7F];
    int reste = v >> 7;
    while (reste > 0) {
      octets.insert(0, (reste & 0x7F) | 0x80);
      reste >>= 7;
    }
    return octets;
  }

  List<int> piste(List<int> evenements) {
    final List<int> corps = [...evenements, 0x00, 0xFF, 0x2F, 0x00];
    return [
      ...'MTrk'.codeUnits,
      (corps.length >> 24) & 0xFF,
      (corps.length >> 16) & 0xFF,
      (corps.length >> 8) & 0xFF,
      corps.length & 0xFF,
      ...corps,
    ];
  }

  Uint8List fichier(List<List<int>> pistes, {int format = 0, int division = 480}) =>
      Uint8List.fromList([
        ...'MThd'.codeUnits,
        0, 0, 0, 6,
        (format >> 8) & 0xFF, format & 0xFF,
        (pistes.length >> 8) & 0xFF, pistes.length & 0xFF,
        (division >> 8) & 0xFF, division & 0xFF,
        for (final p in pistes) ...p,
      ]);

  /// Une note : allumée maintenant, éteinte après [tics].
  List<int> note(int hauteur, int tics, {int canal = 0, int apres = 0}) => [
        ...vlq(apres), 0x90 | canal, hauteur, 80,
        ...vlq(tics), 0x80 | canal, hauteur, 0,
      ];

  group('un fichier simple se lit entier', () {
    // Tempo 100, signature 3/4, hautbois (programme 68), puis trois temps :
    // deux noires et une noire dans la mesure suivante.
    late Melodie melodie;

    setUp(() {
      melodie = MidiParser().parse(fichier([
        piste([
          0x00, 0xFF, 0x51, 0x03, 0x09, 0x27, 0xC0, // 600 000 µs par noire
          0x00, 0xFF, 0x58, 0x04, 3, 2, 24, 8, // 3/4
          0x00, 0xC0, 68,
          ...note(60, 480),
          ...note(62, 480),
          ...note(64, 480), // déborde dans la deuxième mesure
          ...note(65, 480),
        ]),
      ]));
    });

    test('tempo, instrument et découpe en mesures', () {
      expect(melodie.tempo, 100);
      expect(melodie.instrumentMidi, 68);
      expect(melodie.mesures.length, 2);
      expect(melodie.mesures.first.duree, 3.0);
      expect(melodie.mesures.first.notes.map((n) => n.hauteur), [60, 62, 64]);
      expect(melodie.mesures.last.notes.map((n) => n.hauteur), [65]);
    });

    test('positions et durées en noires', () {
      final Note troisieme = melodie.mesures.first.notes[2];
      expect(troisieme.position, closeTo(2.0, 1e-9));
      expect(troisieme.duree, closeTo(1.0, 1e-9));
      expect(melodie.mesures.last.notes.single.position, closeTo(0.0, 1e-9));
    });
  });

  test('le statut répété se lit comme un statut écrit', () {
    // Trois notes dont seules la première porte l'octet « note allumée » : la
    // façon la plus courante d'écrire un fichier MIDI réel.
    final Melodie melodie = MidiParser().parse(fichier([
      piste([
        0x00, 0x90, 60, 80,
        ...vlq(480), 60, 0, // éteinte par vélocité nulle, statut répété
        0x00, 62, 80,
        ...vlq(480), 62, 0,
        0x00, 64, 80,
        ...vlq(480), 64, 0,
      ]),
    ]));
    expect(
      [for (final m in melodie.mesures) ...m.notes.map((n) => n.hauteur)],
      [60, 62, 64],
    );
  });

  test('les pistes d\'un fichier de type 1 se fondent en un morceau', () {
    final Melodie melodie = MidiParser().parse(
      fichier(format: 1, [
        piste([0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]), // tempo 120
        piste(note(72, 960)),
        piste(note(48, 960, canal: 1)),
      ]),
    );
    expect(melodie.tempo, 120);
    final List<int> hauteurs =
        melodie.mesures.single.notes.map((n) => n.hauteur).toList()..sort();
    expect(hauteurs, [48, 72]);
  });

  test('le canal des percussions ne devient pas des notes', () {
    final Melodie melodie = MidiParser().parse(fichier([
      piste([
        ...note(60, 480),
        ...note(35, 480, canal: 9), // grosse caisse
      ]),
    ]));
    expect(melodie.mesures.single.notes.single.hauteur, 60);
  });

  group('l\'armure écrite dans le fichier', () {
    Melodie avecArmure(int alterations, int mode) => MidiParser().parse(
          fichier([
            piste([
              0x00, 0xFF, 0x59, 0x02, alterations & 0xFF, mode,
              ...note(60, 480),
            ]),
          ]),
        );

    test('deux dièses en majeur : ré majeur', () {
      final Armure armure = avecArmure(2, 0).armure!;
      expect(armure.tonique, 2);
      expect(armure.majeur, isTrue);
    });

    test('un bémol en mineur : ré mineur', () {
      final Armure armure = avecArmure(-1, 1).armure!;
      expect(armure.tonique, 2);
      expect(armure.majeur, isFalse);
    });

    test('sans armure écrite et avec trop peu de notes, rien n\'est deviné',
        () {
      expect(MidiParser().parse(fichier([piste(note(60, 480))])).armure,
          isNull);
    });

    test('sans armure écrite, elle se devine sur les notes', () {
      // « Au clair de la lune » en sol majeur, avec sa cadence.
      const List<int> air = [
        67, 67, 67, 69, 71, 69, 67, 71, 69, 69, 67, //
        69, 69, 69, 69, 64, 64, 69, 67, 66, 64, 62, //
        67, 67, 67, 69, 71, 69, 67, 71, 69, 69, 67,
      ];
      final Armure armure = MidiParser().parse(fichier([
        piste([for (final int h in air) ...note(h, 480)]),
      ])).armure!;
      expect(armure.tonique, 7);
      expect(armure.majeur, isTrue);
    });

    test('une armure écrite n\'est jamais remplacée par une devinée', () {
      // Les notes penchent vers do majeur, le fichier dit ré mineur : il
      // fait foi.
      final Armure armure = MidiParser().parse(fichier([
        piste([
          0x00, 0xFF, 0x59, 0x02, 0xFF, 1,
          for (final int h in [60, 62, 64, 65, 67, 69, 71, 72, 67, 64, 60])
            ...note(h, 480),
        ]),
      ])).armure!;
      expect(armure.tonique, 2);
      expect(armure.majeur, isFalse);
    });
  });

  group('le titre', () {
    final List<int> nommee = piste([
      0x00, 0xFF, 0x03, 7, ...'Bourree'.codeUnits,
      ...note(60, 480),
    ]);

    test('le nom donné par l\'appli prime', () {
      expect(MidiParser().parse(fichier([nommee]), titre: 'Mon fichier').titre,
          'Mon fichier');
    });

    test('à défaut, le nom écrit dans la première piste', () {
      expect(MidiParser().parse(fichier([nommee])).titre, 'Bourree');
    });
  });

  test('une note jamais éteinte s\'arrête à la fin de la piste', () {
    final Melodie melodie = MidiParser().parse(fichier([
      piste([
        0x00, 0x90, 60, 80,
        ...vlq(960), 0xFF, 0x01, 0x00, // du texte, pour faire avancer le temps
      ]),
    ]));
    expect(melodie.mesures.first.notes.single.duree, closeTo(2.0, 1e-9));
  });

  group('les fichiers refusés le sont clairement', () {
    test('pas un fichier MIDI', () {
      expect(() => MidiParser().parse(Uint8List.fromList('bonjour'.codeUnits)),
          throwsFormatException);
    });

    test('type 2, pistes indépendantes', () {
      expect(() => MidiParser().parse(fichier(format: 2, [piste(note(60, 480))])),
          throwsFormatException);
    });

    test('temps compté en images vidéo (SMPTE)', () {
      expect(
          () => MidiParser()
              .parse(fichier(division: 0xE250, [piste(note(60, 480))])),
          throwsFormatException);
    });

    test('fichier tronqué au milieu d\'une piste', () {
      final Uint8List entier = fichier([piste(note(60, 480))]);
      expect(
          () => MidiParser()
              .parse(entier.sublist(0, entier.length - 6)),
          throwsFormatException);
    });

    test('aucune note', () {
      expect(
          () => MidiParser()
              .parse(fichier([piste([0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20])])),
          throwsFormatException);
    });
  });

  test('ce que l\'écrivain MIDI écrit, le lecteur le relit', () {
    // La boucle complète : la mélodie exportée par l'appli doit pouvoir se
    // réimporter telle quelle, aux réglages neutres.
    final Melodie origine = Melodie(
      titre: 'Boucle',
      source: '',
      tempo: 90,
      instrumentMidi: 24,
      mesures: [
        Mesure(notes: [
          Note(hauteur: 64, duree: 1.0, position: 0.0),
          Note(hauteur: 67, duree: 0.5, position: 1.0),
          Note(hauteur: 69, duree: 2.5, position: 1.5),
        ], duree: 4.0),
        Mesure(notes: [
          Note(hauteur: 72, duree: 4.0, position: 0.0),
        ], duree: 4.0),
      ],
    );
    final Melodie relue = MidiParser()
        .parse(ExportMusical().versMidi(origine), titre: 'Boucle');

    expect(relue.tempo, 90);
    expect(relue.mesures.length, 2);
    for (int m = 0; m < 2; m++) {
      final List<Note> avant = origine.mesures[m].notes;
      final List<Note> apres = relue.mesures[m].notes;
      expect(apres.length, avant.length);
      for (int n = 0; n < avant.length; n++) {
        expect(apres[n].hauteur, avant[n].hauteur);
        expect(apres[n].position, closeTo(avant[n].position, 1e-3));
        expect(apres[n].duree, closeTo(avant[n].duree, 1e-3));
      }
    }
  });
}
