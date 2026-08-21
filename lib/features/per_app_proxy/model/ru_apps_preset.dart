/// Curated default split-tunneling bypass list for fresh Android installs
/// (PLAN.md split-tunneling task): major Russian banking, marketplace and
/// social/messaging apps whose backends geo/reputation-flag VPN exit IPs.
/// These packages are routed OUTSIDE the tunnel by default so they see the
/// user's real local IP instead of the proxy's.
///
/// Package names verified against live Google Play / RuStore listings as of
/// 2026-08-21 — publishers occasionally migrate package ids on rebrand (e.g.
/// Tinkoff -> T-Bank kept its package so far), so re-verify before a release
/// if this list hasn't been touched in a while.
const List<String> ruDefaultExcludePackages = [
  // Banking
  'ru.sberbankmobile', // Sberbank Online
  'com.idamob.tinkoff.android', // T-Bank (ex-Tinkoff)
  'ru.alfabank.mobile.android', // Alfa-Bank
  'ru.vtb24.mobilebanking.android', // VTB Online

  // Marketplaces
  'ru.ozon.app.android', // Ozon
  'com.wildberries.ru', // Wildberries

  // Social / messaging
  'com.vkontakte.android', // VK
  'com.vk.im', // VK Messenger
  'ru.oneme.app', // MAX

  // Yandex family
  'ru.yandex.taxi', // Yandex Go (taxi/delivery)
  'ru.yandex.yandexmaps', // Yandex Maps & Navigator
  'ru.yandex.music', // Yandex Music
  'ru.yandex.mail', // Yandex Mail
  'ru.yandex.disk', // Yandex Disk
  'com.yandex.browser', // Yandex Browser
];
