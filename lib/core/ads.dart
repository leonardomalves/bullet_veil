import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Ad unit REWARDED. Este é o de TESTE oficial do Google — anúncios reais de
/// teste, sem risco de banimento. Com a conta AdMob criada, passe o real via:
///   flutter build apk --dart-define=ADMOB_REWARDED_ID=ca-app-pub-XXXX/YYYY
/// (e troque o APPLICATION_ID no AndroidManifest.xml.)
const _testRewardedId = 'ca-app-pub-3940256099942544/5224354917';
const _rewardedId = String.fromEnvironment(
  'ADMOB_REWARDED_ID',
  defaultValue: _testRewardedId,
);

/// Anúncios do jogo: SÓ rewarded (o jogador escolhe assistir em troca de
/// algo). Sem banner, sem interstitial — num jogo de reflexo, anúncio não
/// pedido é desinstalação. Sem rede/sem fill, os botões somem: o jogo nunca
/// bloqueia esperando anúncio.
class Ads {
  Ads._();

  static final Ads instance = Ads._();

  /// Há um rewarded carregado e pronto para exibir (a UI liga os botões).
  final rewardedReady = ValueNotifier(false);

  RewardedAd? _rewarded;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      await MobileAds.instance.initialize();
      _initialized = true;
      _load();
    } catch (e) {
      debugPrint('[Ads] indisponível, jogo segue sem anúncios: $e');
    }
  }

  void _load() {
    if (!_initialized) return;
    RewardedAd.load(
      adUnitId: _rewardedId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewarded = ad;
          rewardedReady.value = true;
        },
        onAdFailedToLoad: (error) {
          _rewarded = null;
          rewardedReady.value = false;
          // Sem fill agora não é sem fill sempre: tenta de novo daqui a pouco.
          Future.delayed(const Duration(seconds: 45), _load);
        },
      ),
    );
  }

  /// Exibe o rewarded. [onReward] SÓ dispara se o usuário completar o
  /// anúncio — é o contrato do formato.
  void showRewarded({required VoidCallback onReward}) {
    final ad = _rewarded;
    if (ad == null) return;
    _rewarded = null;
    rewardedReady.value = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _load(); // pré-carrega o próximo
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _load();
      },
    );
    ad.show(onUserEarnedReward: (_, reward) => onReward());
  }
}

final ads = Ads.instance;
