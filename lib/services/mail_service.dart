import 'dart:async';
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

  /// Höchstdauer einer Operation. Antwortet der Server nicht, bricht sie ab,
  /// statt die Oberfläche dauerhaft im Ladezustand zu lassen.
  static const _opTimeout = Duration(seconds: 45);

  Future<T> _run<T>(Future<T> Function(ImapClient client) action) async {
    ImapClient? client;
    try {
      client = await _connectImap().timeout(_opTimeout);
      return await action(client).timeout(_opTimeout);
    } on TimeoutException {
      throw StateError('Der Server antwortet nicht. Bitte erneut versuchen.');
    } finally {
      await _close(client);
    }
  }

  /// Sauber abmelden; hängt das, wird die Verbindung hart getrennt.
  Future<void> _close(ImapClient? client) async {
    if (client == null) return;
    try {
      await client.logout().timeout(const Duration(seconds: 5));
    } catch (_) {
      try {
        await client.disconnect();
      } catch (_) {}
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
        // Direkt per UID: markSeen/markUnseen senden sonst eine Sequenznummer,
        // die der Server bei manchen Nachrichten als ungültig ablehnt.
        await c.uidStore(
          _uidSequence(message),
          [MessageFlags.seen],
          action: seen ? StoreAction.add : StoreAction.remove,
        );
        message.isSeen = seen;
      });

  /// Stern setzen oder entfernen. Danach wird der Stand beim Server geprüft,
  /// damit ein stiller Fehlschlag nicht unbemerkt bleibt.
  Future<void> setFlagged(Mailbox box, MimeMessage message, bool flagged) =>
      _run((c) async {
        final seq = _uidSequence(message);
        await c.selectMailbox(box);
        await c.uidStore(
          seq,
          [MessageFlags.flagged],
          action: flagged ? StoreAction.add : StoreAction.remove,
        );
        final check = await c.uidFetchMessages(seq, '(UID FLAGS)');
        final serverState = check.messages.firstOrNull?.isFlagged ?? false;
        if (serverState != flagged) {
          throw StateError('Der Server hat die Markierung nicht übernommen.');
        }
        message.isFlagged = flagged;
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


  /// Nachricht in einen anderen Ordner verschieben (z. B. Papierkorb, Spam).
  Future<void> moveMessage(Mailbox from, MimeMessage message, Mailbox to) =>
      _run((c) async {
        await c.selectMailbox(from);
        await c.uidMove(_uidSequence(message), targetMailbox: to);
      });

  /// Mehrere Nachrichten auf einmal verschieben.
  Future<void> moveMessages(
    Mailbox from,
    List<MimeMessage> messages,
    Mailbox to,
  ) =>
      _run((c) async {
        final uids = messages.map((m) => m.uid).whereType<int>().toList();
        if (uids.isEmpty) return;
        await c.selectMailbox(from);
        await c.uidMove(
          MessageSequence.fromIds(uids, isUid: true),
          targetMailbox: to,
        );
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
