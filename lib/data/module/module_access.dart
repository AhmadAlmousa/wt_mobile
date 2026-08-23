import '../../core/webtrees_client.dart';
import '../../domain/access.dart';
import '../../domain/notice.dart';
import '../transport.dart';
import 'module_api.dart';
import 'module_decode.dart';

/// Who is signed in, and what they may do — in one request.
///
/// The stock path costs `4 + 3·N` requests for `N` trees, and most of them
/// fetch a whole page only to throw it away because a *status code* was the
/// answer. It also cannot state a role: it infers one from which probe stopped
/// refusing, and on a **public** tree it cannot tell a Member from a Visitor
/// at all, because webtrees serves them the same routes. That ambiguity is why
/// [TreeRole.memberOrVisitor] exists.
///
/// Here the role is simply asked for, so that case never arises.
final class ModuleAccessTransport implements AccessTransport {
  ModuleAccessTransport(WebtreesClient client) : _api = ModuleApi(client);

  final ModuleApi _api;

  @override
  Future<AccessSummary> describe() async {
    final body = await _api.get(
      '$kModuleBase/access',
      probe: 'reading your access',
    );

    final account = body['account'];
    final trees = [
      for (final tree in listOf(body['trees']))
        if (tree is Map<String, Object?>) _tree(tree),
    ];

    return AccessSummary(
      account: Account(
        username: account is Map<String, Object?>
            ? stringOf(account['username']) ?? ''
            : '',
        realName: account is Map<String, Object?>
            ? stringOf(account['realName'])
            : null,
        email: account is Map<String, Object?>
            ? stringOf(account['email'])
            : null,
      ),
      trees: trees,
      isAdministrator: body['isAdministrator'] == true,
      warnings: [if (trees.isEmpty) const NoTreesVisible()],
    );
  }

  TreeAccess _tree(Map<String, Object?> json) => TreeAccess(
    name: stringOf(json['name']) ?? '',
    role: _role(stringOf(json['role']), private: json['private'] == true),
    title: stringOf(json['title']),
    myXref: stringOf(json['myXref']),
  );

  /// The stated role, mapped onto what the app can distinguish.
  ///
  /// The one wrinkle is `member` on a **public** tree. The app's own
  /// vocabulary keeps [TreeRole.memberOrVisitor] for exactly that case, and
  /// the interface says so rather than guessing — but here it is not a guess,
  /// so a public tree a user really is a member of is reported as membership.
  static TreeRole _role(String? name, {required bool private}) =>
      switch (name) {
        'administrator' => TreeRole.administrator,
        'manager' => TreeRole.manager,
        'moderator' => TreeRole.moderator,
        'editor' => TreeRole.editor,
        'member' => TreeRole.member,
        // A visitor on a public tree is what `memberOrVisitor` describes, and
        // the app already words that honestly.
        _ => private ? TreeRole.member : TreeRole.memberOrVisitor,
      };
}
