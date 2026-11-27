import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Systembenachrichtigungen für neue Mails (Android und Windows).
/// Fehler werden geschluckt, damit die App auch ohne Benachrichtigungen läuft.
class Notifier {
  Notifier._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    if (_ready) return;
    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          windows: WindowsInitializationSettings(
            appName: 'Mail',
            appUserModelId: 'de.anton.mail.app',
            guid: '2b8f9d4e-6c1a-4f7e-9a3b-5d2e8c7f1a90',
          ),
        ),
      );
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  static Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'new_mail',
            'Neue Mails',
            channelDescription: 'Hinweise bei neuen E-Mails',
            importance: Importance.high,
            priority: Priority.high,
          ),
          windows: WindowsNotificationDetails(),
        ),
      );
    } catch (_) {
      // Benachrichtigung nicht anzeigbar: ignorieren.
    }
  }
}
