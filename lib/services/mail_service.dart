import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart';

import '../models/mail_account.dart';

/// Kapselt IMAP (Empfang, Ordner, Flags, Verschieben) und SMTP (Versand).
/// Jede Operation öffnet eine kurze Verbindung, wählt bei Bedarf den Ordner
/// aus und schließt die Verbindung danach wieder.
/// Ein Anhang, der beim Senden mitgeschickt wird.
class OutgoingAttachment {
  const OutgoingAttachment(this.name, this.bytes);

  final String name;
  final Uint8List bytes;
}

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

  Future<T> _run<T>(Future<T> Function(ImapClient client) action) async {
    final client = await _connectImap();
    try {
      return await action(client);
    } finally {
      await client.logout();
    }
  }

  /// Alle Ordner des Kontos.
  Future<List<Mailbox>> listMailboxes() =>
      _run((c) => c.listMailboxes(recursive: true));

  /// Eine Seite Nachrichten eines Ordners, neueste zuerst.
  /// Seite 0 sind die neuesten Nachrichten, Seite 1 die davor usw.
  /// Enthält UID, Flags und den vollständigen Inhalt.
  Future<({List<MimeMessage> messages, bool hasMore})> fetchPage(
    Mailbox box, {
    required int page,
    int pageSize = 40,
  }) =>
      _run((c) async {
        final selected = await c.selectMailbox(box);
        final total = selected.messagesExists;
        final upper = total - page * pageSize;
        if (upper < 1) {
          return (messages: <MimeMessage>[], hasMore: false);
        }
        final lower = (upper - pageSize + 1) < 1 ? 1 : upper - pageSize + 1;
        final result = await c.fetchMessages(
          MessageSequence.fromRange(lower, upper),
          '(UID FLAGS BODY.PEEK[])',
        );
        final messages = [...result.messages]
          ..sort((a, b) => (b.sequenceId ?? 0).compareTo(a.sequenceId ?? 0));
        return (messages: messages, hasMore: lower > 1);
      });

  /// Binärdaten eines Anhangs (z. B. PDF).
  Future<Uint8List?> fetchAttachment(
    Mailbox box,
    MimeMessage message,
    ContentInfo info,
  ) =>
      _run((c) async {
        await c.selectMailbox(box);
        final result = await c.fetchMessage(
          message.sequenceId!,
          '(BODY.PEEK[])',
        );
        return result.messages.first.getPart(info.fetchId)?.decodeContentBinary();
      });

  /// Gelesen (true) bzw. ungelesen (false) markieren.
  Future<void> setSeen(Mailbox box, MimeMessage message, bool seen) =>
      _run((c) async {
        await c.selectMailbox(box);
        if (seen) {
          await c.markSeen(_uidSequence(message));
        } else {
          await c.markUnseen(_uidSequence(message));
        }
        message.isSeen = seen;
      });

  /// Mit Stern markieren (das Entfernen der Markierung ist noch nicht umgesetzt).
  Future<void> setFlagged(Mailbox box, MimeMessage message) =>
      _run((c) async {
        await c.selectMailbox(box);
        await c.markFlagged(_uidSequence(message));
        message.isFlagged = true;
      });

  /// Nur Kopfzeilen und Flags der neuesten Nachrichten (für neue-Mail-Prüfung).
  Future<List<MimeMessage>> fetchLatestHeaders(Mailbox box, {int count = 15}) =>
      _run((c) async {
        final selected = await c.selectMailbox(box);
        final total = selected.messagesExists;
        if (total < 1) return <MimeMessage>[];
        final lower = (total - count + 1) < 1 ? 1 : total - count + 1;
        final result = await c.fetchMessages(
          MessageSequence.fromRange(lower, total),
          '(UID FLAGS BODY.PEEK[HEADER])',
        );
        return result.messages;
      });

  /// Neuen Ordner anlegen. Mit [parent] (z. B. Posteingang) entsteht er darunter,
  /// sonst auf oberster Ebene. IMAP verlangt den vollständigen Pfad inkl. Namensraum.
  Future<void> createFolder(String name, {Mailbox? parent}) =>
      _run((c) async {
        final path = parent == null
            ? name
            : '${parent.encodedPath}${parent.pathSeparator}$name';
        await c.createMailbox(path);
      });

  /// Ordner umbenennen. Der neue Name bleibt auf derselben Ebene.
  Future<void> renameFolder(Mailbox box, String newName) =>
      _run((c) async {
        final sep = box.pathSeparator;
        final idx = box.encodedPath.lastIndexOf(sep);
        final parentPath =
            idx < 0 ? '' : '${box.encodedPath.substring(0, idx)}$sep';
        await c.renameMailbox(box, '$parentPath$newName');
      });

  /// Ordner löschen (samt Inhalt).
  Future<void> deleteFolder(Mailbox box) =>
      _run((c) async {
        await c.deleteMailbox(box);
      });

  /// Stern entfernen.
  Future<void> unsetFlagged(Mailbox box, MimeMessage message) =>
      _run((c) async {
        await c.selectMailbox(box);
        await c.store(
          _uidSequence(message),
          [MessageFlags.flagged],
          action: StoreAction.remove,
        );
        message.isFlagged = false;
      });

  /// Nachricht in einen anderen Ordner verschieben (z. B. Papierkorb, Spam).
  Future<void> moveMessage(Mailbox from, MimeMessage message, Mailbox to) =>
      _run((c) async {
        await c.selectMailbox(from);
        await c.uidMove(_uidSequence(message), targetMailbox: to);
      });

  /// Papierkorb des Kontos anhand der Ordner-Flags oder des Namens.
  static Mailbox? findTrash(List<Mailbox> boxes) =>
      _findBox(boxes, MailboxFlag.trash, const ['papierkorb', 'trash']);

  /// Spam-Ordner des Kontos anhand der Ordner-Flags oder des Namens.
  static Mailbox? findJunk(List<Mailbox> boxes) =>
      _findBox(boxes, MailboxFlag.junk, const ['spam', 'junk']);

  static Mailbox? _findBox(
    List<Mailbox> boxes,
    MailboxFlag flag,
    List<String> names,
  ) {
    for (final box in boxes) {
      if (box.hasFlag(flag)) return box;
    }
    for (final box in boxes) {
      if (names.contains(box.name.toLowerCase())) return box;
    }
    return null;
  }

  static MessageSequence _uidSequence(MimeMessage message) {
    final uid = message.uid;
    if (uid == null) {
      throw StateError('Nachricht hat keine UID. Bitte den Ordner neu laden.');
    }
    return MessageSequence.fromId(uid, isUid: true);
  }

  /// Versendet eine Textnachricht über SMTP.
  Future<void> send({
    required String to,
    required String subject,
    required String body,
    String cc = '',
    List<OutgoingAttachment> attachments = const [],
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
      ..cc = [
        for (final addr in cc.split(',').map((a) => a.trim()))
          if (addr.isNotEmpty) MailAddress('', addr),
      ]
      ..subject = subject
      ..text = body;
    for (final a in attachments) {
      builder.addBinary(
        a.bytes,
        MediaType.guessFromFileName(a.name),
        filename: a.name,
      );
    }
    await smtp.sendMessage(builder.buildMimeMessage());
    await smtp.quit();
  }
}
