package com.bkdash.sanitary

import io.flutter.embedding.android.FlutterFragmentActivity

// local_auth (fingerprint) requires a FragmentActivity, not a plain FlutterActivity.
class MainActivity : FlutterFragmentActivity()
