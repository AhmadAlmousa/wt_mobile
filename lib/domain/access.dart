import 'package:meta/meta.dart';

/// What a signed-in user may do in one tree.
///
/// The values are ordered from least to most privileged, so they can be
/// compared with [index].
enum TreeRole {
  /// The tree is public, so read-only access proves nothing: webtrees shows a
  /// Visitor and a Member the same routes.
  memberOrVisitor,

  /// The tree is private, and webtrees lists a private tree only for users
  /// whose role is not Visitor — so seeing it at all proves membership.
  member,

  editor,
  moderator,
  manager,

  /// A site administrator, who is implicitly a manager of every tree.
  administrator;

  /// Whether this role may change records.
  bool get canEdit => index >= TreeRole.editor.index;

  /// Whether this role may accept or reject other people's pending changes.
  bool get canModerate => index >= TreeRole.moderator.index;

  /// Whether this role may change the tree's settings.
  bool get canManage => index >= TreeRole.manager.index;
}

/// A tree the signed-in user can reach, and their standing in it.
@immutable
final class TreeAccess {
  const TreeAccess({
    required this.name,
    required this.role,
    this.title,
    this.myXref,
  });

  /// The tree's identifier, as it appears in URLs.
  final String name;

  final TreeRole role;

  /// The tree's display title, when it could be read.
  final String? title;

  /// The XREF of the individual record this user is linked to, if any.
  ///
  /// webtrees uses it for relationship-based privacy, so a user often sees
  /// more of their own family than of anyone else's.
  final String? myXref;

  @override
  String toString() => '$name (${role.name})';
}

/// Who is signed in.
@immutable
final class Account {
  const Account({required this.username, this.realName, this.email});

  final String username;
  final String? realName;
  final String? email;

  /// The best available name to greet this person with.
  String get displayName =>
      (realName != null && realName!.isNotEmpty) ? realName! : username;
}

/// Everything the app learned about the signed-in user's access.
@immutable
final class AccessSummary {
  /// The lists are copied unmodifiable, so the `@immutable` annotation is a
  /// guarantee rather than a hope: a caller cannot reach in and rewrite what a
  /// probe reported.
  AccessSummary({
    required this.account,
    required List<TreeAccess> trees,
    required this.isAdministrator,
    List<String> warnings = const [],
  }) : trees = List.unmodifiable(trees),
       warnings = List.unmodifiable(warnings);

  final Account account;
  final List<TreeAccess> trees;

  /// Site administrators manage every tree, so the per-tree probes are skipped.
  final bool isAdministrator;

  /// Non-fatal findings, such as being unable to enumerate every tree.
  final List<String> warnings;
}
