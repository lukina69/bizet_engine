import 'dart:io';

import 'package:test/test.dart';

import 'package:bizet_engine/bizet_engine.dart';

void main() {
  final parser = LilypondParser();

  Melodie p(String source) => parser.parse(source);

  List<int> hauteurs(Melodie m) =>
      [for (final mes in m.mesures) ...mes.notes.map((n) => n.hauteur)];

  group('LilypondParser — hauteurs', () {
    test('gamme de do majeur en mode relatif', () {
      final m = p(r"melodie = \relative c' { c4 d e f g a b c }");
      expect(hauteurs(m), [60, 62, 64, 65, 67, 69, 71, 72]);
    });

    test('mode absolu (sans \\relative)', () {
      final m = p("melodie = { c'4 e' g' }");
      expect(hauteurs(m), [60, 64, 67]);
    });

    test('altérations : dièses et bémols', () {
      // fis = fa dièse, bes = si bémol, as = la bémol, es = mi bémol.
      final m = p(r"melodie = \relative c' { fis4 bes as es }");
      expect(hauteurs(m), [66, 70, 68, 63]);
    });

    test("marques d'octave en mode relatif", () {
      final m = p(r"melodie = \relative c' { c c' c, }");
      expect(hauteurs(m), [60, 72, 60]);
    });

    test('le mode relatif choisit toujours la note la plus proche', () {
      // g est à une quinte au-dessus de do mais une quarte en dessous :
      // c'est l'intervalle le plus court qui gagne (sol grave, MIDI 55).
      final m = p(r"melodie = \relative c' { g4 a b c }");
      expect(hauteurs(m), [55, 57, 59, 60]);
    });
  });

  group('LilypondParser — durées et mesures', () {
    test('héritage des durées et notes pointées', () {
      final m = p(r"melodie = \relative c' { c4. d8 e2 f }");
      final durees = [
        for (final mes in m.mesures) ...mes.notes.map((n) => n.duree)
      ];
      expect(durees, [1.5, 0.5, 2.0, 2.0]);
      // La blanche héritée déborde sur une seconde mesure.
      expect(m.mesures.length, 2);
    });

    test('les silences décalent les notes suivantes', () {
      final m = p(r"melodie = \relative c' { c4 r2 d4 }");
      expect(m.mesures.length, 1);
      expect(m.mesures.first.notes.length, 2);
      expect(m.mesures.first.notes.last.position, 3.0);
    });

    test('signature 3/4 dans la voix : mesures de trois temps', () {
      final m = p(r"melodie = { \time 3/4 c'4 d' e' f' g' a' }");
      expect(m.mesures.length, 2);
      expect(m.mesures.map((mes) => mes.duree), [3.0, 3.0]);
      expect(m.mesures.last.notes.first.position, 0.0);
    });

    test('signature déclarée hors de la voix (variable global)', () {
      final m = p(r'''
global = { \time 3/4 s2.*2 }
melodie = \relative c' { c4 d e f g a }
''');
      expect(m.mesures.length, 2);
      expect(m.mesures.first.duree, 3.0);
    });

    test('un silence final crée une mesure vide', () {
      final m = p(r"melodie = \relative c' { c1 r1 }");
      expect(m.mesures.length, 2);
      expect(m.mesures.last.notes, isEmpty);
      expect(m.mesures.last.duree, 4.0);
    });
  });

  group('LilypondParser — tempo et entête', () {
    test('tempo à la noire', () {
      final m = p("\\tempo 4 = 110  melodie = { c'4 }");
      expect(m.tempo, 110);
    });

    test('tempo à la blanche, converti à la noire', () {
      final m = p("\\tempo 2 = 54  melodie = { c'4 }");
      expect(m.tempo, 108);
    });

    test('tempo absent : 120 par défaut', () {
      expect(p("melodie = { c'4 }").tempo, 120);
    });

    test("titre et attribution tirés de l'entête", () {
      final m = p(r'''
\header {
  title = "Petit air"
  composer = "G. Bizet"
  maintainer = "Ludo"
  license = "Public Domain"
  mutopiacomposer = "BizetG"
}
melodie = \relative c' { c4 }
''');
      expect(m.titre, 'Petit air');
      expect(m.source, contains('G. Bizet'));
      expect(m.source, contains('Mutopia Project'));
      expect(m.source, contains('typographie : Ludo'));
      expect(m.source, contains('Public Domain'));
    });
  });

  group('LilypondParser — sélection de la voix', () {
    test('ignore les variables sans notes et les paroles', () {
      // "re mi fa" ressemble à des notes mais ce sont des paroles.
      final m = p(r'''
text = \lyricmode { re mi fa }
global = { s1 }
melodie = \relative c' { g4 a b c }
''');
      expect(hauteurs(m), [55, 57, 59, 60]);
    });

    test('passe à la voix suivante si la première est muette', () {
      final m = p(r'''
percus = { r1 r1 }
melodie = \relative c' { c4 d e f }
''');
      expect(hauteurs(m), [60, 62, 64, 65]);
    });
  });

  group('LilypondParser — accords', () {
    test("trois notes à la même position, la durée après l'accord", () {
      final m = p(r"melodie = { <c' e' g'>2 c'2 }");
      final notes = m.mesures.single.notes;
      expect(notes.map((n) => n.hauteur), [60, 64, 67, 60]);
      expect(notes.map((n) => n.position), [0.0, 0.0, 0.0, 2.0]);
      expect(notes.every((n) => n.duree == 2.0), isTrue);
    });

    test("mode relatif : la référence suivante est la première de l'accord",
        () {
      // Le sol de l'accord est au-dessus, mais le do suivant s'accroche au
      // do de l'accord, pas au sol (règle LilyPond).
      final m = p(r"melodie = \relative c' { <c e g>2 c2 }");
      expect(hauteurs(m), [60, 64, 67, 60]);
    });

    test("l'accord hérite sa durée et la transmet", () {
      final m = p(r"melodie = { c'8 <d' f'> e' }");
      final durees = [
        for (final mes in m.mesures) ...mes.notes.map((n) => n.duree)
      ];
      expect(durees, [0.5, 0.5, 0.5, 0.5]);
    });
  });

  group('LilypondParser — répétitions déroulées', () {
    test(r'\repeat volta avec \alternative', () {
      final m = p(
          r"melodie = { \repeat volta 2 { c'4 d' } \alternative { { e'2 } { g'2 } } }");
      expect(hauteurs(m), [60, 62, 64, 60, 62, 67]);
    });

    test(r'\repeat unfold sans alternative', () {
      final m = p(r"melodie = { \repeat unfold 3 { c'4 d' } }");
      expect(hauteurs(m), [60, 62, 60, 62, 60, 62]);
    });

    test('le mode relatif traverse la répétition comme LilyPond', () {
      // Déroulé : c' g c g — le sol reste sous le do, et le second passage
      // repart du sol précédent, pas du début.
      final m = p(r"melodie = \relative c' { \repeat unfold 2 { c4 g } }");
      expect(hauteurs(m), [60, 55, 60, 55]);
    });
  });

  group('LilypondParser — triolets', () {
    test(r'\tuplet 3/2 : trois croches dans le temps de deux', () {
      final m = p(r"melodie = { \tuplet 3/2 { c'8 d' e' } f'4 }");
      final notes = m.mesures.single.notes;
      expect(notes.map((n) => n.duree.toStringAsFixed(4)),
          ['0.3333', '0.3333', '0.3333', '1.0000']);
      expect(notes.last.position, closeTo(1.0, 1e-9));
    });

    test(r'\times 2/3 : même effet, fraction inversée', () {
      final m = p(r"melodie = { \times 2/3 { c'8 d' e' } f'4 }");
      expect(m.mesures.single.notes.last.position, closeTo(1.0, 1e-9));
    });
  });

  group('LilypondParser — voix parallèles', () {
    test('deux voix fusionnées, chacune partant du même instant', () {
      final m = p(r"melodie = { << { c'2 d'2 } \\ { e'1 } >> g'1 }");
      expect(m.mesures.length, 2);
      final premiere = m.mesures.first.notes;
      expect(premiere.map((n) => n.hauteur), [60, 64, 62]);
      expect(premiere.map((n) => n.position), [0.0, 0.0, 2.0]);
      // Le sol vient après le <<...>> entier, dans la mesure suivante.
      expect(m.mesures.last.notes.single.hauteur, 67);
    });

    test('la voix la plus longue donne la durée de l\'ensemble', () {
      final m = p(r"melodie = { << { c'4 } \\ { e'1 } >> g'4 }");
      // Le sol part après la ronde, pas après la noire.
      expect(m.mesures.last.notes.single.position, 0.0);
      expect(m.mesures.length, 2);
    });

    test(r'\relative imbriqué dans une voix parallèle', () {
      final m = p(r"melodie = { << \relative c'' { c4 } \\ { c4 } >> }");
      expect(hauteurs(m), [72, 48]);
    });
  });

  group('LilypondParser — blocs \\parallelMusic', () {
    // L'écriture entrelacée de LilyPond : les barres se distribuent une à
    // une entre les voix listées, puis chaque voix devient une variable.
    // La Bourrée en mi mineur de Bach (BWV 996) est écrite ainsi, et se
    // lisait de travers sans rien dire : quelques notes fantaisistes.
    test('les barres se distribuent une à une entre les voix', () {
      final Melodie m = LilypondParser().parse(r"""
        \parallelMusic #'(haut bas) {
          c'4 d' e' f' |
          c2 g |
          g'4 f' e' d' |
          e2 c |
        }
        \score { << \new Staff { \haut } \new Staff { \bas } >> }
      """);
      expect(m.mesures.length, 2);
      // Première mesure : la première barre au chant, la deuxième à la basse.
      final List<int> hauteurs =
          m.mesures.first.notes.map((n) => n.hauteur).toList()..sort();
      expect(hauteurs, [48, 55, 60, 62, 64, 65]);
    });

    test('une barre de fin dans une chaîne ne coupe pas la distribution', () {
      final Melodie m = LilypondParser().parse(r"""
        \parallelMusic #'(haut bas) {
          c'4 d' e' f' \bar "|." |
          c1 |
        }
        \score { << \new Staff { \haut } \new Staff { \bas } >> }
      """);
      expect(m.mesures.single.notes.length, 5);
    });

    test('un accent -> ou un soufflet ne comptent pas comme un accord', () {
      final Melodie m = LilypondParser().parse(r"""
        \parallelMusic #'(haut bas) {
          c'4-> d'\< e' f'\! |
          <c e>2 g |
        }
        \score { << \new Staff { \haut } \new Staff { \bas } >> }
      """);
      expect(m.mesures.single.notes.length, 7);
    });
  });

  group('LilypondParser — langues de notes', () {
    test(r'\language "deutsch" : h = si bécarre, b = si bémol', () {
      final m = p(r'''
\language "deutsch"
melodie = { h'4 b' fis' }
''');
      expect(hauteurs(m), [71, 70, 66]);
    });

    test(r'\language "english" : cs = do dièse, df = ré bémol', () {
      final m = p("\\language \"english\"\nmelodie = { cs'4 df' }");
      expect(hauteurs(m), [61, 61]);
    });

    test(r'\language "italiano" : dod = do dièse, sib = si bémol', () {
      final m = p("\\language \"italiano\"\nmelodie = { dod'4 sib }");
      expect(hauteurs(m), [61, 58]);
    });

    test(r'\include "deutsch.ly" vaut \language (ancienne syntaxe)', () {
      final m = p("\\include \"deutsch.ly\"\nmelodie = { h'4 }");
      expect(hauteurs(m), [71]);
    });
  });

  group('LilypondParser — assemblage par le \\score', () {
    test('les variables référencées dans le score sont déroulées', () {
      final m = p(r'''
melodie = \relative c' { c4 d e f }
basse = { c1 }
\score { << \new Staff \melodie \new Staff \basse >> }
''');
      expect(m.mesures.length, 1);
      // Les notes des deux portées s'entrelacent chronologiquement.
      expect(hauteurs(m), [60, 48, 62, 64, 65]);
      final basse =
          m.mesures.first.notes.firstWhere((n) => n.hauteur == 48);
      expect(basse.position, 0.0);
      expect(basse.duree, 4.0);
    });

    test('une variable de réglages (\\time) profite à tout le morceau', () {
      final m = p(r'''
global = { \time 3/4 }
melodie = { \global c'4 d' e' f' g' a' }
\score { \new Staff \melodie }
''');
      expect(m.mesures.length, 2);
      expect(m.mesures.first.duree, 3.0);
    });

    test('les paroles du score ne deviennent pas des notes', () {
      final m = p(r'''
melodie = { c'4 d' }
paroles = \lyricmode { la la }
\score { << \new Voice = "v" \melodie \new Lyrics \lyricsto "v" \paroles >> }
''');
      expect(hauteurs(m), [60, 62]);
    });
  });

  group('LilypondParser — transposition écrite', () {
    test(r"\transpose do fa : la musique monte d'une quarte", () {
      final m = p(r"melodie = { \transpose c f { c'4 d' } g'4 }");
      // Le sol qui suit le bloc n'est pas transposé.
      expect(hauteurs(m), [65, 67, 67]);
    });
  });

  group('LilypondParser — rappel d\'accord q', () {
    test('q rejoue le dernier accord, avec sa propre durée', () {
      final m = p(r"melodie = { <c' e'>4 q2 }");
      final notes = m.mesures.single.notes;
      expect(notes.map((n) => n.hauteur), [60, 64, 60, 64]);
      expect(notes.last.duree, 2.0);
    });
  });

  group('LilypondParser — fichiers \\include', () {
    test('le contenu inclus est fourni par le résolveur', () {
      final m = LilypondParser().parse(
        '\\include "notes.ily"\n\\score { \\melodie }',
        inclure: (nom) =>
            nom == 'notes.ily' ? "melodie = { c'4 d' }" : null,
      );
      expect(hauteurs(m), [60, 62]);
    });

    test('un fichier inclus introuvable est refusé avec son nom', () {
      expect(
        () => p('\\include "perdu.ily"\nmelodie = { c4 }'),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('perdu.ily'))),
      );
    });
  });

  group('LilypondParser — hors périmètre refusé proprement', () {
    test('fichier sans musique refusé', () {
      expect(() => p(r'\header { title = "Vide" }'),
          throwsA(isA<FormatException>()));
    });

    test('accolade non refermée refusée', () {
      expect(() => p(r'melodie = { c4 d'), throwsA(isA<FormatException>()));
    });
  });

  group('LilypondParser — fichier Mutopia réel (Vocalise n°1, Abt)', () {
    late Melodie m;

    setUpAll(() {
      final source = File('test/fixtures/vocalise1.ly').readAsStringSync();
      m = parser.parse(source);
    });

    test('métadonnées : titre, tempo, attribution', () {
      expect(m.titre, 'Vocalise № 1');
      expect(m.tempo, 110);
      expect(m.source, contains('Franz Abt'));
      expect(m.source, contains('Mutopia Project'));
    });

    test('seize mesures de quatre temps', () {
      expect(m.mesures.length, 16);
      expect(m.mesures.every((mes) => mes.duree == 4.0), isTrue);
    });

    test('chant et piano fusionnés : la première phrase est là', () {
      // Le chant (mi blanche, ré blanche) et la basse du piano (do grave
      // tenu sur la ronde) jouent ensemble dès la première mesure.
      final premiere = m.mesures[0].notes;
      bool a(int hauteur, double position, double duree) => premiere.any(
          (n) => n.hauteur == hauteur && n.position == position && n.duree == duree);
      expect(a(64, 0.0, 2.0), isTrue, reason: 'mi du chant');
      expect(a(62, 2.0, 2.0), isTrue, reason: 'ré du chant');
      expect(a(36, 0.0, 4.0), isTrue, reason: 'do grave du piano');
    });

    test('le fa dièse de la mesure 7 est bien lu', () {
      final hauteursChant = m.mesures[6].notes
          .where((n) => n.hauteur >= 60)
          .map((n) => n.hauteur);
      expect(hauteursChant, containsAllInOrder([69, 67, 66]));
    });

    test('demi-pause du chant respectée : le mi s\'arrête au deuxième temps',
        () {
      final chant = m.mesures[3].notes
          .where((n) => n.hauteur == 64 && n.position == 0.0)
          .toList();
      expect(chant, isNotEmpty);
      expect(chant.first.duree, 2.0);
    });

    test('dernière mesure : tout le monde tient la ronde finale', () {
      expect(m.mesures[15].notes.every((n) => n.duree == 4.0), isTrue);
      expect(m.mesures[15].notes.map((n) => n.hauteur), contains(60));
    });
  });
}
