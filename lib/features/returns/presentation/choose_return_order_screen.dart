import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabler_icons_next/tabler_icons_next.dart' as tabler;

import '../../../core/constants/app_icons.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../core/utils/date_formatter.dart';
import '../../../core/utils/debouncer.dart';
import '../../../data/models/order.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../orders/presentation/widgets/order_status_badge.dart';
import '../providers/returnable_orders_provider.dart';
import 'create_return_screen.dart';

/// Step one of a return started from the Returns screen: which order the
/// goods came back from. Picking one opens [CreateReturnScreen]; saving
/// there closes this screen too, back to the Returns list.
class ChooseReturnOrderScreen extends ConsumerStatefulWidget {
  const ChooseReturnOrderScreen({super.key});

  @override
  ConsumerState<ChooseReturnOrderScreen> createState() =>
      _ChooseReturnOrderScreenState();
}

class _ChooseReturnOrderScreenState
    extends ConsumerState<ChooseReturnOrderScreen> {
  final _searchCtrl = TextEditingController();
  final _debouncer = Debouncer();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  Future<void> _open(Order order) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => CreateReturnScreen(originalOrder: order),
    ));
    if (saved == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final ordersAsync = ref.watch(returnableOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.chooseOrderToReturn),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              autofocus: false,
              onChanged: (v) => _debouncer.run(
                  () => setState(() => _query = v.trim().toLowerCase())),
              decoration: InputDecoration(
                hintText: s.searchOrdersToReturn,
                prefixIcon: const ThinIcon(tabler.Search.new, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        tooltip: s.clearSearch,
                        icon: const ThinIcon(tabler.X.new),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
      body: ordersAsync.when(
        data: (all) {
          final orders = [
            for (final o in all)
              if (returnOrderMatches(o, _query)) o,
          ];
          if (orders.isEmpty) {
            return EmptyState(
              icon: tabler.ShoppingBag.new,
              title: s.noOrdersToReturn,
              subtitle: s.noOrdersToReturnHint,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: orders.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _OrderTile(
              order: orders[i],
              onTap: () => _open(orders[i]),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(child: Text(s.errorOccurred)),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({required this.order, required this.onTap});

  final Order order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.6);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(order.orderNumber,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerEnd,
                      child: Text(CurrencyFormatter.format(order.totalAmount),
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                order.customerName.isNotEmpty
                    ? order.customerName
                    : s.walkInCustomer,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OrderStatusBadge(status: order.orderStatus),
                  Text(
                    '${DateFormatter.format(order.createdAt)} · ${order.totalItems} ${s.items}',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
