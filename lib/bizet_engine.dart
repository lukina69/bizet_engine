/// Le cœur musical de Bizet, utilisable sans Flutter.
///
/// Ce que le moteur sait faire :
///
/// * lire une partition LilyPond ([LilypondParser]) ;
/// * la représenter ([Melodie], [Mesure], [Note], [Armure]) ;
/// * la transformer — transposition, mode majeur/mineur, découpe ;
/// * dire comment la jouer ([Reglages]) ;
/// * en fabriquer du son ([RenduAudio]) et des fichiers ([ExportMusical]).
///
/// Ce qu'il ne sait pas faire, volontairement : jouer ce son dans un
/// haut-parleur, aller chercher une partition sur le réseau, ni enregistrer un
/// travail en cours. Ces trois-là dépendent de la plateforme ou de
/// l'application, et restent chez l'hôte.
///
/// L'hôte lui fournit aussi ses ressources : le SoundFont se charge à partir
/// de ses octets, jamais d'un chemin d'asset.
library;

export 'src/instruments/catalogue.dart';
export 'src/instruments/compatibilite.dart';
export 'src/instruments/instrument.dart';
export 'src/model/armure.dart';
export 'src/model/balancement.dart';
export 'src/model/compagnons.dart';
export 'src/model/epaisseur.dart';
export 'src/model/melodie.dart';
export 'src/model/mesure.dart';
export 'src/model/note.dart';
export 'src/model/reglages.dart';
export 'src/model/rubato.dart';
export 'src/services/export_musical.dart';
export 'src/services/lilypond_parser.dart';
export 'src/services/rendu_audio.dart';
