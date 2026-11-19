/// Guided listing questions and the local description composer.
///
/// No AI, no network, no callable: the description is composed locally
/// from the seller's own answers. Each category has 5 to 7 questions,
/// required ones first, at most 2 text questions per category, every
/// other question is a single-select chip group. Nothing is
/// pre-selected. Every category also asks the purchase date (year and
/// month chips, required, with "Don't remember" escapes). Admin-added
/// categories (unknown id) get no questions and the description field
/// works as before.
enum QuestionType { choice, text, purchaseDate }

class ListingQuestion {
  final String id;
  final String label;
  final QuestionType type;
  final List<String> options;
  /// Month chips for a purchaseDate question; empty otherwise.
  final List<String> monthOptions;
  final String? placeholder;
  final bool required;

  const ListingQuestion({
    required this.id,
    required this.label,
    required this.type,
    this.options = const [],
    this.monthOptions = const [],
    this.placeholder,
    this.required = false,
  });
}

/// The purchase date question, shared by every category: year and
/// month of purchase, required. The "Don't remember" chips mean
/// required never blocks a seller who genuinely does not remember.
const purchaseDateId = 'purchaseDate';

/// Sub-keys holding the raw year and month picks for the purchase
/// date card. The combined display string lives under `purchaseDate`
/// itself. The year key is what required validation checks, because
/// the combined string is empty when the seller picks "Don't
/// remember" for the year.
const purchaseDateYearKey = 'purchaseDate.year';
const purchaseDateMonthKey = 'purchaseDate.month';

const purchaseDateQuestion = ListingQuestion(
  id: purchaseDateId,
  label: 'When did you buy it?',
  type: QuestionType.purchaseDate,
  options: [
    '2026',
    '2025',
    '2024',
    '2023',
    '2022',
    'Before 2022',
    "Don't remember",
  ],
  monthOptions: [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
    "Don't remember",
  ],
  required: true,
);

const _monthFullNames = <String, String>{
  'Jan': 'January',
  'Feb': 'February',
  'Mar': 'March',
  'Apr': 'April',
  'May': 'May',
  'Jun': 'June',
  'Jul': 'July',
  'Aug': 'August',
  'Sep': 'September',
  'Oct': 'October',
  'Nov': 'November',
  'Dec': 'December',
};

/// Combines a picked year and month into the stored purchase date
/// string: "March 2023" when both are known, the year alone when
/// only the year is known, empty when there is no usable year (none
/// picked, "Don't remember", or a month without a year). A month is
/// meaningless with "Before 2022", so that year stands alone too.
String combinePurchaseDate(String? year, String? month) {
  final y = (year ?? '').trim();
  if (y.isEmpty || y == "Don't remember") return '';
  if (y == 'Before 2022') return 'Before 2022';
  final m = (month ?? '').trim();
  if (m.isEmpty || m == "Don't remember") return y;
  final full = _monthFullNames[m];
  if (full == null) return y;
  return '$full $y';
}

