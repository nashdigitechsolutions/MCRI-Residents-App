import 'package:flutter/material.dart';

class _EmojiEntry {
  final String char;
  final String name;
  const _EmojiEntry(this.char, this.name);
}

class _EmojiCategory {
  final String id;
  final String label;
  final String icon;
  final List<_EmojiEntry> emojis;
  const _EmojiCategory(this.id, this.label, this.icon, this.emojis);
}

const _categories = [
  _EmojiCategory('smileys', 'Smileys', '😀', [
    _EmojiEntry('😀', 'grinning'),
    _EmojiEntry('😂', 'joy'),
    _EmojiEntry('🙂', 'slight smile'),
    _EmojiEntry('😉', 'wink'),
    _EmojiEntry('😍', 'heart eyes'),
    _EmojiEntry('😘', 'kiss'),
    _EmojiEntry('😎', 'sunglasses'),
    _EmojiEntry('🤔', 'thinking'),
    _EmojiEntry('😅', 'sweat smile'),
    _EmojiEntry('😭', 'sob'),
    _EmojiEntry('😴', 'sleeping'),
    _EmojiEntry('🥳', 'party'),
    _EmojiEntry('😇', 'angel'),
    _EmojiEntry('🙃', 'upside down'),
    _EmojiEntry('😜', 'wink tongue'),
  ]),
  _EmojiCategory('gestures', 'Gestures', '👍', [
    _EmojiEntry('👍', 'thumbs up'),
    _EmojiEntry('👎', 'thumbs down'),
    _EmojiEntry('👏', 'clap'),
    _EmojiEntry('🙌', 'raised hands'),
    _EmojiEntry('🙏', 'pray'),
    _EmojiEntry('👋', 'wave'),
    _EmojiEntry('✌️', 'peace'),
    _EmojiEntry('🤝', 'handshake'),
    _EmojiEntry('💪', 'muscle'),
    _EmojiEntry('👌', 'ok hand'),
    _EmojiEntry('🤙', 'call me'),
    _EmojiEntry('☝️', 'point up'),
  ]),
  _EmojiCategory('hearts', 'Hearts', '❤️', [
    _EmojiEntry('❤️', 'red heart'),
    _EmojiEntry('🧡', 'orange heart'),
    _EmojiEntry('💛', 'yellow heart'),
    _EmojiEntry('💚', 'green heart'),
    _EmojiEntry('💙', 'blue heart'),
    _EmojiEntry('💜', 'purple heart'),
    _EmojiEntry('🖤', 'black heart'),
    _EmojiEntry('💕', 'two hearts'),
    _EmojiEntry('💯', 'hundred'),
  ]),
  _EmojiCategory('objects', 'Objects', '🎉', [
    _EmojiEntry('🎉', 'party popper'),
    _EmojiEntry('🔥', 'fire'),
    _EmojiEntry('⭐', 'star'),
    _EmojiEntry('✅', 'check mark'),
    _EmojiEntry('❌', 'cross mark'),
    _EmojiEntry('🍽️', 'plate'),
    _EmojiEntry('☕', 'coffee'),
    _EmojiEntry('🏠', 'house'),
    _EmojiEntry('📅', 'calendar'),
    _EmojiEntry('⏰', 'alarm clock'),
    _EmojiEntry('💡', 'bulb'),
    _EmojiEntry('🎂', 'cake'),
  ]),
];

final _allEmojis = _categories.expand((c) => c.emojis).toList();

class EmojiPickerPanel extends StatefulWidget {
  final void Function(String emoji) onSelect;

  const EmojiPickerPanel({super.key, required this.onSelect});

  @override
  State<EmojiPickerPanel> createState() => _EmojiPickerPanelState();
}

class _EmojiPickerPanelState extends State<EmojiPickerPanel> {
  String _query = '';
  String _activeCat = _categories.first.id;

  List<_EmojiEntry> get _results {
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      return _allEmojis.where((e) => e.name.contains(q)).toList();
    }
    return _categories.firstWhere((c) => c.id == _activeCat).emojis;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 300,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search emoji',
                prefixIcon: Icon(
                  Icons.search,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
                isDense: true,
                filled: true,
                fillColor: colors.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (_query.isEmpty)
            Row(
              children: _categories
                  .map(
                    (c) => Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _activeCat = c.id),
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 4,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: _activeCat == c.id
                                ? colors.surfaceContainerHighest
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            c.icon,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          SizedBox(
            height: 190,
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      'No emoji found',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                        ),
                    itemCount: _results.length,
                    itemBuilder: (context, i) {
                      final e = _results[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => widget.onSelect(e.char),
                        child: Center(
                          child: Text(
                            e.char,
                            style: const TextStyle(fontSize: 20),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
