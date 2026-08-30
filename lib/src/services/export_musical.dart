import 'dart:convert';
import 'dart:typed_data';

import 'package:dart_melty_soundfont/dart_melty_soundfont.dart' show ArrayInt16;

import '../model/balancement.dart';
import '../model/compagnons.dart';
import '../model/epaisseur.dart';
import '../model/melodie.dart';
import '../model/reglages.dart';
import 'rendu_audio.dart';

/// Écrit une [Melodie] dans un format que le reste du monde sait lire : MIDI
/// pour la partition jouable, WAV pour le son déjà fabriqué.
///
/// Aucun encodage exotique ici : ce sont deux formats binaires simples qu'on
/// écrit directement, sans dépendance ni compilation native.
///
/// Ce qui relève d'une application — enregistrer un chantier en cours avec ses
/// réglages — ne se trouve pas ici : ça n'a de sens que pour l'appli qui l'a
/// produit.
class ExportMusical {
  /// Nombre de tics MIDI par noire. 480 est la valeur usuelle des séquenceurs.
  static const int ticsParNoire = 480;

  // -------------------------------------------------------------------
  // MIDI : fichier standard de type 0, une seule piste.
  // -------------------------------------------------------------------

  /// Les [reglages] s'appliquent comme à la lecture : le fichier exporté doit
  /// sonner comme ce que l'utilisateur a réglé. Les voix ajoutées par
  /// l'épaisseur sont donc écrites comme de vraies notes, sur leur propre
  /// canal, et celles des compagnons gardent en plus leur propre sonorité. Le
  /// fichier est moins « propre » à réutiliser, c'est un compromis assumé.
  Uint8List versMidi(
    Melodie partition, {
    Reglages reglages = const Reglages(),
  }) {
    final Melodie melodie = reglages.applique(partition);
    final Epaisseur epaisseur = reglages.epaisseur;
    // Les compagnons **calés** : ce sont eux que les notes suivront plus bas,
    // et eux seuls qui portent le niveau de chaque voix. Prendre les
    // compagnons bruts ici enverrait le fichier avec des canaux muets de
    // toute correction.
    final Compagnons compagnons = reglages.compagnonsCales(melodie);
    final List<int> piste = [];

    // Tempo : nombre de microsecondes par noire.
    final int microsecondes = (60000000 / melodie.tempo).round();
    piste.addAll([0x00, 0xFF, 0x51, 0x03]);
    piste.addAll([
      (microsecondes >> 16) & 0xFF,
      (microsecondes >> 8) & 0xFF,
      microsecondes & 0xFF,
    ]);

    // Choix de l'instrument, le même sur chaque canal de l'épaisseur.
    for (int canal = 0; canal < epaisseur.canaux; canal++) {
      piste.addAll([0x00, 0xC0 | canal, melodie.instrumentMidi & 0x7F]);
    }

    // Les compagnons, eux, ont chacun le leur, sur les canaux suivants.
    for (final voix in compagnons.canaux(epaisseur.canaux)) {
      piste.addAll([0x00, 0xC0 | voix.canal, voix.programme & 0x7F]);
      // Le niveau de la voix voyage avec elle : un fichier MIDI ouvert
      // ailleurs doit garder l'équilibre qu'on a entendu ici. Il passe par le
      // volume de canal, comme au rendu, et non par la vélocité.
      if (voix.niveau != 0) {
        piste.addAll([
          0x00,
          0xB0 | voix.canal,
          0x07,
          RenduAudio.volumeDeCanal(voix.niveau),
        ]);
      }
    }

    int precedent = 0;
    for (final _Evenement e in _evenements(melodie, reglages)) {
      piste.addAll(_dureeVariable(e.tic - precedent));
      piste.addAll([
        (e.debut ? 0x90 : 0x80) | e.canal,
        e.hauteur.clamp(0, 127),
        e.velocite,
      ]);
      precedent = e.tic;
    }

    // Fin de piste.
    piste.addAll([0x00, 0xFF, 0x2F, 0x00]);

    final BytesBuilder fichier = BytesBuilder();
    fichier.add(ascii.encode('MThd'));
    fichier.add(_entier32(6));
    fichier.add([0x00, 0x00]); // type 0 : une seule piste
    fichier.add([0x00, 0x01]); // nombre de pistes
    fichier.add([(ticsParNoire >> 8) & 0xFF, ticsParNoire & 0xFF]);
    fichier.add(ascii.encode('MTrk'));
    fichier.add(_entier32(piste.length));
    fichier.add(piste);

    return fichier.toBytes();
  }

