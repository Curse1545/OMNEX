# OMNEX 0.3

## Ücretsiz Windows yerel modu

Windows varsayılanı Ollama + qwen3:1.7b. API anahtarı ve API ücreti gerekmez. ZIP içindeki OMNEX-Yerel-Baslat.cmd, Ollama eksikse resmi winget paketini kurar, modeli indirir ve OMNEX’i açar. Winget yoksa resmi indirme sayfasını açar. Kullanıcı kurulum ekranlarını tamamlamalıdır.

Yalnızca 127.0.0.1:11434 kullanılır; yerel isteklerde OpenAI anahtarı gönderilmez. 2048 token bağlam, 384 token çıktı, 2 CPU iş parçacığı ve 1 dakika model tutma süresi kullanılır. Model yaklaşık 1.4 GB indirmedir; gerçek RAM/VRAM tüketimi daha fazladır. 8 GB RAM + GTX 1050 Ti üzerinde hız testi yapılmadı. Android yerel mod içermez.

## OpenAI seçeneği

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
