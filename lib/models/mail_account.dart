/// Ein eingerichtetes Mail-Konto. Das Passwort wird NICHT hier gespeichert,
/// sondern verschlüsselt im Systemschlüsselbund (siehe AccountStore).
class MailAccount {
  const MailAccount({
    required this.provider,
    required this.email,
    required this.imapHost,
    required this.imapPort,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpImplicitTls,
  });

  final String provider;
  final String email;
  final String imapHost;
  final int imapPort;
  final String smtpHost;
  final int smtpPort;

  /// true = Verbindung ist ab Start verschlüsselt (Port 465).
  /// false = STARTTLS nach dem Verbindungsaufbau (Port 587).
  final bool smtpImplicitTls;

  Map<String, Object> toJson() => {
        'provider': provider,
        'email': email,
        'imapHost': imapHost,
        'imapPort': imapPort,
        'smtpHost': smtpHost,
        'smtpPort': smtpPort,
        'smtpImplicitTls': smtpImplicitTls,
      };

  factory MailAccount.fromJson(Map<String, dynamic> json) => MailAccount(
        provider: json['provider'] as String,
        email: json['email'] as String,
        imapHost: json['imapHost'] as String,
        imapPort: json['imapPort'] as int,
        smtpHost: json['smtpHost'] as String,
        smtpPort: json['smtpPort'] as int,
        smtpImplicitTls: json['smtpImplicitTls'] as bool,
      );
}

/// Voreinstellungen für bekannte Provider. Die Hostnamen bitte vor dem
/// ersten Test mit den Angaben in der Provider-Hilfe abgleichen.
class ProviderPreset {
  const ProviderPreset({
    required this.name,
    required this.imapHost,
    required this.smtpHost,
    required this.smtpPort,
    required this.smtpImplicitTls,
  });

  final String name;
  final String imapHost;
  final String smtpHost;
  final int smtpPort;
  final bool smtpImplicitTls;

  static const freenet = ProviderPreset(
    name: 'Freenet',
    imapHost: 'imap.freenet.de',
    smtpHost: 'smtp.freenet.de',
    smtpPort: 465,
    smtpImplicitTls: true,
  );

  static const ionos = ProviderPreset(
    name: 'IONOS',
    imapHost: 'imap.ionos.de',
    smtpHost: 'smtp.ionos.de',
    smtpPort: 587,
    smtpImplicitTls: false,
  );

  static const all = [freenet, ionos];
}
