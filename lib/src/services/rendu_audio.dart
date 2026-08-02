import 'package:dart_melty_soundfont/dart_melty_soundfont.dart';

import '../model/balancement.dart';
import '../model/compagnons.dart';
import '../model/epaisseur.dart';
import '../model/melodie.dart';
import '../model/reverberation.dart';

/// Fabrique le son d'une [Melodie] : la mélodie entre, une forme d'onde (PCM)
/// en sort.
///
/// C'est la moitié « calcul » de l'ancien `AudioEngine` de Bizet. L'autre
/// moitié — envoyer ce PCM au haut-parleur, suivre le curseur, boucler — vit
/// dans l'application hôte, parce qu'elle dépend de la plateforme. Ici, rien
/// ne dépend de Flutter : le rendu tourne aussi bien en ligne de commande.
class RenduAudio {
  static const int frequence = 44100;

  Synthesizer? _synth;

  /// Programmes General MIDI que le SoundFont chargé sait vraiment jouer,
  /// triés. Vide tant qu'il n'est pas chargé.
  ///
  /// Un fichier .sf2 ne couvre pas forcément les 128 sonorités de la norme :
  /// proposer les autres à l'utilisateur reviendrait à lui promettre du
  /// silence.
  List<int> get programmes {
    final Synthesizer? synth = _synth;
    if (synth == null) return const [];
    return synth.soundFont.presets
        .where((p) => p.bankNumber == 0)
        .map((p) => p.patchNumber)
        .toList()
      ..sort();
  }

  bool get charge => _synth != null;

  /// Longueur de la partie musicale du dernier rendu, en échantillons — le
  /// tampon est plus long d'une seconde, le temps que les notes s'éteignent.
  /// Rapporter le curseur au tampon entier le mettrait en retard, d'autant
  /// plus que le morceau avance.
  int _echantillonsMusique = 0;

  int get echantillonsMusique => _echantillonsMusique;

  /// Charge le SoundFont à partir de ses octets.
  ///
  /// C'est à l'hôte de les fournir : le moteur ne connaît ni les assets de
  /// Flutter, ni le système de fichiers de l'appareil.
  void chargerSoundFont(ByteData donnees) {
    if (_synth != null) return;

    _synth = Synthesizer.loadByteData(
      donnees,
      SynthesizerSettings(
        sampleRate: frequence,
        blockSize: 64,
        maximumPolyphony: 64,
        enableReverbAndChorus: true,
      ),
    );
  }

  /// Enveloppe d'un tampon : [points] valeurs entre 0 et 1, chacune le pic du
  /// segment correspondant. Sert à dessiner la forme d'onde. On peut se
  /// limiter à ses [echantillons] premiers échantillons.
  static List<double> enveloppeDe(
    ArrayInt16 tampon, {
    int points = 480,
    int? echantillons,
  }) {
    final int longueur = tampon.bytes.lengthInBytes ~/ 2;
    final int total = (echantillons == null || echantillons > longueur)
        ? longueur
        : echantillons;
    if (total == 0) return const [];

    final List<double> valeurs = List<double>.filled(points, 0);
    final int parPoint = (total / points).ceil();

    for (int p = 0; p < points; p++) {
      final int debut = p * parPoint;
      if (debut >= total) break;
      final int fin = (debut + parPoint) > total ? total : debut + parPoint;

      int pic = 0;
      for (int i = debut; i < fin; i++) {
        final int v = (tampon[i] as int).abs();
        if (v > pic) pic = v;
      }
      valeurs[p] = pic / 32768.0;
    }
    return valeurs;
  }

