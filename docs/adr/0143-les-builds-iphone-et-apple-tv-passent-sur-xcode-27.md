# ADR-0143 — Les builds iPhone et Apple TV passent sur Xcode 27

- **Statut :** **suspendu** le 2026-11-18. Demandé par l'utilisateur (« fais le passage à Xcode 27
  dans le workflow »), le premier build sous Xcode 27 a cassé (release run 154, job `build-ios`) ;
  consigne de l'utilisateur : « si le build avec xcode 27 casse ne cherche pas a trouvé de solution
  reste sur 26.6 on verra ca plus tard ». Les jobs Apple sont revenus sur `macos-latest`
  (Xcode 26.6) et les gardes de SDK sont retirées. **À reprendre avant avril 2027.**
- **Date :** 2026-11-18
- **Portée :** `.github/workflows/release.yml` (jobs `build-ios` et `build-tvos`),
  `.github/workflows/tvos.yml`, `docs/release-ci.md`.

## Contexte

App Store Connect a renvoyé l'avertissement 90725 sur le dernier build TestFlight : l'app a été
construite avec le SDK iOS 26.5, et à partir d'avril 2027 les apps iOS et iPadOS envoyées doivent
l'être avec le SDK iOS 27 (Xcode 27) ou plus. Rien n'est refusé aujourd'hui.

Les jobs Apple tournaient sur `macos-latest`, qui pointe sur l'image macOS 26 arm64 : Xcode 26.6 par
défaut, SDK iOS 26.5 au plus. Aucune version d'Xcode 27 n'y est installée, donc un `xcode-select`
ne suffit pas. GitHub publie Xcode 27 sur une image à part, `xcode-27` (macOS 27, arm64) :
Xcode 27.0, 27.1 (par défaut) et 27.2, versions publiées et pas des bêtas, avec les SDK et
simulateurs iOS et tvOS 27 (`images/macos/xcode-27-arm64-Readme.md` de `actions/runner-images`,
image `20261104.0337.1`).

## Décision

1. **`build-ios`, `build-tvos` et le workflow `tvos.yml` tournent sur `runs-on: xcode-27`.** On
   prend l'Xcode par défaut de l'image plutôt qu'un chemin `/Applications/Xcode_27.x.app` : GitHub
   retire les anciennes mineures, et un chemin épinglé casserait le build le jour où il disparaît.
2. **Une garde par job.** Avant le build, l'étape lit le SDK (`xcrun --sdk iphoneos
   --show-sdk-version`, `appletvos` pour l'Apple TV) et échoue sous 27 : si l'image change de
   défaut, le build s'arrête au lieu de repartir en silence avec un SDK qu'Apple refusera.
3. **Le DMG macOS reste sur `macos-latest` (Xcode 26).** Il ne passe pas par App Store Connect,
   la règle ne le concerne pas. Il suivra quand `macos-latest` passera à Xcode 27.

## L'échec, à reprendre

`flutter build ios` sous Xcode 27.1 s'arrête sur l'intégrité de la cible, dans
`app/ios/Pods/Pods.xcodeproj` :

> The iOS deployment target 'IPHONEOS_DEPLOYMENT_TARGET' is set to 13.0, but the range of
> supported deployment target versions is 15.0 to 27.1.x.

Un des Pods (les plugins encore sans Swift Package Manager sont `media_kit_libs_ios_video` et
`media_kit_video`) garde un plancher iOS 13.0, qu'Xcode 27 refuse. Pas cherché plus loin, à la
demande de l'utilisateur. La décision ci-dessus reste celle à appliquer quand ce sera réglé.

## Conséquences

- Les builds iPhone et Apple TV sortent avec le SDK 27.1. Les planchers ne bougent pas (iOS 18,
  tvOS 18, ADR-0038) : le SDK fixe les API disponibles, pas les appareils qui installent l'app.
- Deux images Apple dans la CI : un écart de compilateur entre le DMG (Swift d'Xcode 26) et
  l'iPhone (Swift d'Xcode 27) est possible. La garde de l'ADR-0038 sur AetherEngine (pas au-delà de
  la 7.42, refusée par Xcode 26.6) n'a pas été retentée sous Xcode 27.
- Flutter 3.44.2 et flutter-tvos `v3.44.9-tvos.1.5.1` n'ont pas encore construit sous Xcode 27 :
  le premier build le vérifie. Le job Apple TV de la release garde son `continue-on-error`.
- Si `xcode-27` attend un runner plus longtemps que `macos-latest`, c'est la capacité de l'image
  qui le veut, pas le workflow.
