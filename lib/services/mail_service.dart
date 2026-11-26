import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart';

import '../models/mail_account.dart';

/// Kapselt IMAP (Empfang) und SMTP (Versand). Jede Operation öffnet eine
/// kurze Verbindung und schließt sie danach wieder. Das ist für eine
/// erste Version einfach und robust.
class MailService {
  MailService(this.account, this.password);

  final AccountConfig account;
  final String password;

  Future<ImapClient> _connectImap() async {
    final client = ImapClient(isLogEnabled: false);
    await client.connectToServer(
      account.imapHost,
      account.imapPort,
      isSecure: true,
    );
    await client.login(account.email, password);
    return client;
  }

  /// Lädt die neuesten Nachrichten aus dem Posteingang (neueste zuerst).
  Future<List<MimeMessage>> fetchInbox({int count = 30}) async {
    final client = await _connectImap();
    try {
      await client.selectInbox();
      final result = await client.fetchRecentMessages(messageCount: count);
      return result.messages;
    } finally {
      await client.logout();
    }
  }

  /// Lädt die Binärdaten eines Anhangs, z. B. eines PDFs.
  /// Die Nachricht wird mit ihrer Sequenznummer komplett nachgeladen,
  /// danach wird der Teil über seine fetchId herausgezogen.
  Future<Uint8List?> fetchAttachment(
    MimeMessage message,
    ContentInfo info,
  ) async {
    final client = await _connectImap();
    try {
      await client.selectInbox();
      final result = await client.fetchMessage(
        message.sequenceId!,
        'BODY.PEEK[]',
      );
      final full = result.messages.first;
      final part = full.getPart(info.fetchId);
      return part?.decodeContentBinary();
    } finally {
      await client.logout();
    }
  }

  /// Versendet eine einfache Textnachricht über SMTP.
  Future<void> send({
    required String to,
    required String subject,
    required String body,
  }) async {
    final domain = account.email.split('@').last;
    final smtp = SmtpClient(domain, isLogEnabled: false);
    await smtp.connectToServer(
      account.smtpHost,
      account.smtpPort,
      isSecure: account.smtpImplicitTls,
    );
    await smtp.ehlo();
    if (!account.smtpImplicitTls) {
      await smtp.startTls();
      await smtp.ehlo();
    }
    await smtp.authenticate(account.email, password);

    final builder = MessageBuilder()
      ..from = [MailAddress('', account.email)]
      ..to = [MailAddress('', to)]
      ..subject = subject
      ..text = body;
    await smtp.sendMessage(builder.buildMimeMessage());
    await smtp.quit();
  }
}
