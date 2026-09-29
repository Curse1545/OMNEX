# OMNEX 0.2

Android ve Windows için kişisel Türkçe sohbet uygulaması.

## Durum

Gerçek OpenAI Responses API istemcisi eklendi. Canlı model testi yapılmadı; kendi API hesabınız ve erişebildiğiniz model kimliği gerekir. Anahtar uygulama ayarlarında girilir, yalnızca RAM’de tutulur, uygulama kapatıldığında kaybolur. Anahtarı GitHub’a veya sohbete göndermeyin.

Mesaj gönderildiğinde o oturumun başarılı sohbet geçmişi OpenAI’a gönderilir (`store: false`). Yeni sohbet düğmesi geçmişi temizler. API kullanımı ayrıca ücretlenebilir. Ortak bir geliştirici anahtarı uygulamaya gömülmemelidir; çok kullanıcılı dağıtım için kimlik doğrulamalı sunucu katmanı gerekir.

## Eklenenler

- Model ve API anahtarı ayar ekranı
- Asenkron gerçek yanıt isteği, 90 saniye zaman aşımı
- Türkçe bağlantı, kimlik doğrulama ve kota hataları
- Başarısız mesajı düzenleme alanına geri koyma
- Yeni sohbet, seçilebilir yanıtlar, bekleme göstergesi
- Android ve Windows derlemeleri; analiz ve otomatik testler

## Henüz olmayanlar

Sesli konuşma, kalıcı sohbet geçmişi ve gerçek cihaz kontrolü yoktur. İzin anahtarları ve onay diyaloğu arayüz demosudur; işletim sistemi izni vermez veya komut çalıştırmaz.

## Geliştirme

```sh
flutter create . --project-name omnex --platforms=android,windows
flutter pub get
flutter analyze lib test
flutter test
python3 tool/android_network.py
flutter build apk --release
```

Windows derlemesi Windows üzerinde `flutter build windows --release` ile yapılır. Actions çıktıları APK ve Windows çalıştırma klasörüdür; Windows klasöründeki DLL ve veri dosyalarını EXE ile birlikte tutun. Android ilk deneme paketi Flutter’ın varsayılan geliştirme imzasını kullanır; mağaza yayınına hazır değildir.
