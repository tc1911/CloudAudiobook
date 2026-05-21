import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import '../theme_manager.dart';

class ThemeSettingsScreen extends StatefulWidget {
  final ThemeManager themeManager;
  const ThemeSettingsScreen({super.key, required this.themeManager});

  @override
  State<ThemeSettingsScreen> createState() => _ThemeSettingsScreenState();
}

class _ThemeSettingsScreenState extends State<ThemeSettingsScreen> {
  late String _mode;
  late Color _seedColor;

  @override
  void initState() {
    super.initState();
    _mode = widget.themeManager.mode;
    _seedColor = widget.themeManager.seedColor;
  }

  void _setMode(String mode) {
    setState(() => _mode = mode);
    widget.themeManager.setMode(mode);
  }

  void _pickColor() async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (ctx) => _ColorPickerDialog(current: _seedColor),
    );
    if (picked != null) {
      setState(() => _seedColor = picked);
      widget.themeManager.setSeedColor(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('主题'), centerTitle: true),
      body: ListView(
        children: [
          // Mode selector
          // Only show Monet option on Android
          if (Platform.isAndroid)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'dynamic', label: Text('莫奈取色'), icon: Icon(Icons.auto_awesome)),
                  ButtonSegment(value: 'system', label: Text('预设'), icon: Icon(Icons.palette)),
                ],
                selected: {_mode},
                onSelectionChanged: (v) => _setMode(v.first),
              ),
            ),
          // Custom color picker
          if (_mode != 'dynamic') ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('种子色'),
                  const Spacer(),
                  GestureDetector(
                    onTap: _pickColor,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _seedColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.outline, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Preset colors
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ThemeManager.builtInColors.map((preset) {
                  final isSelected = _seedColor.value == preset.color.value;
                  return ChoiceChip(
                    label: Text(preset.name),
                    selected: isSelected,
                    selectedColor: preset.color,
                    avatar: CircleAvatar(
                      backgroundColor: preset.color,
                      radius: 10,
                    ),
                    onSelected: (_) {
                      setState(() => _seedColor = preset.color);
                      widget.themeManager.setSeedColor(preset.color);
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            // Custom color button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: _pickColor,
                icon: const Icon(Icons.colorize),
                label: const Text('自定义颜色'),
              ),
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

/// Simple color picker dialog
class _ColorPickerDialog extends StatelessWidget {
  final Color current;
  const _ColorPickerDialog({required this.current});

  static const _customColors = [
    0xFFD32F2F, 0xFFC2185B, 0xFF7B1FA2, 0xFF512DA8,
    0xFF303F9F, 0xFF1976D2, 0xFF0288D1, 0xFF0097A7,
    0xFF00796B, 0xFF388E3C, 0xFF689F38, 0xFFAFB42B,
    0xFFFBC02D, 0xFFFFA000, 0xFFF57C00, 0xFFE64A19,
    0xFF5D4037, 0xFF616161, 0xFF455A64,
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('选择颜色'),
      content: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _customColors.map((c) {
          final color = Color(c);
          return GestureDetector(
            onTap: () => Navigator.pop(context, color),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: current.value == c
                    ? Border.all(color: Colors.white, width: 3)
                    : null,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
