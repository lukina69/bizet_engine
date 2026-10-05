import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bizet_engine/bizet_engine.dart';
import 'package:dart_melty_soundfont/dart_melty_soundfont.dart' show ArrayInt16;
import 'package:test/test.dart';

final File _banque = File('../bizet/assets/soundfonts/Bizet_socle.sf2');

RenduAudio _rendu() {
  final Uint8List o = _banque.readAsBytesSync();
  return RenduAudio()..chargerSoundFont(ByteData.view(o.buffer));
}

/// Huit mesures : des notes courtes, et une longue tenue qui traverse le
/// milieu du morceau, là où l'on viendra se placer.
Melodie _morceau() => Melodie(
  titre: '',
  source: '',
  tempo: 120,
  instrumentMidi: 40,
  mesures: [
    for (int m = 0; m < 3; m++)
      Mesure(
        notes: [
          for (int i = 0; i < 4; i++)
            Note(hauteur: 60 + i, duree: 1.0, position: i.toDouble()),
        ],
        duree: 4.0,
      ),
    Mesure(notes: [Note(hauteur: 67, duree: 8.0, position: 0.0)], duree: 4.0),
    Mesure(notes: const [], duree: 4.0),
    for (int m = 0; m < 3; m++)
      Mesure(
        notes: [
          for (int i = 0; i < 4; i++)
            Note(hauteur: 64 - i, duree: 1.0, position: i.toDouble()),
        ],
        duree: 4.0,
      ),
  ],
);

List<int> _echantillons(ArrayInt16 t) => [
  for (int i = 0; i < t.bytes.lengthInBytes ~/ 2; i++)
    t.bytes.getInt16(i * 2, Endian.little),
];

double _efficace(List<int> v) =>
    math.sqrt(v.fold<double>(0, (s, x) => s + x * x) / math.max(1, v.length));

void main() {
  const Reglages reglages = Reglages(tempo: 120, voix: [Voix(instrument: 40)]);

  test('fabriqué par tranches depuis le début, le son est identique', () {
    final List<int> entier = _echantillons(
      _rendu().rendre(_morceau(), reglages: reglages),
    );

    final RenduProgressif progressif = _rendu().commencer(
      _morceau(),
      reglages: reglages,
    );
    expect(progressif.debut, 0);
    final List<int> morceaux = [];
    // Des tranches de tailles inégales, comme l'appli les demandera.
    for (final int longueur in [4410, 22050, 1000, 88200]) {
      morceaux.addAll(_echantillons(progressif.suivante(longueur)));
    }
    while (!progressif.fini) {
      morceaux.addAll(_echantillons(progressif.suivante(44100)));
    }
    expect(morceaux, entier);
  });

  test('partir du milieu garde la note tenue, et rejoint le rendu entier', () {
    final List<int> entier = _echantillons(
      _rendu().rendre(_morceau(), reglages: reglages),
    );

    // Au milieu de la longue tenue : mesure 4, deux temps après son début.
    const int frequence = RenduAudio.frequence;
    final int depuis = ((12 + 2) * 0.5 * frequence).round();
    final RenduProgressif progressif = _rendu().commencer(
      _morceau(),
      reglages: reglages,
      depuis: depuis,
    );
    expect(progressif.debut, depuis - frequence, reason: 'une seconde d\'élan');

    final List<int> suite = [];
    while (!progressif.fini) {
      suite.addAll(_echantillons(progressif.suivante(44100)));
    }
    List<int> fenetre(List<int> v, int a, int n) => v.sublist(a, a + n);

    // À l'endroit demandé, la tenue sonne déjà.
    final int ici = depuis - progressif.debut;
    expect(
      _efficace(fenetre(suite, ici, 4410)),
      greaterThan(100),
      reason: 'la note tenue n\'est pas coupée',
    );

    // Deux secondes plus loin, sur les notes suivantes, on retrouve le rendu
    // entier à quelques pour cent près : seule la réverbération d'avant
    // l'élan manque.
    final int loin = depuis + 6 * frequence;
    final double vrai = _efficace(fenetre(entier, loin, frequence));
    final double approche = _efficace(
      fenetre(suite, loin - progressif.debut, frequence),
    );
    expect(approche, closeTo(vrai, vrai * 0.1));
  });

  test('un nouveau rendu invalide le précédent', () {
    final RenduAudio rendu = _rendu();
    final RenduProgressif premier = rendu.commencer(
      _morceau(),
      reglages: reglages,
    );
    premier.suivante(1000);
    rendu.commencer(_morceau(), reglages: reglages);
    expect(() => premier.suivante(1000), throwsStateError);
  });
}
