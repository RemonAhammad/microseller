import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tabler_icons_next/tabler_icons_next.dart' as tabler;

import '../../core/constants/app_icons.dart';
import '../../core/constants/app_strings.dart';
import '../../core/extensions/context_extensions.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/date_formatter.dart';
import '../../core/utils/quantity.dart';
import '../../core/utils/validators.dart';
import '../../data/models/customer.dart';
import '../../data/models/order.dart';
import '../../data/services/isar_service.dart';
import '../../data/services/mail_service.dart';
import '../../data/services/order_returns_summary.dart';
import '../../features/customers/providers/customer_provider.dart';
import '../../features/settings/providers/settings_provider.dart';
import 'action_feedback.dart';
import 'app_button.dart';
import 'bottom_sheet_handle.dart';

/// A tap on a saved address: a new email in the mail app, or, where no mail
/// app opens, a sheet with the address and Copy email (as `callPhone` does).
Future<void> writeEmail(
    BuildContext context, WidgetRef ref, String address) async {
  final opened = await ref.read(mailComposerProvider).openAddress(address);
  if (opened || !context.mounted) return;
  await AppBottomSheet.show<void>(
    context,
    title: AppStrings.of(context).mailNotAvailable,
    child: _MailNotAvailable(address: address.trim()),
  );
}

class _MailNotAvailable extends StatelessWidget {
  const _MailNotAvailable({required this.address});

  final String address;

  Future<void> _copy(BuildContext context) async {
    final s = AppStrings.of(context);
    await Clipboard.setData(ClipboardData(text: address));
    if (!context.mounted) return;
    Navigator.pop(context);
    context.showSuccessSnackBar(s.emailCopied);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // An address has no spaces to wrap at: it breaks anywhere instead.
        SelectionArea(
          child: Text(
            breakableEmail(address),
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style:
                theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 16),
        AppButton(
          label: s.copyEmail,
          icon: tabler.Copy.new,
          isFullWidth: true,
          onPressed: () => _copy(context),
        ),
      ],
    );
  }
}

/// [address] with zero-width spaces after `@` and `.`, so a long one wraps
/// at its natural breaks rather than overflowing; for display only.
String breakableEmail(String address) =>
    address.replaceAllMapped(RegExp(r'[@._\-+]'), (m) => '${m[0]}​');

/// Opens the mail app with everything filled in. Where none can (no mail
/// app, iOS Mail not set up) the share sheet takes the PDF and subject,
/// pointing at [shareOrigin] on an iPad. Says "Opened in your mail app",
/// never "Sent": the app can't know whether the seller sent it. True when
/// the mail app opened or the share sheet shared.
Future<bool> sendByEmail(
  BuildContext context,
  WidgetRef ref, {
  required String to,
  required String subject,
  required String body,
  MailAttachment? attachment,
  Rect? shareOrigin,
}) async {
  final s = AppStrings.of(context);
  final composer = ref.read(mailComposerProvider);
  MailOutcome outcome;
  try {
    outcome = await composer.compose(
        to: to, subject: subject, body: body, attachment: attachment);
  } catch (e) {
    debugPrint('Email compose failed: $e');
    if (context.mounted) context.showErrorSnackBar(s.errorOccurred);
    return false;
  }
  if (!context.mounted) return outcome == MailOutcome.opened;
  switch (outcome) {
    case MailOutcome.opened:
      context.showSuccessSnackBar(s.openedInMailApp);
      return true;
    case MailOutcome.cancelled:
      return false;
    case MailOutcome.unavailable:
      context.showSnackBar(s.noMailAppShareInstead);
      final ShareParams params;
      if (attachment != null) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/${attachment.fileName}');
        await file.writeAsBytes(attachment.bytes, flush: true);
        params = ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: subject,
          sharePositionOrigin: shareOrigin,
        );
      } else {
        params = ShareParams(
            text: body, subject: subject, sharePositionOrigin: shareOrigin);
      }
      final result = await SharePlus.instance.share(params);
      if (context.mounted) confirmShared(context, result);
      return result.status == ShareResultStatus.success;
  }
}

/// Where an email to [customer] goes: their saved address, else one the
/// seller types now, optionally saved to the customer. Null when cancelled.
Future<String?> emailRecipientFor(
    BuildContext context, WidgetRef ref, Customer? customer) async {
  if (customer != null && customer.hasEmail) return customer.email.trim();
  final answer = await showDialog<(String, bool)>(
    context: context,
    builder: (_) => _AskEmailDialog(customer: customer),
  );
  if (answer == null) return null;
  final (address, save) = answer;
  if (save && customer != null) {
    await ref
        .read(customerProvider.notifier)
        .updateCustomer(customer.copyWith(email: address));
  }
  return address;
}

class _AskEmailDialog extends StatefulWidget {
  const _AskEmailDialog({required this.customer});

  final Customer? customer;

  @override
  State<_AskEmailDialog> createState() => _AskEmailDialogState();
}

