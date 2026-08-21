/// Curated default split-tunneling bypass list for fresh Android installs
/// (PLAN.md split-tunneling task): major Russian banking, marketplace,
/// government, telecom and social/messaging apps whose backends geo/
/// reputation-flag VPN exit IPs, or (per the RKS Global VPN-detection study,
/// May 2026: https://rks.global — 30 popular RU apps tested, all 30
/// detecting VPN presence by that point) actively check for VPN/Tor and
/// alter behavior. These packages are routed OUTSIDE the tunnel by default
/// so they see the user's real local IP instead of the proxy's.
///
/// IMPORTANT SCOPE NOTE: this only affects network routing. It does NOT
/// stop an app from enumerating other installed packages via
/// PackageManager (the RKS Global study found 7 of these apps — Wildberries,
/// 2GIS, Мой МТС, Ozon, MegaMarket, RuStore, Odnoklassniki, plus Samokat —
/// can read the full list of installed VPN client packages). Package
/// visibility is a completely different Android mechanism (queries/
/// QUERY_ALL_PACKAGES) from network routing; excluding an app from the
/// tunnel doesn't touch it. There's no client-side fix for that from here.
///
/// Package names verified against live Google Play / RuStore listings as of
/// 2026-08-21 — publishers occasionally migrate package ids on rebrand (e.g.
/// Tinkoff -> T-Bank kept its package so far), so re-verify before a release
/// if this list hasn't been touched in a while.
///
/// Deliberately NOT included despite being named in the RKS Global study:
/// Sovcombank/Halva, Rosbank, MTS Bank — automated lookups returned
/// conflicting/unverifiable package ids for these (several sanctioned-bank
/// apps have been pulled from Google Play and only distribute via RuStore or
/// direct APK, with inconsistent ids across sources). Get the exact id from
/// Settings > Apps > (app) > App details on a device that has it installed
/// before adding.
const List<String> ruDefaultExcludePackages = [
  // Banking
  'ru.sberbankmobile', // Sberbank Online
  'com.idamob.tinkoff.android', // T-Bank (ex-Tinkoff)
  'ru.alfabank.mobile.android', // Alfa-Bank
  'ru.vtb24.mobilebanking.android', // VTB Online
  'ru.raiffeisennews', // Raiffeisenbank Online
  'ru.nspk.mirpay', // Mir Pay

  // Government
  'ru.rostel', // Gosuslugi (state services)

  // Telecom
  'ru.mts.mymts', // My MTS
  'ru.megafon.mlk', // MegaFon personal account

  // Marketplaces / delivery
  'ru.ozon.app.android', // Ozon
  'com.wildberries.ru', // Wildberries
  'com.avito.android', // Avito
  'ru.megamarket.marketplace', // Megamarket (ex-SberMegaMarket)
  'ru.sbcs.store', // Samokat (grocery delivery)

  // Maps / navigation
  'ru.dublgis.dgismobile', // 2GIS

  // App stores
  'ru.vk.store', // RuStore

  // Social / messaging / video
  'com.vkontakte.android', // VK
  'com.vk.im', // VK Messenger
  'com.vk.vkvideo', // VK Video
  'com.uma.musicvk', // VK Music
  'ru.ok.android', // Odnoklassniki (OK)
  'ru.oneme.app', // MAX
  'ru.rutube.app', // Rutube
  'ru.zen.android', // Zen
  'ru.mail.mailapp', // Mail.ru Mail

  // Yandex family
  'ru.yandex.taxi', // Yandex Go (taxi/delivery)
  'ru.yandex.yandexmaps', // Yandex Maps & Navigator
  'ru.yandex.music', // Yandex Music
  'ru.yandex.mail', // Yandex Mail
  'ru.yandex.disk', // Yandex Disk
  'com.yandex.browser', // Yandex Browser
  'ru.beru.android', // Yandex Market (kept the ex-Beru package id)
  'ru.foodfox.client', // Yandex Food/Eda (kept the ex-FoodFox package id)
  'ru.kinopoisk', // Kinopoisk
];
