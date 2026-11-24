import 'package:flutter/services.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:url_launcher/url_launcher.dart';

part 'mail_service.g.dart';

/// What became of an email handed to the phone's mail app.
enum MailOutcome {
  /// The mail app opened with the email filled in. Whether the seller then
  /// sent it isn't known (Android never says), so the app never says "Sent".
  opened,

  /// The seller discarded it in the composer (iOS says so).
  cancelled,

  /// No mail app, or none with an account (iOS Mail not set up): the caller
  /// falls back to the share sheet.
  unavailable,
}

/// A PDF to attach.
class MailAttachment {
  const MailAttachment(this.bytes, this.fileName);

  final Uint8List bytes;
  final String fileName;
}

/// Opens the phone's own mail app (Gmail, Outlook, Mail) with everything
/// filled in; the seller taps Send. Nothing goes through a server. A
/// provider, so tests swap it ([mailComposerProvider]).
class MailComposer {
  const MailComposer();

  Future<MailOutcome> compose({
    required String to,
    required String subject,
    required String body,
    MailAttachment? attachment,
  }) async {
    try {
      final result = await FlutterEmailSender.send(Email(
        recipients: [to],
        subject: subject,
        body: body,
        attachments: [
          if (attachment != null)
            EmailAttachment.data(attachment.bytes,
                fileName: attachment.fileName, mimeType: 'application/pdf'),
        ],
      ));
      return result == EmailSendResult.cancelled
          ? MailOutcome.cancelled
          : MailOutcome.opened;
    } on FlutterEmailSenderNotAvailableException {
      return MailOutcome.unavailable;
    } on FlutterEmailSenderUnsupportedFeatureException {
      // iOS without Mail set up can open a mailto: link, but not attach.
      return MailOutcome.unavailable;
    } on MissingPluginException {
      return MailOutcome.unavailable;
    }
  }

  /// A new email to [address] in the mail app; false when none opens.
  Future<bool> openAddress(String address) async {
    final uri = mailtoUri(address);
    if (uri == null) return false;
    try {
      return await launchUrl(uri);
    } catch (_) {
      return false;
    }
  }
}

/// `mailto:` for [address], or null when it isn't one. Query values are
/// percent-encoded (spaces as `%20`, never `+`, which mail apps show).
Uri? mailtoUri(String address, {String? subject, String? body}) {
  final to = address.trim();
  if (!isEmailAddress(to)) return null;
  final query = [
    if (subject != null && subject.isNotEmpty)
      'subject=${Uri.encodeComponent(subject)}',
    if (body != null && body.isNotEmpty) 'body=${Uri.encodeComponent(body)}',
  ].join('&');
  return Uri.parse(
      'mailto:${Uri.encodeComponent(to).replaceAll('%40', '@')}'
      '${query.isEmpty ? '' : '?$query'}');
}

/// Something that looks like an email address: text without spaces, one `@`,
/// a dot in the part after it. Letters of any script are allowed.
bool isEmailAddress(String value) =>
    RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@.]+$').hasMatch(value.trim());

@Riverpod(keepAlive: true)
MailComposer mailComposer(Ref ref) => const MailComposer();
