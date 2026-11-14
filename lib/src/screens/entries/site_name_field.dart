import 'package:flutter/material.dart';
import '../../models.dart';
import '../../site_name_suggestions.dart';

class SiteNameAutocomplete extends StatefulWidget {
  const SiteNameAutocomplete({
    super.key,
    required this.controller,
    required this.entries,
    this.selectAllOnFocus = false,
    this.errorText,
    this.onChanged,
  });

  final TextEditingController controller;
  final List<WorkEntry> entries;
  final bool selectAllOnFocus;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  @override
  State<SiteNameAutocomplete> createState() => _SiteNameAutocompleteState();
}

class _SiteNameAutocompleteState extends State<SiteNameAutocomplete> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  bool _selectedForFocus = false;

  void _handleFocusChanged() {
    if (!_focusNode.hasFocus) {
      _selectedForFocus = false;
      return;
    }
    if (widget.controller.text.trim().isEmpty) {
      setState(() {});
      return;
    }
    if (!widget.selectAllOnFocus || _selectedForFocus) return;
    _selectedForFocus = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_focusNode.hasFocus) return;
      widget.controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.controller.text.length,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (value) => recentSiteNameSuggestions(
        widget.entries,
        query: value.text,
        limit: value.text.trim().isEmpty ? 5 : 8,
      ),
      onSelected: (value) {
        widget.controller
          ..text = value
          ..selection = TextSelection.collapsed(offset: value.length);
      },
      fieldViewBuilder:
          (context, textEditingController, focusNode, onFieldSubmitted) {
            return TextField(
              controller: textEditingController,
              focusNode: focusNode,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                hintText: 'Where did you work?',
                prefixIcon: Icon(Icons.work_outline_rounded),
              ).copyWith(errorText: widget.errorText),
              onChanged: widget.onChanged,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              onTap: () {
                if (textEditingController.text.trim().isEmpty) {
                  setState(() {});
                }
              },
            );
          },
      optionsViewBuilder: (context, onSelected, options) {
        final colorScheme = Theme.of(context).colorScheme;
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280, maxWidth: 360),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                itemCount: options.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_on_outlined, size: 18),
                    title: Text(option),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
