# OMNEX 0.5

## 0.5 Windows yenilikleri

- Inno Setup kurulum EXE'si, masaüstü ve Başlat menüsü kısayolu. D sürücüsü varsa varsayılan D:\OMNEX.
- Yanıt tarzları, kısa/ayrıntılı yanıt, kalıcı özel talimatlar. Yerel model ağırlıkları aynı Qwen3 1.7B; zeka artışı iddiası yok.
- 4096 token yerel bağlam ve karakter bütçeli son konuşmalar.
- UTF-8 metin eki: txt/md/csv/json/log, en fazla 1 MB dosya, ilk 2800 karakter. Kullanıcı eklemeyi onaylar; bulut seçiliyse gönderimde buluta iletilir.
- Windows TTS: mevcut tr-TR System.Speech sesi gerekir. Ses yoksa açık hata gösterilir; ses kopyalama yok.
- Yerel Whisper base ile 8 saniyelik Türkçe sesle yazma; ilk model indirmesi internet gerektirir. Metin otomatik gönderilmez.
- OpenCV yüz konumu algılama ve kamera HUD; kamera açıkça açılır, sayfa kapanınca kapanır. Kimlik tanıma veya modele görüntü aktarımı yok.
- Kamera/ses kurulumunda Python ve bağımlılıklar D:\OMNEX-Araclar altında hazırlanır. Ayarlardan kurulur. Donanımla gerçek test bu ortamda yapılamadı.
- Bilgisayar araçları: onayla Not Defteri, Hesap Makinesi veya Dosya Gezgini açma. Model metninden komut çalıştırılmaz.
- Yardımcı servis yalnız 127.0.0.1 üzerinde rastgele port ve oturum belirteciyle çalışır. Tarayıcı kökenli istekleri reddeder. Başlangıçta kamera/mikrofon açılmaz, görüntü/ses diske yazılmaz. Ana süreç kapanınca helper kapanır.

Abonelik ödeme sistemi ve çok kullanıcılı yönetici sunucusu henüz uygulanmadı; Pro plan ekranı taslaktır. Kullanıcı hesapları veya merkezi özel veri koleksiyonu yok.

## 0.4 yenilikleri

- Cihazda saklanan birden fazla sohbet; arama, yeniden adlandırma ve onaylı silme.
- Yerel modelde parça parça yanıt ve istek durdurma. Durdurulan mesaj taslağa döner; tamamlanmamış yanıt geçmişe eklenmez.
- Markdown yanıtlar, kod blokları, mesaj/sohbet kopyalama, mesajı düzenleyip yeniden sorma.
- Açık/koyu tema, geniş ekranda yan panel, telefonda menü, başlangıç önerileri.
- OMNEX Pro plan karşılaştırması: 100 TL yalnızca örnek aylık fiyat. Ödeme, üyelik ve ücretli model geçişi uygulanmadı. Gerçek bir satış veya ödeme formu yok.
- D sürücüsüne model indirmek için OMNEX-D-Baslat.cmd dahil.

Geçmiş SharedPreferences ile cihazda şifrelenmeden saklanır; API anahtarları bu kayda dahil değildir. Bozuk geçmiş otomatik silinmez veya üzerine yazılmaz. Android yerel çıkarım henüz desteklenmez. Canlı cihaz testi ayrıca gereklidir.

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

İnternet araması, Android yerel çıkarım, gerçek ödeme ve tam otonom bilgisayar kontrolü yoktur. Windows ses özellikleri gerekli yerel araç/ses kurulumuna bağlıdır. İşlevsiz izin ve işlem demoları kaldırıldı.

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
