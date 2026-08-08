import 'dart:math';

import 'balancement.dart';
import 'compagnons.dart';
import 'epaisseur.dart';
import 'melodie.dart';
import 'nuances.dart';
import 'recette.dart';
import 'reglages.dart';
import 'rubato.dart';

/// Ce qu'un tour de boucle a tiré : la partition à jouer et la façon de la
/// jouer. C'est tout ce dont le rendu a besoin.
class TourDeBoucle {
  final Melodie partition;
  final Reglages reglages;

  const TourDeBoucle(this.partition, this.reglages);
}

/// Le sort, tel que la recette l'encadre : à chaque tour de boucle, un
/// morceau puis une valeur dans chacune de ses bornes.
///
/// Vit dans le moteur, et non dans le module embarqué, pour une raison
/// précise : l'atelier de Bizet fait entendre un tirage d'essai, le module en
/// jouera un pour de vrai. Deux implémentations dériveraient l'une de
/// l'autre, et l'essai cesserait de dire la vérité sur ce que le jeu jouera.
class Tirage {
  /// [instrumentsDisponibles] dit ce que la banque de sons sait jouer : c'est
  /// ce que vaut « tous » dans une recette en mode libre.
  ///
  /// [graine] rejoue exactement la même suite de tirages — utile pour
  /// comparer deux réglages, ou pour qu'un test dise toujours la même chose.
  Tirage(
    this.recette, {
    required this.instrumentsDisponibles,
    int? graine,
  }) : _de = Random(graine);

  final Recette recette;
  final List<int> instrumentsDisponibles;

  final Random _de;

  /// Le morceau du tour précédent : le sort ne le redonnera pas tout de
  /// suite. Avec trois morceaux, le hasard pur en redonne un sur trois — à
  /// l'oreille, ça ne s'entend pas comme du hasard, ça s'entend comme un bug.
  int? _precedent;

  /// Le tour de boucle suivant. Tire d'abord le morceau, puis chacun de ses
  /// réglages dans ses propres bornes.
  TourDeBoucle prochain() {
    final int index = _prochainMorceau();
    _precedent = index;

    final MorceauRecette morceau = recette.morceaux[index];
    return TourDeBoucle(morceau.partition, _reglages(morceau));
  }

  /// Le morceau du tour, tiré selon les poids — sans jamais redonner celui
  /// qui vient d'être joué, sauf s'il est le seul.
  int _prochainMorceau() {
    final List<int> candidats = [
      for (int i = 0; i < recette.morceaux.length; i++)
        if (i != _precedent) i,
    ];
    // Un seul morceau dans la recette : il se répète, faute de mieux.
    final List<int> parmi =
        candidats.isEmpty ? [for (int i = 0; i < recette.morceaux.length; i++) i]
            : candidats;

    final int total =
        parmi.fold(0, (somme, i) => somme + recette.morceaux[i].poids);
    int de = _de.nextInt(total);
    for (final int i in parmi) {
      de -= recette.morceaux[i].poids;
      if (de < 0) return i;
    }
    return parmi.last;
  }

  int _entre(Intervalle borne) =>
      borne.min + _de.nextInt(borne.max - borne.min + 1);

  /// Un cran tiré dans une borne, ramené à ce que la liste possède : une
  /// recette écrite pour une version plus riche ne doit pas faire sortir de
  /// la liste.
  int _cran(Intervalle borne, int nombre) =>
      _entre(borne).clamp(0, nombre - 1);

  Reglages _reglages(MorceauRecette morceau) {
    final Melodie m = morceau.partition;
    final BornesRecette b = morceau.bornes;

    final (int principal, List<int> accompagnants) =
        _instruments(morceau.instrumentation);

    // Ce que le morceau ne saurait pas rendre, on ne le tire pas : sur une
    // suite de notes toutes semblables, aucune règle de rubato ne se
    // déclencherait, et un morceau en blanches ne balance rien.
    final bool balance = Balancement.sEntendSur(m.pulsation);
    final bool respire = rubatoAudible(m.deroule(respiration: false));

    return Reglages(
      tempo: _entre(b.tempo),
      instrument: principal,
      octave: _entre(b.octave),
      majeur: _mode(m, b.caractereOrigine),
      articulation:
          Reglages.articulationDepuisCran(_entre(b.articulation)),
      balancement: Balancement(
        balance ? Swing.values[_cran(b.swing, Swing.values.length)] : Swing.droit,
        Balancement.fenetrePour(m.pulsation),
      ),
      epaisseur: Epaisseur.values[_cran(b.epaisseur, Epaisseur.values.length)],
      compagnons: Compagnons([
        accompagnants.isNotEmpty ? accompagnants[0] : null,
        accompagnants.length > 1 ? accompagnants[1] : null,
      ]),
      accompagnement: _entre(b.accompagnement),
      rubato: respire
          ? Rubato.values[_cran(b.rubato, Rubato.values.length)]
          : Rubato.mecanique,
      nuances: Nuances.values[_cran(b.nuances, Nuances.values.length)],
      // Une graine neuve à chaque tour : deux passages du même morceau ne
      // respirent jamais aux mêmes endroits.
      graine: _de.nextInt(1 << 31),
    );
  }

  /// Le mode du tour : une pondération, pas un intervalle. Nul veut dire
  /// « comme c'est écrit » — c'est aussi la seule réponse possible quand la
  /// partition ne déclare pas sa tonalité, faute de savoir quelles notes
  /// abaisser.
  bool? _mode(Melodie m, int partOrigine) {
    if (m.armure == null) return null;
    return _de.nextInt(100) < partOrigine ? null : !m.armure!.majeur;
  }

  /// Qui joue ce tour-ci : un principal, et zéro à deux accompagnants.
  (int, List<int>) _instruments(InstrumentationRecette instrumentation) {
    switch (instrumentation.mode) {
      case ModeInstrumentation.couples:
        final List<CoupleInstruments> couples = instrumentation.couples;
        if (couples.isEmpty) return (0, const []);

        final int total = couples.fold(0, (somme, c) => somme + c.poids);
        int de = _de.nextInt(total);
        for (final CoupleInstruments c in couples) {
          de -= c.poids;
          if (de < 0) return (c.principal, c.accompagnants);
        }
        return (couples.last.principal, couples.last.accompagnants);

      case ModeInstrumentation.libre:
        // « Tous » s'écrit par l'absence de liste : ce que la banque possède.
        final List<int> principaux =
            instrumentation.principaux ?? instrumentsDisponibles;
        final List<int> accompagnants =
            instrumentation.accompagnants ?? instrumentsDisponibles;

        return (
          principaux.isEmpty ? 0 : principaux[_de.nextInt(principaux.length)],
          accompagnants.isEmpty
              ? const []
              : [accompagnants[_de.nextInt(accompagnants.length)]],
        );
    }
  }
}
