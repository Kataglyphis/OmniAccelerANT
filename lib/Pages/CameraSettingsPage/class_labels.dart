import 'package:omni_accelerant/src/rust/api/onnx.dart';

List<String>? _names;

/// The detector's class names at their class ids, from OxidANT; empty where the Rust core did not load.
List<String> detectorClassNames() {
  final known = _names;
  if (known != null) {
    return known;
  }
  try {
    return _names = detectorLabels();
  } catch (_) {
    return const <String>[];
  }
}

/// The German name of each class, at its class id.
const List<String> _classNamesDe = <String>[
  'Person',
  'Fahrrad',
  'Auto',
  'Motorrad',
  'Flugzeug',
  'Bus',
  'Zug',
  'Lastwagen',
  'Boot',
  'Ampel',
  'Hydrant',
  'Stoppschild',
  'Parkuhr',
  'Bank',
  'Vogel',
  'Katze',
  'Hund',
  'Pferd',
  'Schaf',
  'Kuh',
  'Elefant',
  'Bär',
  'Zebra',
  'Giraffe',
  'Rucksack',
  'Regenschirm',
  'Handtasche',
  'Krawatte',
  'Koffer',
  'Frisbee',
  'Ski',
  'Snowboard',
  'Ball',
  'Drachen',
  'Baseballschläger',
  'Baseballhandschuh',
  'Skateboard',
  'Surfbrett',
  'Tennisschläger',
  'Flasche',
  'Weinglas',
  'Tasse',
  'Gabel',
  'Messer',
  'Löffel',
  'Schüssel',
  'Banane',
  'Apfel',
  'Sandwich',
  'Orange',
  'Brokkoli',
  'Karotte',
  'Hotdog',
  'Pizza',
  'Donut',
  'Kuchen',
  'Stuhl',
  'Sofa',
  'Topfpflanze',
  'Bett',
  'Esstisch',
  'Toilette',
  'Fernseher',
  'Laptop',
  'Maus',
  'Fernbedienung',
  'Tastatur',
  'Handy',
  'Mikrowelle',
  'Ofen',
  'Toaster',
  'Spüle',
  'Kühlschrank',
  'Buch',
  'Uhr',
  'Vase',
  'Schere',
  'Teddybär',
  'Föhn',
  'Zahnbürste',
];

/// How the page names class [name]: German where [languageCode] is `de`, else the detector's name.
String classLabel(String name, String languageCode) {
  final i = detectorClassNames().indexOf(name);
  return languageCode == 'de' && i >= 0 && i < _classNamesDe.length
      ? _classNamesDe[i]
      : name;
}

/// The watched [classes] as one label, `Katze / Hund`, its first letter upper case.
String watchedLabel(List<String> classes, String languageCode) {
  final label = classes.map((c) => classLabel(c, languageCode)).join(' / ');
  return label.isEmpty ? label : label[0].toUpperCase() + label.substring(1);
}
