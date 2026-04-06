/// Slash command metadata for autocomplete display.
class SlashCommand {
  final String name;
  final String description;
  final String? args;
  final bool hasArgs;

  /// If true, the SDK handles execution via parseCommands.
  /// If false, Gloam intercepts before sending to the SDK.
  final bool isSdkCommand;

  const SlashCommand({
    required this.name,
    required this.description,
    this.args,
    this.hasArgs = true,
    this.isSdkCommand = true,
  });
}

/// All supported slash commands, ordered by priority for display.
const slashCommands = <SlashCommand>[
  // ── Tier 1: Common ──
  SlashCommand(
    name: 'me',
    description: 'Send an action message',
    args: '<action>',
  ),
  SlashCommand(
    name: 'plain',
    description: 'Send without markdown formatting',
    args: '<text>',
  ),
  SlashCommand(
    name: 'join',
    description: 'Join a room by alias or ID',
    args: '<room>',
  ),
  SlashCommand(
    name: 'invite',
    description: 'Invite a user to this room',
    args: '<@user:server>',
  ),
  SlashCommand(
    name: 'leave',
    description: 'Leave this room',
    hasArgs: false,
  ),
  SlashCommand(
    name: 'nick',
    description: 'Change your display name',
    args: '<name>',
    isSdkCommand: false,
  ),
  SlashCommand(
    name: 'topic',
    description: 'Set the room topic',
    args: '<text>',
    isSdkCommand: false,
  ),

  // ── Tier 2: Fun text commands ──
  SlashCommand(
    name: 'shrug',
    description: r'Append ¯\_(ツ)_/¯',
    args: '[text]',
    isSdkCommand: false,
  ),
  SlashCommand(
    name: 'tableflip',
    description: 'Append (╯°□°)╯︵ ┻━┻',
    args: '[text]',
    isSdkCommand: false,
  ),
  SlashCommand(
    name: 'unflip',
    description: 'Append ┬─┬ ノ( ゜-゜ノ)',
    args: '[text]',
    isSdkCommand: false,
  ),
  SlashCommand(
    name: 'lenny',
    description: 'Append ( ͡° ͜ʖ ͡°)',
    args: '[text]',
    isSdkCommand: false,
  ),
  SlashCommand(
    name: 'spoiler',
    description: 'Send as a spoiler',
    args: '<text>',
    isSdkCommand: false,
  ),

  // ── Tier 3: Power user ──
  SlashCommand(
    name: 'op',
    description: 'Set user power level',
    args: '<@user:server> [level]',
  ),
  SlashCommand(
    name: 'kick',
    description: 'Remove a user from this room',
    args: '<@user:server>',
  ),
  SlashCommand(
    name: 'ban',
    description: 'Ban a user from this room',
    args: '<@user:server>',
  ),
  SlashCommand(
    name: 'unban',
    description: 'Unban a user',
    args: '<@user:server>',
  ),
  SlashCommand(
    name: 'ignore',
    description: 'Ignore a user\'s messages',
    args: '<@user:server>',
  ),
  SlashCommand(
    name: 'unignore',
    description: 'Stop ignoring a user',
    args: '<@user:server>',
  ),
  SlashCommand(
    name: 'myroomnick',
    description: 'Set your display name for this room',
    args: '<name>',
  ),
  SlashCommand(
    name: 'discardsession',
    description: 'Discard E2EE session keys',
    hasArgs: false,
  ),
  SlashCommand(
    name: 'clearcache',
    description: 'Clear the local cache',
    hasArgs: false,
  ),
];

/// Gloam-specific text append commands.
const _textAppends = <String, String>{
  'shrug': r'¯\_(ツ)_/¯',
  'tableflip': '(╯°□°)╯︵ ┻━┻',
  'unflip': '┬─┬ ノ( ゜-゜ノ)',
  'lenny': '( ͡° ͜ʖ ͡°)',
};

/// Check if text is a Gloam-handled command. Returns the transformed text
/// to send, or null if this is not a Gloam command (let SDK handle it).
String? handleGloamCommand(String text) {
  if (!text.startsWith('/')) return null;

  final spaceIdx = text.indexOf(' ');
  final command = (spaceIdx > 0 ? text.substring(1, spaceIdx) : text.substring(1)).toLowerCase();
  final rest = spaceIdx > 0 ? text.substring(spaceIdx + 1).trim() : '';

  // Text append commands
  if (_textAppends.containsKey(command)) {
    final suffix = _textAppends[command]!;
    return rest.isEmpty ? suffix : '$rest $suffix';
  }

  // Spoiler — wrap in HTML spoiler tags
  if (command == 'spoiler') {
    // Return null here; handled separately because it needs formatted_body
    return null;
  }

  return null;
}

/// Check if text is a /spoiler command. Returns the spoiler body or null.
String? parseSpoilerCommand(String text) {
  if (!text.startsWith('/spoiler ')) return null;
  final body = text.substring(9).trim();
  return body.isEmpty ? null : body;
}

/// Check if text is a /nick command. Returns the new name or null.
String? parseNickCommand(String text) {
  if (!text.startsWith('/nick ')) return null;
  final name = text.substring(6).trim();
  return name.isEmpty ? null : name;
}

/// Check if text is a /topic command. Returns the new topic or null.
String? parseTopicCommand(String text) {
  if (!text.startsWith('/topic ')) return null;
  final topic = text.substring(7).trim();
  return topic.isEmpty ? null : topic;
}
