# Journal des versions

## 0.1.0

Première version : extraction du cœur musical de Bizet, sans changement de
comportement.

- Modèle musical : `Note`, `Mesure`, `Melodie`, `Armure`, `Balancement`,
  `Epaisseur`, `Reverberation`.
- Lecture de partitions LilyPond : `LilypondParser`.
- Rendu sonore par SoundFont : `RenduAudio`.
- Export MIDI et WAV : `ExportMusical`.
