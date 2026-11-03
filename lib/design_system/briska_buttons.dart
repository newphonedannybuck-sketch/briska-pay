import 'package:flutter/material.dart';

import 'briska_radius.dart';

class BriskaButtons {
  const BriskaButtons._();

  static ButtonStyle destructive(BuildContext context) {
    return ElevatedButton.styleFrom(
      backgroundColor: Theme.of(context).colorScheme.error,
      foregroundColor: Colors.white,
      minimumSize: const Size(0, 52),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(BriskaRadii.lg),
      ),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );
  }
}
