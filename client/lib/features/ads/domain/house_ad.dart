/// One ad for the trainee's ad card: FitSync's own today, whatever an
/// `AdSource` hands over later.
class HouseAd {
  const HouseAd({
    required this.id,
    required this.title,
    required this.imageUrl,
    this.linkUrl,
  });

  final int id;
  final String title;

  /// A full address, ready to load.
  final String imageUrl;

  /// The https page tapping the card opens, or null for a card that opens
  /// nothing.
  final String? linkUrl;
}