  /// Rend la mélodie complète en PCM (16 bits, mono). Réclame un SoundFont
  /// déjà chargé.
  ///
  /// [articulation] multiplie la durée sonore des notes : 1,0 les laisse
  /// sonner jusqu'à la suivante, 0,4 les pique.
  ///
  /// [balancement] retarde ce qui tombe entre deux temps, sans déplacer les
  /// temps eux-mêmes.
  ///
  /// [reverberation] choisit le lieu : la dose d'écho ajoutée au son sec.
  ///
  /// [compagnons] ajoute un ou deux autres instruments à l'unisson.
  ArrayInt16 rendre(
    Melodie melodie, {
    double articulation = 1.0,
    Balancement balancement = const Balancement(),
    Reverberation reverberation = Reverberation.salon,
    Epaisseur epaisseur = Epaisseur.simple,
    Compagnons compagnons = Compagnons.aucun,
  }) {
    final Synthesizer synth = _synth!;
    synth.reset();

    // Chaque voix de l'épaisseur a son propre canal : tous doivent recevoir
    // les mêmes réglages, sans quoi les doublages sonneraient d'un autre
    // instrument, dans un autre lieu et à une autre hauteur.
    for (int canal = 0; canal < epaisseur.canaux; canal++) {
      _preparerCanal(synth, canal, melodie.instrumentMidi, reverberation);
    }

    // Les compagnons prennent les canaux suivants : c'est justement parce
    // qu'ils sont à part qu'ils peuvent porter un autre timbre.
    for (final voix in compagnons.canaux(epaisseur.canaux)) {
      _preparerCanal(synth, voix.canal, voix.programme, reverberation);
    }

    final List<_Evenement> evenements =
        _evenements(melodie, articulation, balancement, epaisseur, compagnons);

    // Le modèle exprime les durées en temps (1.0 = une noire).
    final double secondesParTemps = 60.0 / melodie.tempo;

    final double dernierTemps =
        evenements.isEmpty ? 0.0 : evenements.last.temps;

    // Durée musicale : la somme des mesures, exactement ce que l'affichage
    // dessine. C'est la référence du curseur de lecture.
    final double dureeMesures =
        melodie.mesures.fold(0.0, (somme, m) => somme + m.dureeEffective);
    _echantillonsMusique =
        (dureeMesures * secondesParTemps * frequence).ceil();

    // Le tampon va jusqu'au dernier événement (une note peut dépasser sa
    // mesure), plus une seconde de queue pour laisser les notes s'éteindre.
    final double fin =
        dernierTemps > dureeMesures ? dernierTemps : dureeMesures;
    final int total =
        (fin * secondesParTemps * frequence).ceil() + frequence;

    final ArrayInt16 tampon = ArrayInt16.zeros(numShorts: total);

    int position = 0;
    for (final _Evenement e in evenements) {
      final int cible =
          (e.temps * secondesParTemps * frequence).round().clamp(0, total);

      if (cible > position) {
        synth.renderMonoInt16(tampon, offset: position, length: cible - position);
        position = cible;
      }

      if (e.debut) {
        synth.noteOn(channel: e.canal, key: e.hauteur, velocity: e.velocite);
      } else {
        synth.noteOff(channel: e.canal, key: e.hauteur);
      }
    }

    if (position < total) {
      synth.renderMonoInt16(tampon, offset: position, length: total - position);
    }

    return tampon;
  }

  /// Installe un canal MIDI : son lieu et sa sonorité.
  void _preparerCanal(
    Synthesizer synth,
    int canal,
    int programme,
    Reverberation reverberation,
  ) {
    // La dose de réverbération — reset() vient de la remettre au salon par
    // défaut, on la cale sur le lieu choisi.
    synth.processMidiMessage(
      channel: canal,
      command: 0xB0, // controller
      data1: 0x5B, // reverb send
      data2: reverberation.envoi,
    );

    // Attention : selectPreset() attend un INDICE dans la liste des
    // instruments du fichier .sf2, pas un numéro de programme General MIDI.
    // Comme Melodie.instrumentMidi est bien un numéro GM, on envoie
    // directement un changement de programme MIDI.
    synth.processMidiMessage(
      channel: canal,
      command: 0xC0, // program change
      data1: programme,
      data2: 0,
    );
  }

  /// Convertit la mélodie en événements note-on / note-off, triés dans le temps.
  ///
  /// La durée de chaque mesure vient de [Mesure.dureeEffective] : un silence en
  /// fin de mesure est donc respecté.
  ///
  /// [articulation] raccourcit ou non la durée sonore de chaque note, sans
  /// toucher au rythme : la note suivante démarre toujours à l'heure, seul le
  /// silence qui la précède s'allonge.
  ///
  /// [balancement] décale ensuite les instants obtenus : c'est le seul endroit
  /// où le rythme joué s'écarte du rythme écrit.
  /// [epaisseur] ajoute les voix doublées : elles partent au même instant et
  /// durent aussi longtemps que la note d'origine, articulation et balancement
  /// compris, sinon les voix se désynchroniseraient. [compagnons] ajoute de
  /// même les voix à l'unisson.
  List<_Evenement> _evenements(
    Melodie melodie,
    double articulation,
    Balancement balancement,
    Epaisseur epaisseur,
    Compagnons compagnons,
  ) {
    final List<_Evenement> liste = [];
    double debutMesure = 0.0;

    for (final mesure in melodie.mesures) {
      for (final note in mesure.notes) {
        final double debut = balancement.applique(debutMesure + note.position);
        final double fin = balancement
            .applique(debutMesure + note.position + note.duree * articulation);

        for (final voix in [
          ...epaisseur.voix(note.hauteur),
          ...compagnons.voix(note.hauteur, epaisseur.canaux),
        ]) {
          liste.add(_Evenement(
              debut, true, voix.hauteur, voix.canal, voix.velocite));
          liste.add(_Evenement(fin, false, voix.hauteur, voix.canal, 0));
        }
      }

      debutMesure += mesure.dureeEffective;
    }

    // À instant égal, on éteint avant d'allumer : deux notes de même hauteur
    // qui se suivent ne se marchent pas dessus.
    liste.sort((a, b) {
      final int parTemps = a.temps.compareTo(b.temps);
      return parTemps != 0 ? parTemps : (a.debut ? 1 : -1);
    });
    return liste;
  }
}

/// Un début ou une fin de note, positionné dans le temps musical.
class _Evenement {
  final double temps;
  final bool debut;
  final int hauteur;
  final int canal;
  final int velocite;

  _Evenement(this.temps, this.debut, this.hauteur, this.canal, this.velocite);
}