class _AskEmailDialogState extends State<_AskEmailDialog> {
  final _ctrl = TextEditingController();
  bool _save = true;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final s = AppStrings.of(context);
    final address = _ctrl.text.trim();
    final error = address.isEmpty
        ? s.invalidEmail
        : Validators.email(address, s.invalidEmail);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, (address, _save && widget.customer != null));
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final customer = widget.customer;
    return AlertDialog(
      title: Text(s.emailAskTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(customer != null
                ? s.emailAskNoEmail(customer.name)
                : s.emailAskNoCustomer),
            const SizedBox(height: 12),
            // A plain TextField: AppTextField needs a width an AlertDialog
            // can't give it.
            TextField(
              controller: _ctrl,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              textDirection: TextDirection.ltr,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: s.email,
                errorText: _error,
                errorMaxLines: 3,
              ),
            ),
            if (customer != null)
              CheckboxListTile(
                value: _save,
                onChanged: (v) => setState(() => _save = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(s.saveEmailToCustomer(customer.name)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(s.openMailApp)),
      ],
    );
  }
}

/// The customer an order bills, if they still exist.
Future<Customer?> customerOfOrder(WidgetRef ref, Order order) async {
  if (order.customerId <= 0) return null;
  final isar = await ref.read(isarProvider.future);
  return isar.customers.get(order.customerId);
}

/// Email invoice: an order's or a return's PDF to its customer. The address
/// is asked before [pdf] renders, so cancelling costs nothing; [pdf] is the
/// caller's (cached) receipt, the same file Share produces. [customer]
/// skips the lookup when the caller has it. True when it went out (see
/// [sendByEmail]).
Future<bool> emailOrderInvoice(
  BuildContext context,
  WidgetRef ref,
  Order order, {
  required Future<Uint8List> Function() pdf,
  List<Order> returns = const [],
  String? originalOrderNumber,
  Rect? shareOrigin,
  Customer? customer,
}) async {
  customer ??= await customerOfOrder(ref, order);
  if (!context.mounted) return false;
  final to = await emailRecipientFor(context, ref, customer);
  if (to == null || !context.mounted) return false;
  final bytes = await pdf();
  if (!context.mounted) return false;
  final shop = ref.read(settingsProvider.notifier).shopName;
  final s = AppStrings.of(context);
  return sendByEmail(
    context,
    ref,
    to: to,
    subject: order.isReturn
        ? s.emailSubjectReturn(order.orderNumber, shop)
        : s.emailSubjectInvoice(order.orderNumber, shop),
    body: buildInvoiceEmailBody(context, ref, order,
        returns: returns, originalOrderNumber: originalOrderNumber),
    attachment: MailAttachment(
        bytes,
        order.isReturn
            ? '${order.orderNumber}_return.pdf'
            : '${order.orderNumber}.pdf'),
    shareOrigin: shareOrigin,
  );
}

/// The email's text, in the app's language: the items and the totals, like
/// the WhatsApp text.
String buildInvoiceEmailBody(
  BuildContext context,
  WidgetRef ref,
  Order order, {
  List<Order> returns = const [],
  String? originalOrderNumber,
}) {
  final s = AppStrings.of(context);
  final settings = ref.read(settingsProvider.notifier);
  String money(double v) => CurrencyFormatter.format(v);
  final sb = StringBuffer()
    ..writeln(order.customerName.trim().isEmpty
        ? s.emailHello
        : s.reminderGreeting(order.customerName.trim()))
    ..writeln();
  if (order.isReturn) {
    sb.writeln(originalOrderNumber == null
        ? s.emailReturnIntroPlain(order.orderNumber)
        : s.emailReturnIntro(order.orderNumber, originalOrderNumber));
  } else {
    sb.writeln(s.emailInvoiceIntro(
        order.orderNumber, DateFormatter.format(order.createdAt)));
  }
  sb.writeln();
  for (final item in order.items) {
    sb.writeln('• ${item.displayName} × ${documentQty(item.qty, item.unit)}'
        ' — ${money(item.totalPrice)}');
  }
  sb
    ..writeln()
    ..writeln('${s.total}: ${money(order.totalAmount)}');
  if (order.isReturn) {
    if (order.refundAmount > 0) {
      sb.writeln('${s.tr('refunded')}: ${money(order.refundAmount)}');
    }
  } else {
    final summary = OrderReturnsSummary.of(order, returns);
    sb
      ..writeln('${s.paid}: ${money(summary.received)}')
      ..writeln('${s.balanceDue}: ${money(summary.due)}');
  }
  sb
    ..writeln()
    ..writeln(s.emailThanks)
    ..writeln(settings.shopName);
  if (settings.shopPhone.isNotEmpty) sb.writeln(settings.shopPhone);
  return sb.toString().trimRight();
}

/// A choice of how to send something (Remind, Statement): the existing way
/// first, then email. Returns the chosen index, or null.
Future<int?> showSendChoice(
  BuildContext context, {
  required String title,
  required List<(ThinIconBuilder, String)> options,
}) {
  return AppBottomSheet.show<int>(
    context,
    title: title,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < options.length; i++)
          Builder(
            builder: (tileContext) => ListTile(
              leading: ThinIcon(options[i].$1),
              title: Text(options[i].$2),
              onTap: () => Navigator.pop(tileContext, i),
            ),
          ),
      ],
    ),
  );
}
