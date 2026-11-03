part of '../briska_app.dart';

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
            return SelectableText(
              text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                height: 1.55,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            );
          },
        ),
      ),
    );
  }
}

