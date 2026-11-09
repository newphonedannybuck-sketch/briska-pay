part of '../briska_app.dart';

class StartupRecoveryScreen extends StatelessWidget {
  const StartupRecoveryScreen({
    required this.error,
    required this.dataIsCorrupt,
    this.restoreRecoveryRequired = false,
    required this.onRetry,
    required this.onRestoreBackup,
    required this.onResetLocalData,
    super.key,
  });

  final String error;
  final bool dataIsCorrupt;
  final bool restoreRecoveryRequired;
  final Future<void> Function() onRetry;
  final Future<void> Function() onRestoreBackup;
  final Future<void> Function() onResetLocalData;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppPage(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BriskaLogo(size: 56),
                    const SizedBox(height: 18),
                    Text(
                      restoreRecoveryRequired
                          ? "Briska Pay couldn't complete the restore safely"
                          : dataIsCorrupt
                          ? "Briska Pay couldn't load your saved data"
                          : 'Briska Pay could not read local data',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      restoreRecoveryRequired
                          ? 'The stored data must be checked before you can continue. Changes are blocked. Tap Retry to recover and reload your saved data.'
                          : dataIsCorrupt
                          ? 'Your saved information appears to be damaged or unreadable. It has not been deleted or replaced.'
                          : 'Your data has not been erased. Try again, restore a backup, or reset this installation after confirmation.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: 12),
                      SelectableText(
                        error,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    BriskaPrimaryButton(
                      icon: Icons.refresh_rounded,
                      label: 'Retry',
                      onPressed: onRetry,
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: restoreRecoveryRequired
                          ? null
                          : onRestoreBackup,
                      icon: const Icon(Icons.restore_outlined),
                      label: const Text('Restore backup'),
                    ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: restoreRecoveryRequired
                          ? null
                          : onResetLocalData,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Reset local data'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
