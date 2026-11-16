import '../../design_system/briska_cards.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/shared_ui.dart';

class LegalTextScreen extends StatelessWidget {
  const LegalTextScreen({
    required this.title,
    required this.assetPath,
    super.key,
  });

  final String title;
  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: AppPage(
        child: FutureBuilder<String>(
          future: rootBundle.loadString(assetPath),
          builder: (context, snapshot) {
            final text = snapshot.data ?? 'Loading...';
            return BriskaCard(
              padding: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: SelectableText(
                  text,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    height: 1.7,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
