import 'package:flutter/material.dart';
import '../../app_lock_service.dart';

Future<bool> showAppLockPinDialog(
  BuildContext context, {
  required bool disabling,
  required bool Function() hasPin,
  required Future<void> Function(String) onDisableLock,
  required Future<void> Function(String, String?) onSetLockPin,
}) async {
  var current = '';
  var pin = '';
  var confirmation = '';
  var saving = false;
  String? error;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, update) {
        Future<void> save() async {
          if (saving) return;
          if (!disabling && !RegExp(r'^[0-9]{4,12}$').hasMatch(pin)) {
            update(() => error = 'Use 4-12 numerical digits.');
            return;
          }
          if (!disabling && pin != confirmation) {
            update(() => error = 'PINs do not match.');
            return;
          }
          update(() {
            saving = true;
            error = null;
          });
          try {
            if (disabling) {
              await onDisableLock(current);
            } else {
              await onSetLockPin(pin, hasPin() ? current : null);
            }
            if (dialogContext.mounted) Navigator.pop(dialogContext, true);
          } on PinCooldownException catch (cooldown) {
            if (dialogContext.mounted) {
              update(() => error = cooldown.toString());
            }
          } on PinVerificationException {
            if (dialogContext.mounted) {
              update(() => error = 'Current PIN did not match.');
            }
          } catch (_) {
            if (dialogContext.mounted) {
              update(
                () => error = disabling
                    ? 'Could not update app lock.'
                    : 'Could not update PIN.',
              );
            }
          } finally {
            if (dialogContext.mounted) update(() => saving = false);
          }
        }

        Widget field(String label, ValueChanged<String> changed) => TextField(
          enabled: !saving,
          obscureText: true,
          enableSuggestions: false,
          autocorrect: false,
          keyboardType: TextInputType.number,
          onChanged: changed,
          decoration: InputDecoration(labelText: label),
        );
        return PopScope(
          canPop: !saving,
          child: AlertDialog(
            title: Text(disabling ? 'Disable App Lock' : 'Set Briska Pay PIN'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (disabling || hasPin())
                    field('Current PIN', (value) => current = value),
                  if (!disabling) ...[
                    field('PIN', (value) => pin = value),
                    field('Confirm PIN', (value) => confirmation = value),
                    const Text(
                      'Use 4-12 numerical digits. Forgotten PINs cannot be recovered securely.',
                    ),
                  ],
                  if (error != null) Text(error!),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: saving ? null : save,
                child: Text(
                  saving
                      ? 'Saving...'
                      : disabling
                      ? 'Disable App Lock'
                      : 'Save PIN',
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
  return result == true;
}