/// Questions for one category, in display order, required first.
/// Returns an empty list for unknown category ids.
List<ListingQuestion> questionsForCategory(String categoryId) {
  switch (categoryId) {
    case 'gaming':
      return const [
        ListingQuestion(
          id: 'item_type',
          label: 'Item type',
          type: QuestionType.choice,
          options: ['Console', 'Controller', 'Game', 'Accessory'],
          required: true,
        ),
        ListingQuestion(
          id: 'model',
          label: 'Model',
          type: QuestionType.text,
          placeholder: 'e.g. PS5, Xbox Series X',
          required: true,
        ),
        purchaseDateQuestion,
        ListingQuestion(
          id: 'storage',
          label: 'Storage',
          type: QuestionType.choice,
          options: ['500GB', '1TB', '2TB'],
        ),
        ListingQuestion(
          id: 'included',
          label: 'Controllers or games included',
          type: QuestionType.choice,
          options: ['None', 'Controller', 'Games', 'Controller and games'],
        ),
        ListingQuestion(
          id: 'issues',
          label: 'Any issues',
          type: QuestionType.choice,
          options: ['None', 'Minor', 'Needs repair'],
        ),
      ];
    case 'mobiles':
      return const [
        ListingQuestion(
          id: 'storage',
          label: 'Storage',
          type: QuestionType.choice,
          options: ['64GB', '128GB', '256GB', '512GB', '1TB'],
          required: true,
        ),
        ListingQuestion(
          id: 'ram',
          label: 'RAM',
          type: QuestionType.choice,
          options: ['4GB', '6GB', '8GB', '12GB', '16GB'],
          required: true,
        ),
        purchaseDateQuestion,
        ListingQuestion(
          id: 'battery_health',
          label: 'Battery health',
          type: QuestionType.text,
          placeholder: 'e.g. 89%',
        ),
        ListingQuestion(
          id: 'screen',
          label: 'Screen condition',
          type: QuestionType.choice,
          options: ['Flawless', 'Minor scratches', 'Cracked'],
        ),
        ListingQuestion(
          id: 'bill_box',
          label: 'Bill and box',
          type: QuestionType.choice,
          options: ['Both', 'Bill only', 'Box only', 'Neither'],
        ),
        ListingQuestion(
          id: 'repairs',
          label: 'Repairs',
          type: QuestionType.choice,
          options: ['None', 'Screen', 'Battery', 'Other'],
        ),
      ];
    case 'laptops':
      return const [
        ListingQuestion(
          id: 'processor',
          label: 'Processor',
          type: QuestionType.text,
          placeholder: 'e.g. Intel i5 11th gen',
          required: true,
        ),
        ListingQuestion(
          id: 'ram',
          label: 'RAM',
          type: QuestionType.choice,
          options: ['4GB', '8GB', '16GB', '32GB'],
          required: true,
        ),
        purchaseDateQuestion,
        ListingQuestion(
          id: 'storage',
          label: 'Storage',
          type: QuestionType.choice,
          options: ['256GB', '512GB', '1TB', '2TB'],
        ),
        ListingQuestion(
          id: 'battery',
          label: 'Battery backup',
          type: QuestionType.text,
          placeholder: 'e.g. 5 hours',
        ),
        ListingQuestion(
          id: 'screen',
          label: 'Screen condition',
          type: QuestionType.choice,
          options: ['Flawless', 'Minor scratches', 'Cracked'],
        ),
        ListingQuestion(
          id: 'charger',
          label: 'Charger included',
          type: QuestionType.choice,
          options: ['Yes', 'No'],
        ),
      ];
    case 'cameras':
      return const [
        ListingQuestion(
          id: 'model',
          label: 'Model',
          type: QuestionType.text,
          placeholder: 'e.g. Canon EOS 1500D',
          required: true,
        ),
        ListingQuestion(
          id: 'lens',
          label: 'Lens included',
          type: QuestionType.choice,
          options: ['Body only', 'Kit lens', 'Extra lens'],
          required: true,
        ),
        purchaseDateQuestion,
        ListingQuestion(
          id: 'shutter',
          label: 'Shutter count',
          type: QuestionType.text,
          placeholder: 'e.g. 12000',
        ),
        ListingQuestion(
          id: 'sensor',
          label: 'Sensor condition',
          type: QuestionType.choice,
          options: ['Clean', 'Dust spots', 'Scratched'],
        ),
        ListingQuestion(
          id: 'battery_charger',
          label: 'Battery and charger',
          type: QuestionType.choice,
          options: ['Both', 'Battery only', 'Neither'],
        ),
      ];
    case 'music':
      return const [
        ListingQuestion(
          id: 'item',
          label: 'Item',
          type: QuestionType.choice,
          options: ['Guitar', 'Keyboard', 'Headphones', 'Speaker', 'Other'],
          required: true,
        ),
        ListingQuestion(
          id: 'brand_model',
          label: 'Brand and model',
          type: QuestionType.text,
          placeholder: 'e.g. Yamaha F310',
          required: true,
        ),
        purchaseDateQuestion,
        ListingQuestion(
          id: 'working',
          label: 'Working condition',
          type: QuestionType.choice,
          options: ['Perfect', 'Minor issue', 'Needs repair'],
        ),
        ListingQuestion(
          id: 'accessories',
          label: 'Accessories included',
          type: QuestionType.text,
          placeholder: 'e.g. carry case, cable',
        ),
        ListingQuestion(
          id: 'damage',
          label: 'Any damage',
          type: QuestionType.choice,
          options: ['None', 'Minor', 'Visible'],
        ),
      ];
    case 'fashion':
      return const [
        ListingQuestion(
          id: 'size',
          label: 'Size',
          type: QuestionType.text,
          placeholder: 'e.g. M, 42, UK 9',
          required: true,
        ),
        ListingQuestion(
          id: 'brand',
          label: 'Brand',
          type: QuestionType.text,
          placeholder: 'e.g. Nike',
          required: true,
        ),
        purchaseDateQuestion,
        ListingQuestion(
          id: 'worn',
          label: 'Worn',
          type: QuestionType.choice,
          options: ['Never', 'Once', 'Few times', 'Often'],
        ),
        ListingQuestion(
          id: 'defects',
          label: 'Any defects',
          type: QuestionType.choice,
          options: ['None', 'Minor', 'Visible'],
        ),
        ListingQuestion(
          id: 'tags_bill',
          label: 'Tags and bill',
          type: QuestionType.choice,
          options: ['Both', 'Tags only', 'Bill only', 'Neither'],
        ),
      ];
    case 'furniture':
      return const [
        ListingQuestion(
          id: 'material',
          label: 'Material',
          type: QuestionType.choice,
          options: ['Wood', 'Metal', 'Fabric', 'Other'],
          required: true,
        ),
        ListingQuestion(
          id: 'size',
          label: 'Size',
          type: QuestionType.text,
          placeholder: 'e.g. 6x3 ft',
          required: true,
        ),
        purchaseDateQuestion,
        ListingQuestion(
          id: 'age',
          label: 'Age',
          type: QuestionType.text,
          placeholder: 'e.g. 2 years',
        ),
        ListingQuestion(
          id: 'damage',
          label: 'Any damage',
          type: QuestionType.choice,
          options: ['None', 'Minor', 'Visible'],
        ),
        ListingQuestion(
          id: 'assembly',
          label: 'Assembly needed',
          type: QuestionType.choice,
          options: ['Yes', 'No'],
        ),
      ];
    case 'appliances':
      return const [
        ListingQuestion(
          id: 'item',
          label: 'Item',
          type: QuestionType.choice,
          options: ['TV', 'Fridge', 'Washing machine', 'Microwave', 'Other'],
          required: true,
        ),
        ListingQuestion(
          id: 'capacity',
          label: 'Size or capacity',
          type: QuestionType.text,
          placeholder: 'e.g. 43 inch, 260L',
          required: true,
        ),
        purchaseDateQuestion,
        ListingQuestion(
          id: 'smart',
          label: 'Smart',
          type: QuestionType.choice,
          options: ['Yes', 'No'],
        ),
        ListingQuestion(
          id: 'panel',
          label: 'Panel type',
          type: QuestionType.choice,
          options: ['LED', 'OLED', 'QLED'],
        ),
        ListingQuestion(
          id: 'remote',
          label: 'Remote included',
          type: QuestionType.choice,
          options: ['Yes', 'No'],
        ),
        ListingQuestion(
          id: 'issues',
          label: 'Any issues',
          type: QuestionType.choice,
          options: ['None', 'Minor', 'Needs repair'],
        ),
      ];
    case 'cycles':
      return const [
        ListingQuestion(
          id: 'type',
          label: 'Type',
          type: QuestionType.choice,
          options: ['Road', 'MTB', 'Hybrid', 'Electric'],
          required: true,
        ),
        ListingQuestion(
          id: 'frame_size',
          label: 'Frame size',
          type: QuestionType.text,
          placeholder: 'e.g. 18 inch',
          required: true,
        ),
        purchaseDateQuestion,
        ListingQuestion(
          id: 'gears',
          label: 'Gears',
          type: QuestionType.choice,
          options: ['Single speed', '7', '21', '24'],
        ),
        ListingQuestion(
          id: 'damage',
          label: 'Any damage',
          type: QuestionType.choice,
          options: ['None', 'Minor', 'Visible'],
        ),
        ListingQuestion(
          id: 'accessories',
          label: 'Accessories included',
          type: QuestionType.text,
          placeholder: 'e.g. lock, lights',
        ),
      ];
    case 'watches':
      return const [
        ListingQuestion(
          id: 'brand',
          label: 'Brand',
          type: QuestionType.text,
          placeholder: 'e.g. Casio',
          required: true,
        ),
        ListingQuestion(
          id: 'strap',
          label: 'Strap',
          type: QuestionType.choice,
          options: ['Metal', 'Leather', 'Rubber', 'Fabric'],
          required: true,
        ),
        purchaseDateQuestion,
        ListingQuestion(
          id: 'model',
          label: 'Model',
          type: QuestionType.text,
          placeholder: 'e.g. G-Shock GA-2100',
        ),
        ListingQuestion(
          id: 'working',
          label: 'Working',
          type: QuestionType.choice,
          options: ['Perfect', 'Needs service', 'Not working'],
        ),
        ListingQuestion(
          id: 'box_papers',
          label: 'Box and papers',
          type: QuestionType.choice,
          options: ['Both', 'Box only', 'Neither'],
        ),
      ];
    case 'collectibles':
      return const [
        ListingQuestion(
          id: 'item',
          label: 'Item',
          type: QuestionType.choice,
          options: ['Coins', 'Stamps', 'Figures', 'Cards', 'Other'],
          required: true,
        ),
        ListingQuestion(
          id: 'brand_series',
          label: 'Brand or series',
          type: QuestionType.text,
          placeholder: 'e.g. Pokemon',
          required: true,
        ),
        purchaseDateQuestion,
        ListingQuestion(
          id: 'condition',
          label: 'Condition detail',
          type: QuestionType.choice,
          options: ['Mint', 'Good', 'Fair'],
        ),
        ListingQuestion(
          id: 'packaging',
          label: 'Original packaging',
          type: QuestionType.choice,
          options: ['Yes', 'No'],
        ),
        ListingQuestion(
          id: 'certificate',
          label: 'Certificate',
          type: QuestionType.choice,
          options: ['Yes', 'No'],
        ),
      ];
    case 'books':
      return const [
        ListingQuestion(
          id: 'author',
          label: 'Author',
          type: QuestionType.text,
          placeholder: 'e.g. Chetan Bhagat',
          required: true,
        ),
        ListingQuestion(
          id: 'language',
          label: 'Language',
          type: QuestionType.choice,
          options: ['English', 'Hindi', 'Other'],
          required: true,
        ),
        purchaseDateQuestion,
        ListingQuestion(
          id: 'edition',
          label: 'Edition or year',
          type: QuestionType.text,
          placeholder: 'e.g. 2021',
        ),
        ListingQuestion(
          id: 'cover',
          label: 'Pages or cover issues',
          type: QuestionType.choice,
          options: ['None', 'Minor', 'Visible'],
        ),
        ListingQuestion(
          id: 'highlighting',
          label: 'Highlighting or notes',
          type: QuestionType.choice,
          options: ['None', 'Some', 'Heavy'],
        ),
      ];
    case 'others':
      return const [
        ListingQuestion(
          id: 'what',
          label: 'What is it',
          type: QuestionType.text,
          placeholder: 'e.g. brass lamp',
          required: true,
        ),
        ListingQuestion(
          id: 'works',
          label: 'Works',
          type: QuestionType.choice,
          options: ['Perfectly', 'Minor issue', 'For parts'],
          required: true,
        ),
        purchaseDateQuestion,
        ListingQuestion(
          id: 'brand',
          label: 'Brand',
          type: QuestionType.text,
          placeholder: 'e.g. Philips',
        ),
        ListingQuestion(
          id: 'included',
          label: 'What is included',
          type: QuestionType.choice,
          options: ['Remote', 'Stand', 'Cable', 'Charger', 'Nothing extra'],
        ),
        ListingQuestion(
          id: 'defects',
          label: 'Any defects',
          type: QuestionType.choice,
          options: ['None', 'Minor', 'Visible'],
        ),
      ];
    default:
      return const [];
  }
}

/// Builds one plain factual description from the answered questions
/// only. One "Label: value." sentence per answered question, required
/// answers first in question order, then answered optional ones in
/// question order, joined with a single space. Unanswered questions
/// are skipped entirely. The purchase date reads as "Purchased:
/// March 2023." rather than repeating its question label. Returns an
/// empty string when nothing is answered. Only the seller's own
/// answers, nothing invented.
String composeDescription(
  String categoryId,
  Map<String, String> answers,
) {
  final questions = questionsForCategory(categoryId);
  final ordered = [
    ...questions.where((q) => q.required),
    ...questions.where((q) => !q.required),
  ];
  final parts = <String>[];
  for (final q in ordered) {
    final value = answers[q.id]?.trim();
    if (value == null || value.isEmpty) continue;
    // The card asks "When did you buy it?" but the description reads
    // better as "Purchased: March 2023."
    final label = q.id == purchaseDateId ? 'Purchased' : q.label;
    parts.add('$label: $value.');
  }
  return parts.join(' ');
}
