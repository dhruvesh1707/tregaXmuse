import 'package:trega/core/icons/phosphor_icons.dart';
import 'package:flutter/material.dart';

/// A single headed section inside a legal page.
class LegalSection {
  final String heading;
  final String body;

  const LegalSection(this.heading, this.body);
}

/// One legal page (Privacy Policy, Terms, …) rendered by
/// [LegalPageScreen].
class LegalPage {
  final String id;
  final String title;
  final String updated;
  final IconData icon;
  final List<LegalSection> sections;

  const LegalPage({
    required this.id,
    required this.title,
    required this.updated,
    required this.icon,
    required this.sections,
  });
}

/// The legal pages required for App Store / Play Store listings, shown
/// under the "Legal" section of the profile page.
const Map<String, LegalPage> legalPages = {
  'privacy': LegalPage(
    id: 'privacy',
    title: 'Privacy Policy',
    updated: 'September 2026',
    icon: PhosphorIconsRegular.shieldCheck,
    sections: [
      LegalSection(
        'Who we are',
        'Trega ("we", "us") operates trega.in and the Trega mobile app, a '
        'community marketplace for pre-owned gear. This policy explains what '
        'information we collect, how we use it, and the choices you have.',
      ),
      LegalSection(
        'Information we collect',
        'Account information: your name, phone number, email address and '
        'profile photo.\n\n'
        'Identity verification: to keep the marketplace trustworthy, sellers '
        'and buyers verify with an Aadhaar OTP. Your Aadhaar number is used '
        'only to request and verify the OTP through our verification '
        'provider and is never stored on our servers — we keep only a '
        'one-way fingerprint to prevent the same Aadhaar verifying two '
        'accounts.\n\n'
        'Listings and transactions: photos, titles, descriptions, prices, '
        'pickup and delivery addresses, bids, offers and order history.\n\n'
        'Payments: processed securely by Cashfree. We never see or store '
        'your card, UPI or bank account details.\n\n'
        'Device information: push-notification tokens and basic app '
        'diagnostics so we can deliver alerts and fix crashes.',
      ),
      LegalSection(
        'How we use your information',
        'To operate the marketplace: creating listings, placing bids, '
        'processing orders and arranging doorstep pickup and delivery. To '
        'verify identity, prevent fraud and abuse, process payments, send '
        'transactional notifications, and improve the app.',
      ),
      LegalSection(
        'Sharing your information',
        'We share data only with the service providers needed to run Trega: '
        'Google Firebase (hosting, database and notifications), Cashfree '
        '(payments) and our KYC provider (Aadhaar OTP verification). We '
        'also disclose information when required by law. We never sell your '
        'personal data.',
      ),
      LegalSection(
        'Data retention',
        'We keep your account data while your account is active. Verification '
        'fingerprints are retained to enforce the one-Aadhaar-per-account '
        'rule. You can request deletion of your account and data at any '
        'time through Help & Support.',
      ),
      LegalSection(
        'Your rights',
        'You may access, correct or delete your personal information, and '
        'withdraw consent for optional processing, by contacting us. We '
        'respond to requests within 30 days.',
      ),
      LegalSection(
        "Children's privacy",
        'Trega is for users aged 18 and above. We do not knowingly collect '
        'data from children.',
      ),
      LegalSection(
        'Changes to this policy',
        'We may update this policy from time to time. Material changes will '
        'be notified in the app.',
      ),
      LegalSection(
        'Contact us',
        'For privacy questions or requests, reach us at support@trega.in.',
      ),
    ],
  ),
  'terms': LegalPage(
    id: 'terms',
    title: 'Terms of Service',
    updated: 'September 2026',
    icon: PhosphorIconsRegular.handshake,
    sections: [
      LegalSection(
        'Eligibility',
        'You must be at least 18 years old and located in India to use '
        'Trega. By creating an account you confirm you meet these '
        'requirements.',
      ),
      LegalSection(
        'Your account',
        'You register with your phone number and are responsible for '
        'activity on your account. One person may hold one account, and one '
        'Aadhaar number may verify only one account.',
      ),
      LegalSection(
        'Listings',
        'You may list only items you own and are entitled to sell. Photos '
        'must be captured with your camera, and titles, descriptions, '
        'condition and price must be accurate and not misleading.',
      ),
      LegalSection(
        'Bids and offers',
        'Negotiation on Trega happens through structured bids and offers '
        'only — there is no buyer-seller chat. An accepted offer is a '
        'commitment: the buyer must complete payment within 24 hours and '
        'the seller must make the item available for the scheduled pickup.',
      ),
      LegalSection(
        'Payments',
        'Payments are processed securely through Cashfree (UPI, cards and '
        'netbanking) and are subject to Cashfree\'s terms in addition to '
        'these.',
      ),
      LegalSection(
        'Pickup and delivery',
        'Trega arranges doorstep pickup from the seller and delivery to the '
        'buyer. Both parties must be reachable and available at the '
        'scheduled slot; missed slots may lead to order cancellation.',
      ),
      LegalSection(
        'Prohibited items',
        'Stolen goods, counterfeit items, weapons, hazardous materials, '
        'and anything illegal under Indian law may not be listed. Such '
        'listings are removed and the account may be suspended.',
      ),
      LegalSection(
        'Fair use',
        'Do not move deals off the platform to evade verification or '
        'payments, scrape the marketplace, or abuse bids, reports or '
        'support channels.',
      ),
      LegalSection(
        'Suspension and termination',
        'We may suspend or terminate accounts for fraud, fake listings, '
        'abuse or repeated policy violations.',
      ),
      LegalSection(
        'Liability',
        'Trega provides the marketplace venue connecting buyers and '
        'sellers. Transactions are between users; please exercise your own '
        'diligence. To the extent permitted by law, our liability is '
        'limited to the value of the transaction in question.',
      ),
      LegalSection(
        'Governing law',
        'These terms are governed by the laws of India.',
      ),
    ],
  ),
  'refund': LegalPage(
    id: 'refund',
    title: 'Refund & Cancellation Policy',
    updated: 'September 2026',
    icon: PhosphorIconsRegular.wallet,
    sections: [
      LegalSection(
        'Cancelling a bid',
        'You may withdraw your bid any time before the seller accepts it, '
        'from the Bids & Offers screen.',
      ),
      LegalSection(
        'After an offer is accepted',
        'The buyer must complete payment within 24 hours of acceptance. If '
        'payment is not completed in time, the deal may be cancelled and '
        'the seller is free to accept another offer.',
      ),
      LegalSection(
        'After payment',
        'Once payment succeeds the order is confirmed and pickup is '
        'scheduled. Refunds are issued when the seller cancels the order, '
        'the item is materially not as described in the listing, or pickup '
        'or delivery fails through no fault of the buyer.',
      ),
      LegalSection(
        'How to request a refund',
        'Raise the issue through Help & Support within 48 hours of delivery '
        '(or of the failed pickup/delivery). Include your order ID and '
        'photos if the item is not as described.',
      ),
      LegalSection(
        'Refund timelines',
        'Approved refunds are returned to the original payment method '
        'within 5–7 business days through our payment partner, Cashfree. '
        'Bank processing times may vary.',
      ),
      LegalSection(
        'What is not refundable',
        'Change of mind after a successful delivery where the item matches '
        'its listing description does not qualify for a refund — please bid '
        'carefully.',
      ),
    ],
  ),
  'about': LegalPage(
    id: 'about',
    title: 'About Trega',
    updated: 'September 2026',
    icon: PhosphorIconsRegular.info,
    sections: [
      LegalSection(
        'What is Trega?',
        'Trega is India\'s community marketplace for pre-owned gear — '
        'gaming, mobiles, laptops, cameras, music equipment and more. Great '
        'gear deserves a second life, and great deals deserve trust.',
      ),
      LegalSection(
        'How it works',
        'Snap your item with your camera and list it in under a minute. '
        'Buyers place structured offers, you accept the best one, the buyer '
        'pays securely, and we arrange doorstep pickup and delivery.',
      ),
      LegalSection(
        'Built on trust',
        'Every buyer and seller is Aadhaar-verified, payments run through '
        'Cashfree\'s secure gateway, and our review team moderates listings '
        '— so you can trade pre-owned with confidence.',
      ),
    ],
  ),
  'contact': LegalPage(
    id: 'contact',
    title: 'Contact Us',
    updated: 'September 2026',
    icon: PhosphorIconsRegular.envelope,
    sections: [
      LegalSection(
        'Support',
        'Questions about an order, a payment, verification or anything else? '
        'Write to support@trega.in and we\'ll get back to you within 2 '
        'business days.',
      ),
      LegalSection(
        'Refunds and disputes',
        'For refund requests or disputes, raise the issue through Help & '
        'Support in the app within 48 hours of delivery (or of the failed '
        'pickup/delivery), and include your order ID.',
      ),
      LegalSection(
        'Privacy requests',
        'For access, correction or deletion of your personal data, write to '
        'support@trega.in with the subject "Privacy request". We respond '
        'within 30 days.',
      ),
      LegalSection(
        'Feedback',
        'Ideas to make Trega better are always welcome at support@trega.in.',
      ),
    ],
  ),
};
