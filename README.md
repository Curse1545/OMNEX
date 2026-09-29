# OMNEX

OMNEX, Android ve Windows için hazırlanmış Flutter tabanlı yerel-asistan başlangıç projesidir.

## Bu ilk sürümde olanlar

- Karanlık temalı sohbet arayüzü
- Yerel demo yanıt motoru
- Mikrofon, bildirim ve dosya erişimi için izin ekranı
- Hassas işlemler için açık kullanıcı onayı akışı
- Android ve Windows için GitHub Actions derleme şablonları
- Gerçek sistem değişikliği yapmayan güvenli demo davranışı

## Çalıştırma

Bilgisayarda Flutter kuruluysa:

```bash
flutter create . --platforms=android,windows
flutter pub get
flutter run
```

Bu ZIP içindeki `lib/main.dart` ve `pubspec.yaml` dosyaları hazırdır. `flutter create .` eksik platform klasörlerini üretir.

## Android APK

```bash
flutter build apk --release
```

Çıktı normalde:
`build/app/outputs/flutter-apk/app-release.apk`

## Windows

```bash
flutter build windows --release
```

## Sonraki geliştirme adımları

1. Gerçek yapay zekâ/model bağlantısı
2. Güvenli yerel komut yürütme katmanı
3. Sesli giriş/çıkış
4. Kalıcı ayarlar
5. Ayrıntılı izin politikası
6. Windows ve Android için imzalı dağıtım
