import 'package:flutter/material.dart';
import 'package:trega/core/icons/phosphor_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase/firebase_providers.dart';
import '../../../core/models/saved_address.dart';
import '../../../core/theme/app_theme.dart';

/// The seller's saved pickup addresses (owner-only, never shown to buyers).
/// Managed here; reused with one tap in the sell flow.
class SavedAddressesScreen extends ConsumerWidget {
  static const String routeName = '/profile/addresses';

  const SavedAddressesScreen({super.key});

  Future<void> _addAddress(
      BuildContext context, WidgetRef ref, String uid,) async {
    final service = ref.read(firestoreServiceProvider);
    final labelController = TextEditingController();
    final line1Controller = TextEditingController();
    final line2Controller = TextEditingController();
    final cityController = TextEditingController();
    final stateController = TextEditingController();
    final pinController = TextEditingController();
    var saving = false;
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add pickup address'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: labelController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Label (optional)',
                    hintText: 'Home, Office…',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: line1Controller,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'House / Flat, Street',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: line2Controller,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Landmark (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: cityController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'City',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: pinController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'PIN code',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: stateController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'State',
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style: const TextStyle(
                          color: AppColors.error, fontSize: 13,),),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: saving
                  ? null
                  : () async {
                      final line1 = line1Controller.text.trim();
                      final city = cityController.text.trim();
                      final state = stateController.text.trim();
                      final pin = pinController.text.trim();
                      if (line1.length < 6) {
                        setDialogState(() => error =
                            'Add your house/flat and street.',);
                        return;
                      }
                      if (city.isEmpty || state.isEmpty) {
                        setDialogState(() => error =
                            'Add your city and state.',);
                        return;
                      }
                      if (!RegExp(r'^[1-9][0-9]{5}$').hasMatch(pin)) {
                        setDialogState(() => error =
                            'Enter a valid 6-digit PIN code.',);
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        await service.saveAddress(
                          uid,
                          SavedAddress(
                            id: '',
                            label: labelController.text.trim(),
                            line1: line1,
                            line2: line2Controller.text.trim(),
                            city: city,
                            state: state,
                            pincode: pin,
                            createdAt: DateTime.now(),
                          ),
                        );
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop();
                      } catch (_) {
                        setDialogState(() {
                          saving = false;
                          error = 'Could not save. Try again.';
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2,),
                    )
                  : const Text('Save'),
            ),
          ],
        ),
      ),
    );
    labelController.dispose();
    line1Controller.dispose();
    line2Controller.dispose();
    cityController.dispose();
    stateController.dispose();
    pinController.dispose();
  }

  Future<void> _deleteAddress(
      BuildContext context, WidgetRef ref, String uid, SavedAddress a,) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove address?'),
        content: Text(a.fullAddress),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove',
                style: TextStyle(color: AppColors.error,),),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(firestoreServiceProvider).deleteSavedAddress(uid, a.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUidProvider);
    final service = ref.watch(firestoreServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Saved pickup addresses')),
      body: uid == null
          ? const Center(child: Text('You are not signed in.'))
          : StreamBuilder<List<SavedAddress>>(
              stream: service.watchSavedAddresses(uid),
              builder: (context, snap) {
                final addresses = snap.data ?? const <SavedAddress>[];
                if (addresses.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(PhosphorIconsRegular.mapPin,
                              size: 48, color: AppColors.textSecondary,),
                          const SizedBox(height: 12),
                          Text(
                            'No saved addresses yet',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Save the places you ship from — pick one '
                            'with a tap when you list an item.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: addresses.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final a = addresses[i];
                    return Card(
                      child: ListTile(
                        leading: const Icon(PhosphorIconsRegular.mapPin,
                            color: AppColors.primary,),
                        title: Text(a.displayLabel),
                        subtitle: Text(a.fullAddress),
                        trailing: IconButton(
                          icon: const Icon(PhosphorIconsRegular.trash,
                              color: AppColors.error,),
                          onPressed: () =>
                              _deleteAddress(context, ref, uid, a),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
      floatingActionButton: uid == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _addAddress(context, ref, uid),
              icon: const Icon(PhosphorIconsRegular.plus),
              label: const Text('Add address'),
            ),
    );
  }
}
