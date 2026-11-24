import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/customer_provider.dart';
import '../../../data/models/customer.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/utils/debouncer.dart';
import '../../../core/utils/number_input.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/animated_entrance.dart';
import '../../../shared/widgets/screen_guide.dart';
import 'widgets/customer_card.dart';
import 'package:tabler_icons_next/tabler_icons_next.dart' as tabler;
import '../../../core/constants/app_icons.dart';
import '../../../shared/widgets/section_help.dart';

class CustomerListScreen extends ConsumerStatefulWidget {
  const CustomerListScreen({super.key});

  @override
  ConsumerState<CustomerListScreen> createState() =>
      _CustomerListScreenState();
}

class _CustomerListScreenState extends ConsumerState<CustomerListScreen> {
  final _searchCtrl = TextEditingController();
  final _debouncer = Debouncer();
  String _query = '';

  /// The customer type shown; null = all.
  CustomerTag? _tag;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final customersAsync = ref.watch(customersProvider);
    final all = customersAsync.value ?? const <Customer>[];
    final chipRowHeight = customerTypeChipRowHeight(MediaQuery.textScalerOf(context));
    String tagLabel(CustomerTag t) => switch (t) {
          CustomerTag.newCustomer => s.tagNew,
          CustomerTag.regular => s.regular,
          CustomerTag.vip => s.vip,
        };
    Widget chip(CustomerTag? t) {
      final n = t == null ? all.length : all.where((c) => c.tag == t).length;
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: ChoiceChip(
          key: ValueKey('customerTypeChip-${t?.name ?? 'all'}'),
          label: Text('${t == null ? s.all : tagLabel(t)} ($n)', softWrap: false),
          selected: _tag == t,
          onSelected: (_) => setState(() => _tag = t),
        ),
      );
    }

    return ScreenGuide(
      id: 'customers',
      steps: [
        GuideStep(title: s.guideCustomersAddTitle, description: s.guideCustomersAddDesc),
        GuideStep(title: s.guideCustomersDuesTitle, description: s.guideCustomersDuesDesc),
      ],
      builder: (context, guide) => Scaffold(
      appBar: AppBar(
        title: Text(s.customers),
        actions: [
          guide.wrap(1, IconButton(
            tooltip: s.dueBook,
            icon: const ThinIcon(tabler.Notebook.new),
            onPressed: () => context.go('/dues'),
          )),
          const SectionHelpButton('customers'),
        ],
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(64 + chipRowHeight + 8),
          child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => _debouncer.run(
                  () => setState(() => _query = v.toLowerCase())),
              decoration: InputDecoration(
                hintText: s.searchCustomers,
                prefixIcon: const ThinIcon(tabler.Search.new, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        tooltip: AppStrings.of(context).clearSearch,
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
          SizedBox(
            height: chipRowHeight,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                  children: [chip(null), for (final t in CustomerTag.values) chip(t)]),
            ),
          ),
          const SizedBox(height: 8),
          ]),
        ),
      ),
      body: customersAsync.when(
        data: (allCustomers) {
          final customers = allCustomers
              .where((c) =>
                  (_tag == null || c.tag == _tag) &&
                  (_query.isEmpty ||
                      c.name.toLowerCase().contains(_query) ||
                      NumberInput.phoneMatches(c.phone, _query)))
              .toList();

          if (customers.isEmpty && _tag != null && allCustomers.isNotEmpty) {
            return EmptyState(
              icon: tabler.Users.new,
              title: s.noCustomersFound,
              actionLabel: s.clearFilters,
              onAction: () => setState(() => _tag = null),
            );
          }
          if (customers.isEmpty) {
            return EmptyState(
              icon: tabler.Users.new,
              title: _query.isNotEmpty ? s.noCustomersFound : s.noDataFound,
              subtitle: _query.isEmpty ? s.addFirstCustomer : null,
              actionLabel: _query.isEmpty ? s.addCustomer : null,
              onAction: _query.isEmpty ? () => context.push('/customers/add') : null,
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: customers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) => AnimatedEntrance(
              index: i,
              child: CustomerCard(customer: customers[i]),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            Center(child: Text('${AppStrings.of(context).error}: $e')),
      ),
      floatingActionButton: guide.wrap(0, FloatingActionButton(
        onPressed: () => context.push('/customers/add'),
        tooltip: s.addCustomer,
        child: const ThinIcon(tabler.Plus.new),
      )),
    ),
    );
  }
}

/// The customer type chip row's height: 36 at the default text size, plus
/// what the chip label grows with a larger font.
@visibleForTesting
double customerTypeChipRowHeight(TextScaler textScaler) =>
    36 + (textScaler.scale(14) - 14) * 1.43;
