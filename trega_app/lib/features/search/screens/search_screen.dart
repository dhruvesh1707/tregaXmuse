import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/sample_data.dart';
import '../../../core/models/listing.dart';
import '../../../core/models/product.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/product_card.dart';
import '../../home/providers/listing_providers.dart';
import '../../listing_detail/screens/listing_detail_screen.dart';

/// Search over live listings with condition filters.
///
/// Firestore has no full-text search; v1 filters the live feed client-side
/// by title/description match. (If the catalog grows, swap this for an
/// Algolia/Typesense integration behind the same UI.)
class SearchScreen extends ConsumerStatefulWidget {
  static const String routeName = '/search';

  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Condition? _conditionFilter;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<Listing> _applyFilters(List<Listing> listings) {
    final q = _controller.text.trim().toLowerCase();
    return listings.where((l) {
      if (_conditionFilter != null &&
          l.product.condition != _conditionFilter) {
        return false;
      }
      if (q.isEmpty) return true;
      final haystack =
          '${l.product.title} ${l.product.description}'.toLowerCase();
      return haystack.contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final liveAsync = ref.watch(liveListingsProvider);
    final results = liveAsync.when(
      data: (listings) => _applyFilters(listings),
      loading: () => const <Listing>[],
      error: (_, __) => _applyFilters(SampleData.listings),
    );
    final demo = liveAsync.hasError;

    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search PS5, iPhone, DSLR…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () =>
                            setState(() => _controller.clear()),
                      ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                // TODO: trigger search request.
              },
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                _filterChip(context, 'All', _conditionFilter == null, () {
                  setState(() => _conditionFilter = null);
                }),
                ...Condition.values.map(
                  (c) => _filterChip(
                    context,
                    c.label,
                    _conditionFilter == c,
                    () => setState(() => _conditionFilter = c),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: liveAsync.connectionState == ConnectionState.waiting
                ? const Center(child: CircularProgressIndicator())
                : results.isEmpty
                    ? Center(
                        child: Text(
                          demo
                              ? 'No results in demo data.'
                              : 'No matches. Try another search.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      )
                    : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.68,
              ),
              itemCount: results.length,
              itemBuilder: (context, i) {
                final listing = results[i];
                return ProductCard(
                  listing: listing,
                  onTap: () => Navigator.of(context).pushNamed(
                    ListingDetailScreen.routeName,
                    arguments: listing.id,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.primary,
        labelStyle: TextStyle(
          color: selected ? Colors.white : AppColors.primaryDark,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