  /// Les temps MIDI s'écrivent en « quantité de longueur variable » : sept
  /// bits utiles par octet, le huitième indiquant qu'un octet suit.
  List<int> _dureeVariable(int valeur) {
    if (valeur <= 0) return [0x00];

    final List<int> octets = [valeur & 0x7F];
    int reste = valeur >> 7;
    while (reste > 0) {
      octets.insert(0, (reste & 0x7F) | 0x80);
      reste >>= 7;
    }
    return octets;
  }

  Uint8List _entier32(int v) => Uint8List.fromList([
        (v >> 24) & 0xFF,
        (v >> 16) & 0xFF,
        (v >> 8) & 0xFF,
        v & 0xFF,
      ]);

  /// Débuts et fins de notes, en tics, triés dans le temps. Les mesures
  /// s'enchaînent sur leur durée déclarée, silences de fin compris.
  List<_Evenement> _evenements(Melodie melodie, Reglages reglages) {
    final Balancement balancement = reglages.balancement;
    final Epaisseur epaisseur = reglages.epaisseur;
    final Compagnons compagnons = reglages.compagnonsCales(melodie);

    final List<_Evenement> liste = [];

    // Le poids de chaque note, aligné sur l'ordre des notes sonnantes.
    final List<int> nuances = reglages.deltasNuances(melodie);
    int rang = 0;

    for (final sonnante in reglages.notesSonnantes(melodie)) {
      final int ticDebut =
          (balancement.applique(sonnante.debut) * ticsParNoire).round();
      final int ticFin =
          (balancement.applique(sonnante.fin) * ticsParNoire).round();
      final int poids = rang < nuances.length ? nuances[rang] : 0;
      rang++;

      for (final voix in [
        ...epaisseur.voix(sonnante.hauteur, brillance: reglages.brillance),
        ...compagnons.voix(sonnante.hauteur, epaisseur.canaux,
            brillance: reglages.brillance),
      ]) {
        liste.add(_Evenement(ticDebut, true, voix.hauteur, voix.canal,
            (voix.velocite + poids).clamp(1, 127)));
        liste.add(_Evenement(ticFin, false, voix.hauteur, voix.canal, 0));
      }
    }

    liste.sort((a, b) {
      final int parTemps = a.tic.compareTo(b.tic);
      // À tic égal, on éteint avant d'allumer : deux fois la même note ne se
      // chevauche pas.
      return parTemps != 0 ? parTemps : (a.debut ? 1 : -1);
    });
    return liste;
  }

  // -------------------------------------------------------------------
  // WAV : l'audio déjà fabriqué, précédé d'un en-tête de 44 octets.
  // -------------------------------------------------------------------

  Uint8List versWav(ArrayInt16 pcm, {int frequence = 44100}) {
    final Uint8List donnees = pcm.bytes.buffer.asUint8List(
      pcm.bytes.offsetInBytes,
      pcm.bytes.lengthInBytes,
    );

    const int canaux = 1;
    const int bits = 16;
    final int octetsParSeconde = frequence * canaux * bits ~/ 8;

    final ByteData entete = ByteData(44);
    entete.setUint32(0, 0x52494646, Endian.big); // « RIFF »
    entete.setUint32(4, 36 + donnees.length, Endian.little);
    entete.setUint32(8, 0x57415645, Endian.big); // « WAVE »
    entete.setUint32(12, 0x666D7420, Endian.big); // « fmt  »
    entete.setUint32(16, 16, Endian.little); // taille du bloc format
    entete.setUint16(20, 1, Endian.little); // PCM non compressé
    entete.setUint16(22, canaux, Endian.little);
    entete.setUint32(24, frequence, Endian.little);
    entete.setUint32(28, octetsParSeconde, Endian.little);
    entete.setUint16(32, canaux * bits ~/ 8, Endian.little);
    entete.setUint16(34, bits, Endian.little);
    entete.setUint32(36, 0x64617461, Endian.big); // « data »
    entete.setUint32(40, donnees.length, Endian.little);

    final BytesBuilder fichier = BytesBuilder();
    fichier.add(entete.buffer.asUint8List());
    fichier.add(donnees);
    return fichier.toBytes();
  }
}

class _Evenement {
  final int tic;
  final bool debut;
  final int hauteur;
  final int canal;
  final int velocite;

  _Evenement(this.tic, this.debut, this.hauteur, this.canal, this.velocite);
}
