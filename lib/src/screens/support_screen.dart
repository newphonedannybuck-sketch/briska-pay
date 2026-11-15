import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../design_system/briska_spacing.dart';
import '../support_service.dart';
import '../widgets/shared_ui.dart';

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  late final Future<BriskaDiagnostics> _diagnostics =
      BriskaSupportService.diagnostics();

  Future<void> _copyDiagnostics(BriskaDiagnostics diagnostics) async {
    await Clipboard.setData(ClipboardData(text: diagnostics.toSummary()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Support information copied.')),
    );
  }

  Future<void> _sendFeedback(BriskaDiagnostics diagnostics) async {
    final opened = await BriskaSupportService.sendFeedback(
      subject: 'Briska Pay feedback',
      diagnostics: diagnostics,
    );
    if (!mounted || opened) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('No email app is available.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Support')),
      body: AppPage(
        topPadding: 8,
        child: FutureBuilder<BriskaDiagnostics>(
          future: _diagnostics,
          builder: (context, snapshot) {
            final diagnostics = snapshot.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PageHeading(
                  title: 'Support',
                  subtitle: 'Help and information for Briska Pay.',
                ),
                const SizedBox(height: 8),
                const Text('Developer: Berkzerker'),
                const Text('Support email: $briskaSupportEmail'),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(BriskaSpacing.cardPadding),
                    child: SelectableText(
                      diagnostics?.toSummary() ??
                          'Loading support information...',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(height: 1.7),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                BriskaPrimaryButton(
                  icon: Icons.copy_rounded,
                  label: 'Copy support information',
                  onPressed: diagnostics == null
                      ? null
                      : () => _copyDiagnostics(diagnostics),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: diagnostics == null
                      ? null
                      : () => _sendFeedback(diagnostics),
                  icon: const Icon(Icons.mail_outline_rounded),
                  label: const Text('Send Feedback'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
