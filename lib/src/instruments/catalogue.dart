import 'instrument.dart';

/// Les instruments que l'application connaît, dans l'ordre des numéros de
/// programme.
///
/// Ils débordent de la banque embarquée : celle-ci n'en porte plus que neuf,
/// le reste se téléchargeant à la demande. Une sonorité absente d'ici n'est
/// pas pour autant injouable — elle est simplement classée « neutre » face aux
/// autres. **Elle est en revanche égalisée comme les autres** : le poids de
/// chaque sonorité se mesure à part, pour les cent vingt (voir `poids.dart`).
/// Source de vérité unique : le grisage des octaves, l'épaisseur et les
/// suggestions d'associations lisent tous cette table.
///
/// La palette est équilibrée à dessein : dix sons résonants, dix entretenus.
/// La liste précédente penchait à quinze contre cinq, et ce déséquilibre
/// sonnait métallique quoi qu'on règle par ailleurs.
///
/// Les tessitures sont **musicales**, posées de départ et à ajuster à
/// l'oreille — pas les plages de samples du fichier, qui sont étirées sur
/// tout le clavier. Les vrais plafonds relevés dans la banque (tuba : 72 ;
/// orgue, chœur et cors : 96) sont respectés.
const List<Instrument> catalogue = [
  // Le piano à queue ne vient pas de la même banque que les autres : ceux de
  // MuseScore comptent sur des modulateurs que le moteur ignore, et n'en
  // sortaient qu'un murmure. Celui-ci est repris de GeneralUser GS.
  Instrument(
      programme: 0,
      nom: 'Stereo Grand',
      noteMin: 21,
      noteMax: 108,
      enveloppe: Enveloppe.resonant,
      famille: Famille.piano),
  Instrument(
      programme: 4,
      nom: 'Tine Electric Piano',
      noteMin: 28,
      noteMax: 88,
      enveloppe: Enveloppe.resonant,
      famille: Famille.clavierElectrique),
  Instrument(
      programme: 6,
      nom: 'Harpsichord',
      noteMin: 29,
      noteMax: 89,
      enveloppe: Enveloppe.resonant,
      famille: Famille.clavecin),
  Instrument(
      programme: 8,
      nom: 'Celesta',
      noteMin: 48,
      noteMax: 96,
      enveloppe: Enveloppe.resonant,
      famille: Famille.metallophone),
  Instrument(
      programme: 10,
      nom: 'Music Box',
      noteMin: 72,
      noteMax: 96,
      enveloppe: Enveloppe.resonant,
      famille: Famille.metallophone),
  Instrument(
      programme: 12,
      nom: 'Marimba',
      noteMin: 36,
      noteMax: 96,
      enveloppe: Enveloppe.resonant,
      famille: Famille.percussionBois),
  Instrument(
      programme: 19,
      nom: 'Church Organ',
      noteMin: 36,
      noteMax: 96,
      enveloppe: Enveloppe.entretenu,
      famille: Famille.orgue),
  Instrument(
      programme: 24,
      nom: 'Nylon String Guitar',
      noteMin: 40,
      noteMax: 83,
      enveloppe: Enveloppe.resonant,
      famille: Famille.pince),
  Instrument(
      programme: 32,
      nom: 'Acoustic Bass',
      noteMin: 28,
      noteMax: 55,
      enveloppe: Enveloppe.resonant,
      famille: Famille.pince),
  Instrument(
      programme: 40,
      nom: 'Violin',
      noteMin: 55,
      noteMax: 93,
      enveloppe: Enveloppe.entretenu,
      famille: Famille.frotte),
  Instrument(
      programme: 42,
      nom: 'Cello',
      noteMin: 36,
      noteMax: 81,
      enveloppe: Enveloppe.entretenu,
      famille: Famille.frotte),
  Instrument(
      programme: 45,
      nom: 'Strings Pizzicato',
      noteMin: 36,
      noteMax: 93,
      enveloppe: Enveloppe.resonant,
      famille: Famille.pince),
  Instrument(
      programme: 46,
      nom: 'Harp',
      noteMin: 24,
      noteMax: 103,
      enveloppe: Enveloppe.resonant,
      famille: Famille.harpe),
  Instrument(
      programme: 48,
      nom: 'Strings Fast',
      noteMin: 36,
      noteMax: 96,
      enveloppe: Enveloppe.entretenu,
      famille: Famille.frotte),
  Instrument(
      programme: 52,
      nom: 'Choir Aahs',
      noteMin: 43,
      noteMax: 84,
      enveloppe: Enveloppe.entretenu,
      famille: Famille.voix),
  Instrument(
      programme: 56,
      nom: 'Trumpet',
      noteMin: 52,
      noteMax: 82,
      enveloppe: Enveloppe.entretenu,
      famille: Famille.cuivre),
  Instrument(
      programme: 58,
      nom: 'Tuba',
      noteMin: 28,
      noteMax: 65,
      enveloppe: Enveloppe.entretenu,
      famille: Famille.cuivre),
  Instrument(
      programme: 60,
      nom: 'French Horns',
      noteMin: 34,
      noteMax: 77,
      enveloppe: Enveloppe.entretenu,
      famille: Famille.cuivre),
  Instrument(
      programme: 71,
      nom: 'Clarinet',
      noteMin: 50,
      noteMax: 91,
      enveloppe: Enveloppe.entretenu,
      famille: Famille.bois),
  Instrument(
      programme: 73,
      nom: 'Flute',
      noteMin: 60,
      noteMax: 96,
      enveloppe: Enveloppe.entretenu,
      famille: Famille.bois),
  Instrument(
      programme: 104,
      nom: 'Sitar',
      noteMin: 48,
      noteMax: 84,
      enveloppe: Enveloppe.resonant,
      famille: Famille.pince),
];

/// L'instrument portant ce numéro de programme, ou nul s'il n'est pas dans la
/// banque. Recherche linéaire : vingt entrées, aucune importance.
Instrument? instrumentParProgramme(int programme) {
  for (final Instrument i in catalogue) {
    if (i.programme == programme) return i;
  }
  return null;
}
