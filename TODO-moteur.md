# TODO moteur

Ce qui a été repéré pendant l'extraction et volontairement laissé de côté, pour
que l'opération reste un déplacement et non une réécriture.

---

## 1. Faire migrer le pipeline de jeu — premier chantier de la session suivante

**Ce n'est pas un nettoyage optionnel : c'est le point de départ de la couche
générative.**

`Atelier._melodieJouee()` (dans Bizet) contient la logique qui transforme la
partition écrite en partition jouée :

```dart
_melodie!.decoupee().enMode(majeur).transposee(octave * 12)
// puis tempo et instrument
```

L'ordre compte : le mode se change **avant** la transposition, pour que les
degrés se comptent depuis la tonique écrite et non depuis celle où
l'utilisateur a déplacé le morceau. Trois autres méthodes de `Atelier` sont du
même ressort :

- `_fenetreBalancement()` — la paire de notes que le balancement décale,
  déduite de la pulsation du morceau ;
- `instrumentDisponible()` — la sonorité la plus proche parmi celles que le
  SoundFont possède réellement ;
- l'ordre d'application des réglages au moment de rendre.

La couche générative se résume à : tirer des paramètres, appliquer ce pipeline,
rendre. C'est donc exactement ce que `Capture` appellera. Il faut le faire
descendre dans le moteur, débarrassé du `ChangeNotifier` — probablement sous
forme d'un objet de réglages sans état, que `Atelier` détiendra et que
`GenerativePlayer` fabriquera.

---

## 2. Deux copies de `_evenements()` — risque de divergence

`RenduAudio._evenements()` (en secondes) et `ExportMusical._evenements()` (en
tics MIDI) font le même travail avec les mêmes règles de tri : à instant égal,
on éteint avant d'allumer. Elles diffèrent par l'unité de temps et par le
moment où le balancement s'applique.

Elles sont maintenant voisines dans le même paquet, ce qui rend la fusion
facile. À faire, parce que **deux jeux de règles qui doivent rester synchronisés
finissent toujours par se désynchroniser** : une correction apportée à l'une
sans l'autre donnerait un fichier MIDI qui ne sonne pas comme la lecture.

---

## 3. Sortie audio pour Capture — décision reportée

Le moteur fabrique du PCM mais ne le joue pas : le transport
(`flutter_pcm_sound`, curseur, boucle, latence) est resté dans Bizet, parce
qu'il dépend de la plateforme.

Capture aura besoin de jouer du son. Trois issues, à trancher quand on saura ce
que Capture a déjà :

1. Capture a sa propre couche audio — probable pour un jeu, et rien à faire ;
2. on extrait un paquet compagnon `bizet_engine_flutter` portant
   `flutter_pcm_sound`, partagé par les deux applications ;
3. le moteur expose une interface abstraite de sortie que chaque hôte
   implémente.

Ne rien décider avant d'avoir regardé Capture.

---

## 4. Résolution des `\include` — au mauvais endroit

`MutopiaService._collecterInclusions()` (dans Bizet) rapatrie les fichiers
qu'une partition réclame, avant de passer la main au parseur. C'est
arguablement du ressort du parseur, pas du service de téléchargement.

Sans objet aujourd'hui : Capture embarquera un `.ly` unique et aplati. À
déplacer le jour où un hôte voudra ouvrir un fichier à inclusions sans passer
par le réseau.

---

## 5. Aucun paramètre n'est modifiable à chaud — c'est voulu

Constat de l'extraction : `rendre()` fabrique le PCM du **morceau entier** avant
qu'il soit joué. Changer un réglage impose de tout re-rendre et de reprendre au
même endroit (`Atelier.appliquer()`).

Ce n'est pas une limite à lever. Accélérer un PCM déjà rendu monterait la
hauteur : ce serait une transposition accidentelle, pas un changement de tempo.

Donc, pour la couche générative : **tous les paramètres musicaux se changent en
frontière de boucle, sans exception.** Seul le volume reste modifiable à chaud,
puisque c'est un simple gain sur les échantillons. Il n'y aura pas de
`setTempoFactor()`. Une API avec une seule règle vaut mieux qu'une API avec
deux catégories à expliquer.

---

## 6. Coût mémoire du pré-rendu — contrainte de conception pour Capture

Le pré-rendu garde le morceau entier en PCM en mémoire : environ **10 Mo par
minute** en mono 16 bits à 44,1 kHz, le double en stéréo. Et comme la variante
suivante se calcule pendant que la précédente joue, il faut compter les deux à
la fois.

Une boucle de trois minutes coûterait donc 30 à 60 Mo, dans un jeu qui a déjà
ses textures et ses sons. Ça oriente Capture vers des boucles courtes, du mono,
et éventuellement une fréquence d'échantillonnage réduite.

Ce n'est pas un défaut à corriger, c'est un chiffre à connaître avant de choisir
la durée des boucles.

---

## 7. Poids du SoundFont

Le code du moteur est négligeable ; le SoundFont fait tout le poids (17 Mo pour
`Bizet19.sf2`). Cible pour Capture : 2 à 4 Mo pour une banque sur mesure de
quelques instruments — le piano est de loin le plus lourd. Prévoir à terme un
mode « MIDI seul », sans synthèse : `ExportMusical.versMidi()` est déjà dans le
paquet et n'a besoin d'aucun SoundFont.

---

## 8. Table d'instruments et compatibilité — FAIT (4 août 2026)

`lib/src/instruments/` : le catalogue des 20 sonorités de Bizet_v3.sf2
(tessiture musicale, enveloppe, famille) et la règle de compatibilité
(`evaluer`, `evaluerContre`), source de vérité unique pour le grisage des
octaves, l'épaisseur et les suggestions d'associations. Les tessitures sont
des valeurs de départ à ajuster à l'oreille ; les tests épinglent des
verdicts, pas des seuils.
