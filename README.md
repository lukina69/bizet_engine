# bizet_engine

Le cœur musical de [Bizet](https://github.com/lukina69/bizet), en Dart pur.

Une partition LilyPond entre, une mélodie manipulable en sort, et le moteur
sait en refaire du son. Aucune dépendance à Flutter : le moteur tourne en
ligne de commande, ce qui permet de le tester et de l'explorer sans lancer
d'application.

Deux applications s'en servent : **Bizet**, qui laisse bidouiller un morceau à
la main, et **Capture**, un jeu qui rejoue une partition en boucle avec des
paramètres légèrement différents à chaque cycle.

## Ce qu'il fait

| | |
|---|---|
| `LilypondParser` | lit un fichier `.ly` et en fait une `Melodie` |
| `Melodie`, `Mesure`, `Note`, `Armure` | le modèle musical, et ses transformations : transposition, bascule majeur/mineur, découpe |
| `Balancement`, `Epaisseur` | les réglages d'interprétation |
| `RenduAudio` | fabrique le son du morceau (PCM 16 bits mono) à partir d'un SoundFont |
| `ExportMusical` | écrit un fichier MIDI ou WAV |

## Ce qu'il ne fait pas

Envoyer le son au haut-parleur, aller chercher une partition sur le réseau,
enregistrer un travail en cours. Tout cela dépend de la plateforme ou de
l'application, et reste chez l'hôte.

Le moteur n'embarque non plus **aucune ressource** : ni partition, ni
SoundFont. C'est l'hôte qui les charge et lui passe les octets.

## Exemple

```dart
import 'dart:io';
import 'package:bizet_engine/bizet_engine.dart';

void main() {
  final melodie = LilypondParser().parse(
    File('morceau.ly').readAsStringSync(),
  );

  // Le même morceau, une quarte plus haut et en mineur.
  final variante = melodie.transposee(5).enMode(false);

  final rendu = RenduAudio()
    ..chargerSoundFont(
      File('banque.sf2').readAsBytesSync().buffer.asByteData(),
    );

  final son = rendu.rendre(variante);
  File('sortie.wav').writeAsBytesSync(ExportMusical().versWav(son));
}
```

## Utilisation

Le paquet n'est pas publié sur pub.dev. Il se référence par son chemin :

```yaml
dependencies:
  bizet_engine:
    path: ../bizet_engine
```

## Licence

Les partitions du [Mutopia Project](https://www.mutopiaproject.org) sont sous
licence Creative Commons BY-SA. Le moteur n'en embarque aucune, mais toute
application qui en redistribue doit respecter l'attribution et le partage à
l'identique.
