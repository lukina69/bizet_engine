// FICHIER ENGENDRÉ par tool/mesure_poids.dart — ne pas le
// retoucher à la main : la prochaine mesure l'écraserait.
//
// 120 sonorités, mesurées sur l'édition « instruments_v2 ».

/// Poids naturel de chaque sonorité, en décibels sous la plus
/// forte de la banque : l'écart qu'une voix doit compenser
/// pour peser autant qu'une autre.
///
/// Passer par [poidsNaturel] plutôt que par cette table : une
/// sonorité inconnue doit rester une absence, jamais un zéro —
/// zéro voudrait dire « aussi forte que la plus forte ».
const Map<int, double> poidsMesures = {
  0: -6.2, // Stereo Grand
  1: -6.5, // Bright Grand
  2: -13.3, // Electric Grand
  3: -7.9, // Honky-Tonk
  4: -10.0, // Tine Electric Piano
  5: -10.5, // FM Electric Piano
  6: -15.0, // Harpsichord
  7: -11.9, // Clavinet
  8: -11.8, // Celesta
  9: -13.1, // Glockenspiel
  10: -18.9, // Music Box
  11: -10.8, // Vibraphone
  12: -10.1, // Marimba
  13: -17.2, // Xylophone
  14: -11.1, // Tubular Bells
  15: -15.7, // Dulcimer
  16: -15.9, // Drawbar Organ
  17: -7.9, // Percussive Organ
  18: -10.7, // Rock Organ
  19: -11.6, // Church Organ
  20: -14.0, // Reed Organ
  21: -14.1, // Accordion
  22: -13.3, // Harmonica
  23: -13.1, // Bandoneon
  24: -11.8, // Nylon String Guitar
  25: -14.3, // Steel String Guitar
  26: -15.2, // Jazz Guitar
  27: -12.3, // Clean Guitar
  28: -9.7, // Palm Muted Guitar
  29: -13.6, // Overdrive Guitar
  30: -12.6, // Distortion Guitar
  31: -12.6, // Guitar Harmonics
  32: -5.5, // Acoustic Bass
  33: -7.9, // Fingered Bass
  34: -8.4, // Picked Bass
  35: -7.9, // Fretless Bass
  36: -15.0, // Slap Bass
  37: -10.9, // Pop Bass
  38: -6.7, // Synth Bass 1
  39: -9.7, // Synth Bass 2
  40: -9.6, // Violin
  41: -10.4, // Viola
  42: -5.0, // Cello
  43: -10.1, // Contrabass
  44: -13.7, // Strings Tremolo
  45: -11.0, // Strings Pizzicato
  46: -8.2, // Harp
  47: -16.6, // Timpani
  48: -10.7, // Strings Fast
  49: -10.7, // Strings Slow
  50: -12.5, // Synth Strings 1
  51: -13.4, // Synth Strings 2
  52: -11.1, // Choir Aahs
  53: -8.1, // Voice Oohs
  54: -12.3, // Synth Voice
  55: -11.0, // Orchestra Hit
  56: -11.0, // Trumpet
  57: -3.3, // Trombone
  58: -3.2, // Tuba
  59: -12.7, // Harmon Mute Trumpet
  60: -5.3, // French Horns
  61: -9.3, // Brass Section
  62: -9.1, // Synth Brass 1
  63: -9.5, // Synth Brass 2
  64: -11.2, // Soprano Sax
  65: -9.2, // Alto Sax
  66: -9.6, // Tenor Sax
  67: -12.2, // Baritone Sax
  68: -7.4, // Oboe
  69: -11.5, // English Horn
  70: -8.0, // Bassoon
  71: -11.7, // Clarinet
  72: -9.1, // Piccolo
  73: -8.9, // Flute
  74: -10.1, // Recorder
  75: -10.0, // Pan Flute
  76: -6.0, // Bottle Chiff
  77: -4.9, // Shakuhachi
  78: -4.5, // Whistle
  79: -3.6, // Ocarina
  80: -6.9, // Square Lead
  81: -7.9, // Saw Lead
  82: -7.4, // Calliope Lead
  83: -3.4, // Chiffer Lead
  84: -9.7, // Charang
  85: -2.7, // Solo Vox
  86: -7.1, // 5th Saw Wave
  87: 0.0, // Bass & Lead
  88: -7.9, // Fantasia
  89: -11.7, // Warm Pad
  90: -3.0, // Polysynth
  91: -6.2, // Space Voice
  92: -11.5, // Bowed Glass
  93: -11.8, // Metal Pad
  94: -8.1, // Halo Pad
  95: -10.7, // Sweep Pad
  96: -9.2, // Ice Rain
  97: -1.6, // Soundtrack
  98: -12.7, // Crystal
  99: -9.2, // Atmosphere
  100: -9.4, // Brightness
  101: -7.8, // Goblin
  102: -11.4, // Echo Drops
  103: -7.2, // Star Theme
  104: -13.3, // Sitar
  105: -5.9, // Banjo
  106: -17.2, // Shamisen
  107: -9.8, // Koto
  108: -9.2, // Kalimba
  109: -7.2, // Bagpipe
  110: -13.1, // Fiddle
  111: -9.9, // Shenai
  112: -9.8, // Tinker Bell
  113: -17.4, // Agogo
  114: -11.4, // Steel Drums
  115: -17.8, // Woodblock
  116: -9.3, // Taiko Drum
  117: -12.2, // Melodic Tom
  118: -4.4, // Synth Drum
  119: -11.0, // Reverse Cymbal
};

/// Le poids naturel de [programme], ou nul si la banque ne
/// connaît pas cette sonorité — auquel cas il n'y a rien à
/// égaliser, et mieux vaut ne rien corriger que corriger au
/// hasard.
double? poidsNaturel(int programme) => poidsMesures[programme];
