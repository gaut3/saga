import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'server_scope.dart';
import 'user_box.dart';

class WantToReadStore {
  static const _boxName = 'want_to_read';
  static late Box _box;

  static final _revision = ValueNotifier<int>(0);
  static ValueNotifier<int> get revisionNotifier => _revision;

  static Future<void> init(List<int> encKey) async {
    _box = await openUserBox(_boxName, encKey);
  }

  // Scoped by server — see server_scope.dart.
  static bool isWanted(String ratingKey) =>
      _box.get(ServerScope.key(ratingKey)) == true;

  static Future<void> toggle(String ratingKey) async {
    final key = ServerScope.key(ratingKey);
    if (isWanted(ratingKey)) {
      await _box.delete(key);
    } else {
      await _box.put(key, true);
    }
    _revision.value++;
  }

  static Set<String> get all => {
        for (final key in _box.keys)
          if (_box.get(key) == true)
            if (ServerScope.ratingKeyOf(key.toString()) case final rk?) rk,
      };
}
