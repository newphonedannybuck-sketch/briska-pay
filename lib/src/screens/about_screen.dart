part of '../briska_app.dart';

class AboutBriskaScreen extends StatelessWidget {
  const AboutBriskaScreen({this.showTesterTools, super.key});

  final bool? showTesterTools;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('About Briska Pay')),
      body: AppPage(
        topPadding: 8,
        child: FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snapshot) {
            final info = snapshot.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: BriskaLogo(size: 80)),
                const SizedBox(height: 18),
                Center(
                  child: Text(
                    'Briska Pay',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                ),
                const Center(child: Text('Work. Track. Get Paid.')),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(BriskaSpacing.cardPadding),
                    child: Column(
                      children: [
                        _AboutRow(
                          label: 'Version',
                          value: info == null
                              ? 'Loading...'
                              : '${info.version} (${info.buildNumber})',
                        ),
                        const Divider(height: 24),
                        const _AboutRow(
                          label: 'Developed by',
                          value: 'Berkzerker',
                        ),
                        const Divider(height: 24),
                        const _AboutRow(
                          label: 'Support',
                          value: briskaSupportEmail,
                        ),
                        const Divider(height: 24),
                        const _AboutRow(
                          label: 'Copyright',
                          value: '© 2026 Berkzerker',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: BriskaSpacing.xl),
                const SectionHeading(title: 'Support & legal'),
                const SizedBox(height: BriskaSpacing.sm),
                _AboutAction(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy Policy',
                  onTap: () => Navigator.of(context).push(
                    _BriskaPageRoute(
                      child: const LegalTextScreen(
                        title: 'Privacy Policy',
                        assetPath: 'assets/legal/privacy_policy.md',
                      ),
                    ),
                  ),
                ),
                _AboutAction(
                  icon: Icons.gavel_outlined,
                  title: 'Terms of Use',
                  onTap: () => Navigator.of(context).push(
                    _BriskaPageRoute(
                      child: const LegalTextScreen(
                        title: 'Terms of Use',
                        assetPath: 'assets/legal/terms_disclaimer.md',
                      ),
                    ),
                  ),
                ),
                _AboutAction(
                  icon: Icons.support_agent_outlined,
                  title: 'Support',
                  onTap: () => Navigator.of(
                    context,
                  ).push(_BriskaPageRoute(child: const SupportScreen())),
                ),
                if (showTesterTools ?? showBetaTools)
                  _AboutAction(
                    icon: Icons.fact_check_outlined,
                    title: 'Beta Checklist',
                    onTap: () => Navigator.of(context).push(
                      _BriskaPageRoute(child: const BetaChecklistScreen()),
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: 'Briska Pay',
                    applicationIcon: const BriskaLogo(size: 48),
                  ),
                  icon: const Icon(Icons.article_outlined),
                  label: const Text('Open Source Licences'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
    );
    const valueStyle = TextStyle(fontWeight: FontWeight.w700);
    if (value.length > 22) {
      return SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: labelStyle),
            const SizedBox(height: BriskaSpacing.xs),
            Text(value, style: valueStyle),
          ],
        ),
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 118, child: Text(label, style: labelStyle)),
        Expanded(child: Text(value, style: valueStyle)),
      ],
    );
  }
}

class _AboutAction extends StatelessWidget {
  const _AboutAction({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}

