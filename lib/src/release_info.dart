const briskaReleaseTrack = String.fromEnvironment(
  'BRISKA_RELEASE_TRACK',
  defaultValue: 'production',
);

bool isTesterReleaseTrack(String value) {
  return switch (value.trim().toLowerCase()) {
    'beta' || 'development' || 'dev' => true,
    _ => false,
  };
}

String get briskaReleaseLabel {
  return switch (briskaReleaseTrack.trim().toLowerCase()) {
    'release-candidate' || 'rc' => 'Briska Pay 1.0 Release Candidate',
    'production' || 'release' => 'Production',
    'development' || 'dev' => 'Development',
    'beta' => 'Beta',
    _ => 'Production',
  };
}

bool get isBriskaBeta => briskaReleaseTrack.trim().toLowerCase() == 'beta';

bool get showBetaTools => isTesterReleaseTrack(briskaReleaseTrack);
