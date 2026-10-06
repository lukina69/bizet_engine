import 'package:test/test.dart';

import 'package:bizet_engine/bizet_engine.dart';

void main() {
  // Do majeur : la gamme part du do central (MIDI 60).
  const Armure doMajeur = Armure(tonique: 0, majeur: true);

  group('bascule majeur → mineur', () {
    test('la tierce, la sixte et la septième descendent d\'un demi-ton', () {
      // do ré mi fa sol la si → do ré mi♭ fa sol la♭ si♭
      const List<int> gamme = [60, 62, 64, 65, 67, 69, 71];
      const List<int> attendue = [60, 62, 63, 65, 67, 68, 70];

      expect(
        [for (final h in gamme) doMajeur.versMode(h, false)],
        attendue,
      );
    });

    test('les autres degrés ne bougent pas, même altérés', () {
      // Un do dièse de passage reste un do dièse : on ne réécrit pas le
      // morceau, on ne touche que ce qui fait l'humeur.
      for (final int hauteur in [61, 66, 68, 70]) {
        expect(doMajeur.versMode(hauteur, false), hauteur, reason: '$hauteur');
      }
    });

    test('la bascule vaut à toutes les octaves', () {
      // La tierce de do est un mi, à l'octave grave comme à l'aiguë.
      for (final int mi in [40, 52, 64, 76, 88]) {
        expect(doMajeur.versMode(mi, false), mi - 1, reason: '$mi');
      }
    });

    test('demander le mode qu\'on a déjà ne change rien', () {
      for (int h = 48; h < 72; h++) {
        expect(doMajeur.versMode(h, true), h);
      }
    });
  });

  group('bascule mineur → majeur', () {
    // La mineur : la tonique est un la, classe de hauteur 9.
    const Armure laMineur = Armure(tonique: 9, majeur: false);

    test('la tierce, la sixte et la septième montent d\'un demi-ton', () {
      // la si do ré mi fa sol → la si do♯ ré mi fa♯ sol♯
      const List<int> gamme = [69, 71, 72, 74, 76, 77, 79];
      const List<int> attendue = [69, 71, 73, 74, 76, 78, 80];

      expect(
        [for (final h in gamme) laMineur.versMode(h, true)],
        attendue,
      );
    });

    test('une tonique haut placée ne fausse pas le calcul des degrés', () {
      // Le do au-dessus du la : le degré se compte modulo l'octave, sans
      // jamais devenir négatif.
      expect(laMineur.versMode(60, true), 61, reason: 'do grave, sous la');
      expect(laMineur.versMode(72, true), 73, reason: 'do aigu, au-dessus');
    });
  });

  test('l\'armure se relit telle qu\'elle a été enregistrée', () {
    final relue = Armure.fromJson(
      const Armure(tonique: 7, majeur: false).toJson(),
    );
    expect(relue.tonique, 7);
    expect(relue.majeur, isFalse);
  });

  group('la tonalité devinée', () {
    /// Le portrait d'une suite de notes d'égale durée.
    List<double> portrait(List<int> hauteurs) {
      final List<double> durees = List.filled(12, 0);
      for (final int h in hauteurs) {
        durees[h % 12] += 1;
      }
      return durees;
    }

    test('une gamme de do majeur qui revient à do', () {
      final Armure a = Armure.devinee(
        portrait([60, 62, 64, 65, 67, 69, 71, 72, 67, 64, 60, 67, 60]),
      )!;
      expect(a.tonique, 0);
      expect(a.majeur, isTrue);
    });

    test('un air en la mineur, avec son sol dièse', () {
      final Armure a = Armure.devinee(
        portrait([69, 71, 72, 74, 76, 77, 80, 81, 76, 72, 69, 76, 69, 72]),
      )!;
      expect(a.tonique, 9);
      expect(a.majeur, isFalse);
    });

    test('transposer le morceau transpose la tonalité devinée', () {
      const List<int> air = [60, 62, 64, 65, 67, 69, 71, 72, 67, 64, 60];
      for (int ecart = 0; ecart < 12; ecart++) {
        final Armure a = Armure.devinee(
          portrait([for (final int h in air) h + ecart]),
        )!;
        expect(a.tonique, ecart, reason: 'écart $ecart');
        expect(a.majeur, isTrue, reason: 'écart $ecart');
      }
    });

    test('trop peu de notes différentes : on ne devine pas', () {
      expect(Armure.devinee(portrait([60, 64, 67, 60, 64])), isNull);
      expect(Armure.devinee(List.filled(12, 0)), isNull);
    });
  });
}
