import 'dart:math' as math;

import 'package:dart_melty_soundfont/dart_melty_soundfont.dart';

import '../model/voix.dart';
import '../model/melodie.dart';
import '../model/reglages.dart';

/// Fabrique le son d'une [Melodie] : la mélodie entre, une forme d'onde (PCM)
/// en sort.
///
/// C'est la moitié « calcul » de l'ancien `AudioEngine` de Bizet. L'autre
/// moitié — envoyer ce PCM au haut-parleur, suivre le curseur, boucler — vit
/// dans l'application hôte, parce qu'elle dépend de la plateforme. Ici, rien
/// ne dépend de Flutter : le rendu tourne aussi bien en ligne de commande.
class RenduAudio {
  /// La qualité de rendu de l'application : celle du disque compact.
  static const int frequence = 44100;

  /// [frequenceRendu] est la finesse à laquelle le son est fabriqué. La
  /// baisser divise d'autant le travail du synthétiseur — un levier de
  /// premier plan pour un hôte qui doit produire ses boucles vite, d'autant
  /// que la banque livrée est elle-même échantillonnée bien en dessous.
  ///
  /// [reverberation] laisse ou coupe la réverbération et le chorus du
  /// synthétiseur. C'est le son que Bizet a toujours eu, mais ils se
  /// calculent sur chaque échantillon.
  RenduAudio({
    this.frequenceRendu = frequence,
    this.reverberation = true,
  });

  final int frequenceRendu;
  final bool reverberation;

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
  /// Oublie la banque en place, pour qu'un prochain [chargerSoundFont] en
  /// monte une autre. L'hôte s'en sert quand l'utilisateur change les
  /// sonorités qu'il possède.
  void oublierSoundFont() => _synth = null;

