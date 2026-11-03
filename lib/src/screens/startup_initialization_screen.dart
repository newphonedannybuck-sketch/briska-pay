part of '../briska_app.dart';

class StartupInitializationScreen extends StatelessWidget {
  const StartupInitializationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Semantics(
            container: true,
            label: 'Briska Pay is starting',
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BriskaLogo(size: 72),
                  const SizedBox(height: 18),
                  Text(
                    'Briska Pay',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 18),
                  if (reduceMotion)
                    const Icon(Icons.lock_outline_rounded)
                  else
                    const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

