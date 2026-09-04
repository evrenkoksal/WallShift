# WallShift

Menü çubuğunda çalışan, seçtiğiniz sitelerden duvar kağıdı indirip belirlediğiniz
periyotlarla masaüstünüzü değiştiren native macOS uygulaması.

## Kurulum

```bash
./Scripts/build_app.sh              # ~/Applications/WallShift.app
./Scripts/build_app.sh /Applications # başka bir hedefe kurmak için
open -a ~/Applications/WallShift.app
```

Gereksinim: macOS 14+, Swift 6 toolchain (Xcode Command Line Tools yeterli).
Uygulama `LSUIElement` olarak paketlenir; Dock'ta görünmez, yalnızca menü çubuğunda durur.

## Kaynaklar

| Kaynak | API anahtarı | Not |
|---|---|---|
| Bing — Günün Görseli | gerekmez | Son 8 günün UHD arkaplanları, bölge seçilebilir |
| Wallhaven | isteğe bağlı | Arama sorgusu, kategori ve oran filtresi; yalnızca SFW |
| Reddit | gerekmez | RSS üzerinden; subreddit listesi ve dönem seçilebilir |
| Wikimedia Commons | gerekmez | Öne çıkan / kaliteli / değerli görsel koleksiyonları |
| Unsplash | **gerekir** | unsplash.com/developers → Access Key |
| NASA APOD | isteğe bağlı | `DEMO_KEY` çalışır ama kotası düşüktür |
| Özel URL listesi | gerekmez | Kendi doğrudan görsel bağlantılarınız |

Birden fazla kaynak seçtiğinizde adaylar birleştirilip karıştırılır. Bir kaynak hata
verirse diğerleri çalışmaya devam eder; ölü bir bağlantı denk gelirse sıradaki aday denenir.

## Ayarlar

- **Zamanlama:** 1 dakikadan günde bire kadar hazır periyotlar, ya da sadece elle.
  Açılışta değiştir, uykudan uyanınca kaçırılan değişimi yap, pil ile çalışırken duraklat.
  Kalan süre menü panelinde geri sayar; uygulama kapansa bile döngü kaldığı yerden sürer.
- **Görünüm:** Tüm ekranlara uygula, yerleşim (doldur/sığdır/yay/ortala),
  en küçük çözünürlük filtresi.
- **Genel:** Girişte otomatik başlat (SMAppService), geçmiş boyutu, önbellek sınırı.

## Menü paneli

Şu anki görselin önizlemesi, başlığı ve kaynağı; "Şimdi değiştir", geçmişte ileri/geri,
"Kaydet…", "Kaynağı aç" ve hızlı periyot seçimi.

## Komut satırından tetikleme

```bash
open -a WallShift --args --change-now      # hemen değiştir (Shortcuts/cron için)
open -a WallShift --args --open-settings   # ayarları aç

~/Applications/WallShift.app/Contents/MacOS/WallShift --print-status
~/Applications/WallShift.app/Contents/MacOS/WallShift --login-item=on
```

## Dosyalar

- Görsel önbelleği: `~/Library/Application Support/WallShift/Wallpapers/`
- Geçmiş: `~/Library/Application Support/WallShift/history.json`
- Ayarlar: `defaults read com.evrenkoksal.wallshift`

Önbellek, ayarlardaki sınırı aşınca en eskiden başlayarak budanır; son 10 görsel korunur.
macOS duvar kağıdını dosya yoluyla tuttuğu için indirilen dosya silinmemelidir — bu yüzden
görseller uygulama klasöründe saklanır.

## Proje yapısı

```
Sources/WallShift/
  WallShiftApp.swift      MenuBarExtra + ayarlar penceresi (scene tanımı)
  AppState.swift          Orkestrasyon: fetch → indir → uygula → zamanla
  ImageSources.swift      Kaynak sağlayıcılar (her site için bir struct)
  WallpaperManager.swift  İndirme, doğrulama, NSWorkspace ile uygulama, önbellek
  Preferences.swift       UserDefaults tabanlı ayarlar
  Models.swift            Tipler ve hata mesajları
  Views/                  Menü paneli ve ayarlar arayüzü
Scripts/build_app.sh      .app paketleme + ad-hoc imzalama
```

Yeni bir site eklemek: `ImageSourceProvider`'ı uygulayan bir struct yazın,
`SourceKind`'a bir case ekleyin, `SourceRegistry`'de bağlayın.
