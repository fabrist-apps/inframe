export 'web_migration_lock_core.dart';
export 'web_migration_lock_unsupported.dart'
    if (dart.library.js_interop) 'web_migration_lock_browser.dart';
