enum HudaViseme {
  wo('WO'),
  thi('Thi'),
  tha('Tha'),
  sh('SH'),
  sie('SIE'),
  ng('NG'),
  l('L'),
  r('R'),
  k('K'),
  h('H'),
  fv('FV'),
  ey('EY'),
  dtn('DTN'),
  ah('Ah');

  const HudaViseme(this.riveValue);

  final String riveValue;

  static HudaViseme fromRiveValue(String value) {
    return HudaViseme.values.firstWhere(
      (viseme) => viseme.riveValue == value,
      orElse: () => throw ArgumentError.value(
        value,
        'value',
        'Unknown Huda viseme value',
      ),
    );
  }
}

enum HudaPose {
  speaking('speaking'),
  listening('listening'),
  bored('bored'),
  happy('happy'),
  idle('idle');

  const HudaPose(this.riveValue);

  final String riveValue;

  static HudaPose fromRiveValue(String value) {
    return HudaPose.values.firstWhere(
      (pose) => pose.riveValue == value,
      orElse: () => throw ArgumentError.value(
        value,
        'value',
        'Unknown Huda pose value',
      ),
    );
  }
}