  void chargerSoundFont(ByteData donnees) {
    if (_synth != null) return;

    _synth = Synthesizer.loadByteData(
      donnees,
      SynthesizerSettings(
        sampleRate: frequenceRendu,
        blockSize: 64,
        maximumPolyphony: 64,
        enableReverbAndChorus: reverberation,
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

  /// Le rendu par amorce dont la suite n'a pas encore été fabriquée : un
  /// nouveau rendu qui démarrerait entre-temps reprendrait le synthétiseur,
  /// et la suite ne vaudrait plus rien. On l'invalide donc, et c'est l'appel
  /// de la suite qui le dira — plutôt qu'un tampon silencieusement faux.
  _RenduEnCours? _enAttente;

  /// Rend la mélodie complète en PCM (16 bits, mono). Réclame un SoundFont
  /// déjà chargé.
  ///
  /// Les [reglages] disent tout de la façon de jouer la partition : à quel
  /// tempo, dans quel mode, à quelle hauteur, avec quelle sonorité, quel
  /// piqué, quel balancement et quels doublages.
  ArrayInt16 rendre(
    Melodie partition, {
    Reglages reglages = const Reglages(),
  }) {
    final _RenduEnCours rendu = _preparer(partition, reglages);
    return rendu.tranche(rendu.total);
  }

  /// Rend la mélodie en deux temps : d'abord ses [mesuresAmorce] premières
  /// mesures — l'amorce —, puis le reste au premier appel de `suite`.
  ///
  /// C'est le levier du démarrage, mesuré sur appareil : l'amorce coûte
  /// quelques dizaines de millisecondes là où le tour entier en coûte des
  /// centaines. Le son peut sortir presque aussitôt, la suite se fabriquant
  /// pendant qu'il joue.
  ///
  /// Même synthétiseur, même suite d'événements : l'amorce suivie de la
  /// suite donne, à l'échantillon près, le tampon de [rendre]. La suite ne
  /// se rend qu'une fois, et doit l'être avant tout autre rendu — sinon elle
  /// lève [StateError], plutôt que de rendre un son qui n'aurait plus rien à
  /// voir avec son amorce.
  ({ArrayInt16 amorce, ArrayInt16 Function() suite}) rendreParAmorce(
    Melodie partition, {
    Reglages reglages = const Reglages(),
    int mesuresAmorce = 2,
  }) {
    final _RenduEnCours rendu = _preparer(partition, reglages);

    // La coupure tombe à la fin de la dernière mesure de l'amorce : jamais
    // au milieu d'une note, et la suite reprend exactement là.
    final double dureeAmorce = rendu.melodie.mesures
        .take(mesuresAmorce)
        .fold(0.0, (somme, m) => somme + m.dureeEffective);
    final int coupure =
        (dureeAmorce * rendu.secondesParTemps * frequenceRendu)
            .ceil()
            .clamp(0, rendu.total);

    final ArrayInt16 amorce = rendu.tranche(coupure);
    _enAttente = rendu;

    return (
      amorce: amorce,
      suite: () {
        if (_enAttente != rendu) {
          throw StateError('la suite de cette amorce a déjà été rendue, '
              'ou un autre rendu est passé derrière elle');
        }
        _enAttente = null;
        return rendu.tranche(rendu.total);
      },
    );
  }

  /// Tout ce qui précède le premier échantillon : la mélodie jouable, les
  /// canaux installés, les événements triés et le tampon dimensionné.
  _RenduEnCours _preparer(Melodie partition, Reglages reglages) {
    _enAttente = null;

    final Melodie melodie = reglages.applique(partition);

    final Synthesizer synth = _synth!;
    synth.reset();

    // Chaque voix prend ses canaux à la suite : un par doublage d'épaisseur.
    // Les doublages d'une même voix doivent recevoir les mêmes réglages, sans
    // quoi ils sonneraient d'un autre instrument et à une autre hauteur ; deux
    // voix différentes, au contraire, sont justement à part pour pouvoir
    // porter d'autres timbres.
    //
    // Toutes sont égalisées, la principale comprise, et c'est ce qui fait
    // qu'en changeant de sonorité l'utilisateur change de couleur sans changer
    // de volume. Sans cela, essayer des timbres revenait à jouer du bouton de
    // volume sans le savoir : vingt-cinq décibels séparent les extrêmes de la
    // banque.
    for (final VoixJouee jouee in reglages.voixJouees(melodie)) {
      for (int i = 0; i < jouee.voix.canaux; i++) {
        _preparerCanal(synth, jouee.premierCanal + i, jouee.programme,
            niveau: jouee.niveau);
      }
    }

    final List<_Evenement> evenements = _evenements(melodie, reglages);

    // Le modèle exprime les durées en temps (1.0 = une noire).
    final double secondesParTemps = 60.0 / melodie.tempo;

    final double dernierTemps =
        evenements.isEmpty ? 0.0 : evenements.last.temps;

    // Durée musicale : la somme des mesures, exactement ce que l'affichage
    // dessine. C'est la référence du curseur de lecture.
    final double dureeMesures =
        melodie.mesures.fold(0.0, (somme, m) => somme + m.dureeEffective);
    _echantillonsMusique =
        (dureeMesures * secondesParTemps * frequenceRendu).ceil();

    // Le tampon va jusqu'au dernier événement (une note peut dépasser sa
    // mesure), plus une seconde de queue pour laisser les notes s'éteindre.
    final double fin =
        dernierTemps > dureeMesures ? dernierTemps : dureeMesures;
    final int total =
        (fin * secondesParTemps * frequenceRendu).ceil() + frequenceRendu;

    return _RenduEnCours(
      synth: synth,
      melodie: melodie,
      evenements: evenements,
      secondesParTemps: secondesParTemps,
      frequenceRendu: frequenceRendu,
      total: total,
    );
  }

  /// Le volume de canal (CC7) qui réalise un écart de [db].
  ///
  /// Le synthétiseur élève ce volume au carré pour en faire un gain — comme
  /// la vélocité —, d'où le même exposant 40 que partout ailleurs. Cent est
  /// la valeur au repos, celle qu'un canal prend sans qu'on lui dise rien ;
  /// on ne peut donc monter que de quatre décibels au-dessus, mais descendre
  /// autant qu'on veut.
  static int volumeDeCanal(double db) =>
      (100 * math.pow(10, db / 40)).round().clamp(0, 127);

  /// Installe un canal MIDI : sa sonorité, et son niveau.
  void _preparerCanal(
    Synthesizer synth,
    int canal,
    int programme, {
    double niveau = 0,
  }) {
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

    // Le niveau passe par le volume de canal, jamais par la vélocité : ainsi
    // baisser une voix ne l'assourdit pas, ça la met simplement en retrait.
    if (niveau != 0) {
      synth.processMidiMessage(
        channel: canal,
        command: 0xB0, // contrôleur
        data1: 0x07, // volume de canal
        data2: volumeDeCanal(niveau),
      );
    }
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
  List<_Evenement> _evenements(Melodie melodie, Reglages reglages) {
    // Le rubato appartient au chef : il se calcule une fois, et les voix le
    // reçoivent toutes tel quel. Chacune l'articule ensuite à sa façon.
    final List<({double debut, double fin})> respiration =
        reglages.rubatoDe(melodie);

    final List<_Evenement> liste = [];

    for (final VoixJouee jouee in reglages.voixJouees(melodie)) {
      final Voix voix = jouee.voix;

      // Le poids de chaque note, aligné sur l'ordre des notes sonnantes.
      final List<int> nuances =
          reglages.deltasNuances(melodie, intensite: voix.nuances);
      int rang = 0;

      for (final sonnante in reglages.notesSonnantes(melodie,
          articulation: voix.articulation, ecarts: respiration)) {
        final double debut = voix.balancement.applique(sonnante.debut);
        final double fin = voix.balancement.applique(sonnante.fin);
        final int poids = rang < nuances.length ? nuances[rang] : 0;
        rang++;

        for (final doublage in voix.epaisseur.voix(
          sonnante.hauteur + 12 * jouee.octave,
          brillance: reglages.brillance - voix.recul,
        )) {
          final int canal = jouee.premierCanal + doublage.canal;
          liste.add(_Evenement(debut, true, doublage.hauteur, canal,
              (doublage.velocite + poids).clamp(1, 127)));
          liste.add(_Evenement(fin, false, doublage.hauteur, canal, 0));
        }
      }
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

/// Un rendu qui peut s'interrompre et reprendre : le synthétiseur garde son
/// état d'une tranche à l'autre, si bien que découper ne change pas un
/// échantillon — une note tenue traverse la coupure, la réverbération aussi.
class _RenduEnCours {
  _RenduEnCours({
    required this.synth,
    required this.melodie,
    required this.evenements,
    required this.secondesParTemps,
    required this.frequenceRendu,
    required this.total,
  });

  final Synthesizer synth;
  final Melodie melodie;
  final List<_Evenement> evenements;
  final double secondesParTemps;
  final int frequenceRendu;

  /// Longueur du rendu entier, queue comprise, en échantillons.
  final int total;

  /// Échantillons déjà rendus par les tranches précédentes.
  int _position = 0;

  /// Rang du prochain événement à jouer.
  int _prochain = 0;

  /// Rend les échantillons de la position courante jusqu'à [fin] (exclue),
  /// dans un tampon neuf de cette taille-là.
  ///
  /// Un événement qui tombe exactement sur [fin] joue en tête de la tranche
  /// suivante — au même échantillon que dans un rendu d'un seul bloc.
  ArrayInt16 tranche(int fin) {
    final int base = _position;
    final ArrayInt16 tampon = ArrayInt16.zeros(numShorts: fin - base);

    while (_prochain < evenements.length) {
      final _Evenement e = evenements[_prochain];
      final int cible = (e.temps * secondesParTemps * frequenceRendu)
          .round()
          .clamp(0, total);
      if (cible >= fin) break;

      if (cible > _position) {
        synth.renderMonoInt16(tampon,
            offset: _position - base, length: cible - _position);
        _position = cible;
      }

      if (e.debut) {
        synth.noteOn(channel: e.canal, key: e.hauteur, velocity: e.velocite);
      } else {
        synth.noteOff(channel: e.canal, key: e.hauteur);
      }
      _prochain++;
    }

    if (_position < fin) {
      synth.renderMonoInt16(tampon,
          offset: _position - base, length: fin - _position);
      _position = fin;
    }

    return tampon;
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
