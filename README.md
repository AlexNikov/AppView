> **Fork.** [AppView](https://github.com/AlexNikov/AppView) is a fork of [Lookin](https://github.com/QMUI/Lookin) by Hugh Li. The iOS framework is [AppViewServer](https://github.com/AlexNikov/AppViewServer), a fork of [LookinServer](https://github.com/QMUI/LookinServer).

# Introduction
You can inspect and modify views in iOS app via AppView, just like UI Inspector in Xcode, or another app called Reveal.

# Integration Guide
To use the AppView macOS app, you need to integrate [AppViewServer](https://github.com/AlexNikov/AppViewServer) (iOS framework of AppView) into your iOS project.

> **Warning**
> 1. Never integrate AppViewServer in Release building configuration.
> 2. Do not use versions earlier than 1.0.6, as it contains a critical bug that could lead to online incidents in your project.

## via CocoaPods:
### Swift Project
`pod 'AppViewServer', :subspecs => ['Swift'], :configurations => ['Debug']`
### Objective-C Project
`pod 'AppViewServer', :configurations => ['Debug']`
## via Swift Package Manager:
`https://github.com/AlexNikov/AppViewServer.git`

# Repository
- macOS app: https://github.com/AlexNikov/AppView
- iOS framework: https://github.com/AlexNikov/AppViewServer

---
> **Форк.** [AppView](https://github.com/AlexNikov/AppView) — форк [Lookin](https://github.com/QMUI/Lookin) (Hugh Li). iOS-фреймворк: [AppViewServer](https://github.com/AlexNikov/AppViewServer), форк [LookinServer](https://github.com/QMUI/LookinServer).

# Введение
AppView позволяет просматривать и изменять UI-объекты в iOS-приложении — как UI Inspector в Xcode или приложение Reveal.

# Установка AppViewServer
Если вы впервые используете AppView в iOS-проекте, сначала подключите [AppViewServer](https://github.com/AlexNikov/AppViewServer).

> **Warning**
> 1. Не подключайте AppViewServer в конфигурации AppStore / Release.
> 2. Не используйте версии ниже 1.0.6 — в них критический баг, который может привести к инцидентам на проде.

## Через CocoaPods:

### Swift-проект
`pod 'AppViewServer', :subspecs => ['Swift'], :configurations => ['Debug']`
### Objective-C-проект
`pod 'AppViewServer', :configurations => ['Debug']`

## Через Swift Package Manager:
`https://github.com/AlexNikov/AppViewServer.git`

# Репозитории
- macOS-приложение: https://github.com/AlexNikov/AppView
- iOS AppViewServer: https://github.com/AlexNikov/AppViewServer
