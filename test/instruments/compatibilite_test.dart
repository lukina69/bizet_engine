import 'package:bizet_engine/bizet_engine.dart';
import 'package:test/test.dart';

/// Les seuils de la règle (7 demi-tons, 75 %, frontières de registre) sont
/// des valeurs de départ, à ajuster à l'oreille. Ces tests épinglent donc des
/// **verdicts connus**, pas les seuils : un réglage ultérieur reste
/// vérifiable — si une paire épinglée bascule, c'est un choix à assumer, pas
/// un accident.
void main() {
  Instrument par(int programme) => instrumentParProgramme(programme)!;

  group('paires épinglées', () {
    test('un son qui s\'éteint sur un son qui se tient : conseillé', () {
      // Guitare nylon + flûte.
      expect(evaluer(par(24), par(73)), Compatibilite.conseille);
      // Harpe + flûte.
      expect(evaluer(par(46), par(73)), Compatibilite.conseille);
      // Clavecin + violon.
      expect(evaluer(par(6), par(40)), Compatibilite.conseille);
    });

    test('rien à signaler : neutre', () {
      // Célesta + cordes pizzicato : deux sons qui s'éteignent — la règle des
      // enveloppes opposées ne s'applique pas. Le document de passation
      // attendait « conseillé » ; décision du 4 août 2026 : la règle prime.
      expect(evaluer(par(8), par(45)), Compatibilite.neutre);
      // Trompette + tuba : même famille, mais registres bien séparés.
      expect(evaluer(par(56), par(58)), Compatibilite.neutre);
      // Violon + violoncelle : même famille, recouvrement partiel seulement.
      expect(evaluer(par(40), par(42)), Compatibilite.neutre);
    });

    test('double emploi ou tessitures étrangères : inattendu', () {
      // Célesta + boîte à musique : la boîte à musique vit entièrement dans
      // la tessiture du célesta.
      expect(evaluer(par(8), par(10)), Compatibilite.inattendu);
      // Violon + cordes trémolo : des cordes frottées sur des cordes
      // frottées.
      expect(evaluer(par(40), par(44)), Compatibilite.inattendu);
      // Contrebasse jazz + contrebasse à l'archet : deux graves.
      expect(evaluer(par(32), par(43)), Compatibilite.inattendu);
      // Tuba + boîte à musique : aucune note en commun.
      expect(evaluer(par(58), par(10)), Compatibilite.inattendu);
    });
  });

  test('le verdict ne dépend pas de l\'ordre de la paire', () {
    for (final Instrument a in catalogue) {
      for (final Instrument b in catalogue) {
        expect(evaluer(a, b), evaluer(b, a),
            reason: '${a.nom} / ${b.nom}');
      }
    }
  });

  group('evaluerContre', () {
    test('retient le pire des verdicts, pas la moyenne', () {
      // La flûte va bien avec la guitare nylon (conseillé), mais n'a presque
      // aucune note en commun avec le tuba (inattendu) : c'est l'inattendu
      // qui doit rester.
      expect(evaluerContre(par(73), [par(24)]), Compatibilite.conseille);
      expect(
          evaluerContre(par(73), [par(24), par(58)]), Compatibilite.inattendu);
    });

    test('sans instrument déjà choisi, rien à signaler', () {
      expect(evaluerContre(par(73), []), Compatibilite.neutre);
    });
  });
}
