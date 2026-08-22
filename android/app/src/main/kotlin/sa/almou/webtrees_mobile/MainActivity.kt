package sa.almou.webtrees_mobile

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity, not FlutterActivity: local_auth hosts the system
// biometric prompt in a fragment and fails at runtime without it.
class MainActivity : FlutterFragmentActivity()
