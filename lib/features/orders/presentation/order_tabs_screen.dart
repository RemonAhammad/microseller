import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tabler_icons_next/tabler_icons_next.dart' as tabler;

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/section_help.dart';
import 'order_form_screen.dart';

/// Most new orders that can be open at once.
const kMaxOrderTabs = 3;

/// `/orders/add`: up to [kMaxOrderTabs] new orders open side by side, each a
/// full [OrderFormScreen] kept alive in an [IndexedStack], so switching tabs
/// never loses what was typed. Saving an order closes its tab; the screen
/// closes with its last tab.
class OrderTabsScreen extends StatefulWidget {
  const OrderTabsScreen({super.key});

  @override
  State<OrderTabsScreen> createState() => _OrderTabsScreenState();
}

class _OrderTabsScreenState extends State<OrderTabsScreen> {
  // Stable ids, so a closed tab never hands its state to another.
  final List<int> _tabs = [0];
  int _nextId = 1;
  int _current = 0;
  final _tabScroll = ScrollController();
  // GlobalKeys, not ValueKeys: IndexedStack wraps each child, so a plain key
  // is matched by position and closing a middle tab handed the next tab's
  // place to the closed tab's form.
  final Map<int, GlobalKey> _formKeys = {};

  @override
  void dispose() {
    _tabScroll.dispose();
    super.dispose();
  }

  void _add() {
    if (_tabs.length >= kMaxOrderTabs) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AppStrings.of(context).orderTabsLimit(kMaxOrderTabs))));
      return;
    }
    setState(() {
      _tabs.add(_nextId++);
      _current = _tabs.length - 1;
    });
    // Show the new tab when the row is wider than the app bar.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_tabScroll.hasClients) {
        _tabScroll.animateTo(
          _tabScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _remove(int id) {
    final i = _tabs.indexOf(id);
    if (i < 0) return;
    if (_tabs.length == 1) {
      context.pop();
      return;
    }
    setState(() {
      _tabs.removeAt(i);
      _formKeys.remove(id);
      if (_current >= _tabs.length || _current > i) _current = (_current - 1).clamp(0, _tabs.length - 1);
    });
  }

  Future<void> _confirmClose(int id) async {
    final s = AppStrings.of(context);
    final ok = await ConfirmDialog.show(
      context,
      title: s.closeOrderTab,
      message: s.closeOrderTabMessage,
      isDestructive: true,
    );
    if (ok == true && mounted) _remove(id);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: _tabs.length < 2 ? null : 8,
        title: _tabs.length < 2
            ? Text(s.addOrder)
            : SingleChildScrollView(
                controller: _tabScroll,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < _tabs.length; i++)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 8),
                        child: _OrderTab(
                          label: i == _current ? s.orderTabLabel(i + 1) : '📦 ${i + 1}',
                          selected: i == _current,
                          closeTooltip: s.closeOrderTab,
                          onTap: () => setState(() => _current = i),
                          onClose: () => _confirmClose(_tabs[i]),
                        ),
                      ),
                  ],
                ),
              ),
        actions: [
          if (_tabs.length < kMaxOrderTabs)
            IconButton(tooltip: s.newOrderTab, onPressed: _add, icon: const ThinIcon(tabler.Plus.new)),
          const SectionHelpButton('order_form'),
        ],
      ),
      body: IndexedStack(
        index: _current,
        children: [
          for (final id in _tabs)
            TickerMode(
              key: _formKeys.putIfAbsent(id, GlobalKey.new),
              enabled: _tabs[_current] == id,
              child: OrderFormScreen(onCreated: () => _remove(id)),
            ),
        ],
      ),
    );
  }
}

/// One order's tab in the app bar: its name (tap to switch) and a ✕ that
/// closes it. Sized to fit the normal app bar.
class _OrderTab extends StatelessWidget {
  final String label;
  final bool selected;
  final String closeTooltip;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _OrderTab({
    required this.label,
    required this.selected,
    required this.closeTooltip,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.onPrimaryContainer : cs.onSurfaceVariant;
    return Material(
      color: selected ? cs.primaryContainer : cs.surfaceContainerHighest,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsetsDirectional.only(start: 12, end: selected ? 2 : 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(vertical: selected ? 0 : 8),
                child: Text(
                  label,
                  maxLines: 1,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: fg, fontWeight: selected ? FontWeight.w600 : FontWeight.w500),
                ),
              ),
              // Only the open tab can be closed, so a tap meant for another
              // tab never closes it by mistake.
              if (selected)
                Tooltip(
                  message: closeTooltip,
                  child: InkResponse(
                    onTap: onClose,
                    radius: 16,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: ThinIcon(tabler.X.new, size: 16, color: fg),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
