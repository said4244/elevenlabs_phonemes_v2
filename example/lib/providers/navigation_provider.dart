import 'package:flutter/foundation.dart';

enum AppPage {
  splash,
  main,
  characters,
  profile,
  friends,
  training,
  waiting,
  call,
  callSuccess,
  practice,
  fight,
}

class NavigationProvider extends ChangeNotifier {
  AppPage _currentPage = AppPage.splash;
  AppPage? _previousPage;

  bool _rewardOverlayVisible = false;

  AppPage get currentPage => _currentPage;
  AppPage? get previousPage => _previousPage;

  bool get rewardOverlayVisible => _rewardOverlayVisible;

  void goTo(AppPage page) {
    if (_currentPage == page) return;
    _previousPage = _currentPage;
    _currentPage = page;
    notifyListeners();
  }

  void showRewardOverlay() {
    if (_rewardOverlayVisible) return;
    _rewardOverlayVisible = true;
    notifyListeners();
  }

  void hideRewardOverlay() {
    if (!_rewardOverlayVisible) return;
    _rewardOverlayVisible = false;
    notifyListeners();
  }
}
