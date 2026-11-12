import 'package:fitsync/features/ads/data/ad_source.dart';
import 'package:fitsync/features/ads/domain/house_ad.dart';

/// An ad source that hands over [ad] (or throws [error]) and records what
/// the card reports, in order, in [calls]: `viewed 7`, `tapped 7`.
class FakeAdSource implements AdSource {
  FakeAdSource({this.ad, this.error, List<String>? calls})
    : calls = calls ?? <String>[];

  HouseAd? ad;
  Object? error;
  int currentCalls = 0;
  final List<String> calls;

  @override
  Future<HouseAd?> current() async {
    currentCalls++;
    if (error case final error?) throw error;
    return ad;
  }

  @override
  Future<void> viewed(int id) async => calls.add('viewed $id');

  @override
  Future<void> tapped(int id) async => calls.add('tapped $id');
}

/// A free trainee's ad, with a link.
const sampleHouseAd = HouseAd(
  id: 7,
  title: 'GymShark PH: 20% off',
  imageUrl: 'http://fitsync.test/storage/ads/7.jpg',
  linkUrl: 'https://shop.example.ph/promo',
);
