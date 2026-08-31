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
  0: -7.4, // Stereo Grand
  1: -7.5, // Bright Grand
  2: -12.3, // Electric Grand
  3: -9.3, // Honky-Tonk
  4: -7.6, // Tine Electric Piano
  5: -8.2, // FM Electric Piano
  6: -15.1, // Harpsichord
  7: -12.0, // Clavinet
  8: -13.5, // Celesta
  9: -14.9, // Glockenspiel
  10: -22.6, // Music Box
  11: -11.0, // Vibraphone
  12: -13.5, // Marimba
  13: -20.6, // Xylophone
  14: -11.5, // Tubular Bells
  15: -18.5, // Dulcimer
  16: -13.3, // Drawbar Organ
  17: -7.7, // Percussive Organ
  18: -8.8, // Rock Organ
  19: -11.2, // Church Organ
  20: -10.2, // Reed Organ
  21: -12.2, // Accordion
  22: -12.3, // Harmonica
  23: -11.3, // Bandoneon
  24: -13.6, // Nylon String Guitar
  25: -15.7, // Steel String Guitar
  26: -17.4, // Jazz Guitar
  27: -11.0, // Clean Guitar
  28: -14.3, // Palm Muted Guitar
  29: -10.7, // Overdrive Guitar
  30: -11.9, // Distortion Guitar
  31: -8.8, // Guitar Harmonics
  32: -6.2, // Acoustic Bass
  33: -6.2, // Fingered Bass
  34: -7.3, // Picked Bass
  35: -5.2, // Fretless Bass
  36: -13.5, // Slap Bass
  37: -13.2, // Pop Bass
  38: -7.7, // Synth Bass 1
  39: -12.0, // Synth Bass 2
  40: -9.5, // Violin
  41: -11.4, // Viola
  42: -7.1, // Cello
  43: -10.1, // Contrabass
  44: -14.5, // Strings Tremolo
  45: -14.6, // Strings Pizzicato
  46: -9.2, // Harp
  47: -19.3, // Timpani
  48: -12.5, // Strings Fast
  49: -13.9, // Strings Slow
  50: -13.4, // Synth Strings 1
  51: -13.7, // Synth Strings 2
  52: -13.4, // Choir Aahs
  53: -9.0, // Voice Oohs
  54: -11.4, // Synth Voice
  55: -11.9, // Orchestra Hit
  56: -9.5, // Trumpet
  57: 0.0, // Trombone
  58: -0.8, // Tuba
  59: -9.5, // Harmon Mute Trumpet
  60: -6.6, // French Horns
  61: -7.8, // Brass Section
  62: -9.8, // Synth Brass 1
  63: -9.9, // Synth Brass 2
  64: -11.9, // Soprano Sax
  65: -6.8, // Alto Sax
  66: -7.9, // Tenor Sax
  67: -11.1, // Baritone Sax
  68: -7.8, // Oboe
  69: -11.0, // English Horn
  70: -6.6, // Bassoon
  71: -8.4, // Clarinet
  72: -8.2, // Piccolo
  73: -8.4, // Flute
  74: -8.4, // Recorder
  75: -8.0, // Pan Flute
  76: -6.2, // Bottle Chiff
  77: -5.8, // Shakuhachi
  78: -3.7, // Whistle
  79: -4.6, // Ocarina
  80: -7.5, // Square Lead
  81: -7.0, // Saw Lead
  82: -9.8, // Calliope Lead
  83: -4.8, // Chiffer Lead
  84: -6.2, // Charang
  85: -4.4, // Solo Vox
  86: -7.4, // 5th Saw Wave
  87: -4.4, // Bass & Lead
  88: -7.5, // Fantasia
  89: -17.5, // Warm Pad
  90: -3.5, // Polysynth
  91: -8.5, // Space Voice
  92: -11.1, // Bowed Glass
  93: -13.7, // Metal Pad
  94: -8.9, // Halo Pad
  95: -13.5, // Sweep Pad
  96: -9.9, // Ice Rain
  97: -6.4, // Soundtrack
  98: -12.3, // Crystal
  99: -10.5, // Atmosphere
  100: -8.5, // Brightness
  101: -16.0, // Goblin
  102: -11.7, // Echo Drops
  103: -8.7, // Star Theme
  104: -14.5, // Sitar
  105: -13.2, // Banjo
  106: -19.7, // Shamisen
  107: -12.7, // Koto
  108: -19.3, // Kalimba
  109: -8.5, // Bagpipe
  110: -13.0, // Fiddle
  111: -8.7, // Shenai
  112: -11.7, // Tinker Bell
  113: -23.3, // Agogo
  114: -13.8, // Steel Drums
  115: -25.2, // Woodblock
  116: -12.8, // Taiko Drum
  117: -17.8, // Melodic Tom
  118: -6.9, // Synth Drum
  119: -18.5, // Reverse Cymbal
};

/// Le poids naturel de [programme], ou nul si la banque ne
/// connaît pas cette sonorité — auquel cas il n'y a rien à
/// égaliser, et mieux vaut ne rien corriger que corriger au
/// hasard.
double? poidsNaturel(int programme) => poidsMesures[programme];
