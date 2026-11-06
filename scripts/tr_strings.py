#!/usr/bin/env python3
"""Source of the Turkish translations; writes Support/tr.lproj/Localizable.strings.

Edit the TR table below and run:  python3 -I scripts/tr_strings.py
Then check coverage with:         python3 -I scripts/check-strings.py
"""
import pathlib

TR = {
    # Menu bar, windows, HUD
    "About mgestures": "mgestures Hakkında",
    "Gestures Enabled": "Jestler Açık",
    "Disable in %@": "%@ içinde kapat",
    "Grant Accessibility Access…": "Erişilebilirlik İzni Ver…",
    "Settings…": "Ayarlar…",
    "Welcome Guide…": "Hoş Geldin Rehberi…",
    "Quit mgestures": "mgestures'tan Çık",
    "mgestures (inactive)": "mgestures (devre dışı)",
    "mgestures Settings": "mgestures Ayarları",
    "Welcome to mgestures": "mgestures'a Hoş Geldiniz",
    "Cancelled": "İptal edildi",
    "Gestures on": "Jestler açık",
    "Gestures off": "Jestler kapalı",
    "Draw shapes with the mouse to control windows, apps and more.": "Fareyle şekiller çizerek pencereleri, uygulamaları ve daha fazlasını yönetin.",
    "Licensed under the Apache License 2.0.": "Apache Lisansı 2.0 ile lisanslanmıştır.",
    "The shape recognizer is an adaptation of the “$1 Unistroke Recognizer” by J. O. Wobbrock, A. D. Wilson and Y. Li (UIST 2007).":
        "Şekil tanıyıcı, J. O. Wobbrock, A. D. Wilson ve Y. Li'nin “$1 Unistroke Recognizer” çalışmasının (UIST 2007) bir uyarlamasıdır.",

    # Tabs
    "Gestures": "Jestler",
    "Excluded Apps": "Hariç Uygulamalar",
    "General": "Genel",

    # Common buttons
    "Cancel": "Vazgeç",
    "Save": "Kaydet",
    "Clear": "Temizle",
    "Choose…": "Seç…",
    "Delete": "Sil",
    "Remove": "Kaldır",
    "Reset": "Sıfırla",
    "Name": "Ad",
    "Action": "Eylem",
    "None": "Yok",

    # Gestures tab
    "All Apps": "Tüm Uygulamalar",
    "Shapes": "Şekiller",
    "Basic": "Temel",
    "All Shapes": "Tüm Şekiller",
    "Show unassigned": "Atanmamışları göster",
    "Hold the right mouse button and draw a shape. The dot marks where the stroke starts.":
        "Sağ fare tuşunu basılı tutup bir şekil çizin. Nokta, çizginin başladığı yeri gösterir.",
    "Hold the middle mouse button and draw a shape. The dot marks where the stroke starts.":
        "Orta fare tuşunu basılı tutup bir şekil çizin. Nokta, çizginin başladığı yeri gösterir.",
    "All custom gestures are unassigned.": "Özel jestlerin hiçbirine eylem atanmamış.",
    "Delete gesture": "Jesti sil",
    "Delete “%@”?": "“%@” silinsin mi?",
    "Its actions are removed too, in all apps.": "Eylemleri de tüm uygulamalarda kaldırılır.",
    "Remove the gestures for %@?": "%@ için ayarlanan jestler kaldırılsın mı?",
    "All shapes will use the All Apps settings in this app again.": "Bu uygulamada tüm şekiller yeniden Tüm Uygulamalar ayarlarını kullanır.",

    # Action details
    "Application path": "Uygulama yolu",
    "Arguments (optional)": "Argümanlar (isteğe bağlı)",
    "Always open a new instance (arguments only apply to new instances)": "Her zaman yeni bir kopya aç (argümanlar yalnızca yeni kopyalarda geçerlidir)",
    "Command (runs in zsh)": "Komut (zsh ile çalışır)",
    "macOS asks once for each app the script controls (Privacy & Security → Automation).":
        "macOS, scriptin denetlediği her uygulama için bir kez izin ister (Gizlilik ve Güvenlik → Otomasyon).",
    "Record Shortcut": "Kısayol Kaydet",
    "Press a shortcut… (Esc to cancel)": "Bir kısayola basın… (iptal için Esc)",

    # Record sheet
    "Record a Gesture": "Jest Kaydet",
    "Draw the shape once, in the direction you will draw it with the trigger button.":
        "Şekli bir kez, tetik tuşuyla çizeceğiniz yönde çizin.",
    "Draw here with the left mouse button": "Buraya sol fare tuşuyla çizin",
    "Draw a longer stroke.": "Daha uzun bir çizgi çizin.",
    "Very similar to “%@” — they may be confused.": "“%@” şekline çok benziyor; karışabilirler.",
    "Shortcuts, apps, URLs, commands and scripts can be set up in the list after saving.":
        "Kısayol, uygulama, URL, komut ve script ayrıntıları kaydettikten sonra listeden ayarlanabilir.",

    # Try tab
    "Draw a shape to see how it is recognized. Here you draw with the left mouse button and nothing is run.":
        "Nasıl tanındığını görmek için bir şekil çizin. Burada sol fare tuşuyla çizersiniz ve hiçbir eylem çalışmaz.",
    "Evaluate for": "Değerlendirilecek yer",
    "Length %.0f pt (minimum %.0f) · tolerance %.0f": "Uzunluk %.0f pt (en az %.0f) · tolerans %.0f",
    "Too short — acts as a normal right click": "Çok kısa — normal sağ tık gibi davranır",
    "No shape within tolerance — normal right click": "Tolerans içinde şekil yok — normal sağ tık",
    "“%@” has no action — normal right click": "“%@” için eylem yok — normal sağ tık",
    "“%@” → %@": "“%@” → %@",

    # Excluded apps tab
    "In these apps the mouse button works normally and gestures are off — useful for 3D tools, games, remote desktops and virtual machines. The app under the cursor decides, not the active one.":
        "Bu uygulamalarda fare tuşu normal çalışır ve jestler kapalıdır; 3B araçlar, oyunlar, uzak masaüstü ve sanal makineler için kullanışlıdır. Karar, etkin uygulamaya değil imlecin altındaki uygulamaya göre verilir.",
    "Add Running App": "Çalışan Uygulamayı Ekle",
    "Add App…": "Uygulama Ekle…",

    # General tab
    "Accessibility access is required to capture mouse gestures.": "Fare jestlerini yakalamak için Erişilebilirlik izni gerekiyor.",
    "Open Accessibility Settings…": "Erişilebilirlik Ayarlarını Aç…",
    "Gestures enabled": "Jestler açık",
    "Launch at login": "Girişte başlat",
    "Could not change the login item: %@": "Giriş öğesi değiştirilemedi: %@",
    "Trigger": "Tetik",
    "Trigger button": "Tetik tuşu",
    "Required modifier key": "Gerekli değiştirici tuş",
    "Turn gestures on/off": "Jestleri aç/kapat",
    "Use at least one of ⌘, ⌃ or ⌥ in the shortcut.": "Kısayolda ⌘, ⌃ veya ⌥ tuşlarından en az biri olmalı.",
    "With a required modifier key, gestures start only while it is held; otherwise the button works normally. The on/off shortcut works everywhere.":
        "Gerekli bir değiştirici tuş seçilirse jestler yalnızca o tuş basılıyken başlar; aksi hâlde fare tuşu normal çalışır. Aç/kapat kısayolu her yerde çalışır.",
    "Context menu": "Bağlam menüsü",
    "Hold still to open the context menu": "Hareketsiz basılı tutunca bağlam menüsünü aç",
    "Hold time": "Basılı tutma süresi",
    "A quick click always works normally. With this option, pressing and holding without moving does too, so you can press, drag to a menu item and release.":
        "Kısa bir tıklama her zaman normal çalışır. Bu seçenekle, hareket etmeden basılı tutmak da normal çalışır; böylece basıp bir menü öğesine sürükleyip bırakabilirsiniz.",
    "Show trail while drawing": "Çizerken izi göster",
    "Trail color": "İz rengi",
    "Trail width": "İz kalınlığı",
    "Show gesture name after drawing": "Çizdikten sonra jestin adını göster",
    "Sound": "Ses",
    "Haptic feedback": "Dokunsal geri bildirim",
    "Force Touch trackpads only": "Yalnızca Force Touch izleme dörtgenlerinde",
    "Recognition": "Tanıma",
    "Minimum gesture length": "En kısa jest uzunluğu",
    "Recognition tolerance": "Tanıma toleransı",
    "Settings": "Ayarlar",
    "Export…": "Dışa Aktar…",
    "Import…": "İçe Aktar…",
    "Reset All Settings…": "Tüm Ayarları Sıfırla…",
    "Show in Finder": "Finder'da Göster",
    "Could not export the settings.": "Ayarlar dışa aktarılamadı.",
    "Could not import the settings.": "Ayarlar içe aktarılamadı.",
    "Reset all settings?": "Tüm ayarlar sıfırlansın mı?",
    "All gestures, custom shapes, app settings and exclusions are replaced with the defaults. Export first if you want to keep them.":
        "Tüm jestler, özel şekiller, uygulama ayarları ve hariç tutulanlar varsayılanlarla değiştirilir. Saklamak istiyorsanız önce dışa aktarın.",

    # Welcome guide
    "Hold a mouse button, draw a shape, release.": "Bir fare tuşunu basılı tutun, bir şekil çizin, bırakın.",
    "Move to the Applications folder": "Uygulamalar klasörüne taşıyın",
    "mgestures is running from %@. Launch at login and permissions work reliably only from Applications.":
        "mgestures şu an %@ konumundan çalışıyor. Girişte başlatma ve izinler yalnızca Uygulamalar klasöründen güvenilir şekilde çalışır.",
    "Move to Applications": "Uygulamalar'a Taşı",
    "Not Now": "Şimdi Değil",
    "Could not move the app: %@": "Uygulama taşınamadı: %@",
    "Allow Accessibility access": "Erişilebilirlik iznini verin",
    "mgestures needs this to see the mouse buttons and to move windows. It does not record or send anything; the keyboard is only observed while you are drawing, to catch Esc.":
        "mgestures'ın fare tuşlarını görebilmesi ve pencereleri taşıyabilmesi için bu izin gerekli. Hiçbir şey kaydetmez ya da göndermez; klavye yalnızca çizim sırasında, Esc tuşunu yakalamak için dinlenir.",
    "Turn on mgestures in the list. This window updates by itself.": "Listede mgestures'ı açın. Bu pencere kendiliğinden güncellenir.",
    "Choose the button you draw with": "Çizeceğiniz tuşu seçin",
    "A quick click with this button still works normally. You can also require a modifier key in Settings.":
        "Bu tuşla yapılan kısa bir tıklama yine normal çalışır. Ayarlar'dan ayrıca bir değiştirici tuş da zorunlu tutabilirsiniz.",
    "Try a gesture": "Bir jest deneyin",
    "Recognized “%@”. You're all set.": "“%@” tanındı. Her şey hazır.",
    "Hold the right mouse button and draw a line to the left or right: the focused window snaps to that half of the screen. Up maximizes, down minimizes.":
        "Sağ fare tuşunu basılı tutup sola ya da sağa bir çizgi çizin: etkin pencere ekranın o yarısına yerleşir. Yukarı büyütür, aşağı küçültür.",
    "Hold the middle mouse button and draw a line to the left or right: the focused window snaps to that half of the screen. Up maximizes, down minimizes.":
        "Orta fare tuşunu basılı tutup sola ya da sağa bir çizgi çizin: etkin pencere ekranın o yarısına yerleşir. Yukarı büyütür, aşağı küçültür.",
    "There's more": "Dahası da var",
    "Record your own shapes": "Kendi şekillerinizi kaydedin",
    "Different gestures for each app": "Her uygulama için farklı jestler",
    "Turn gestures off in apps that need the button": "Fare tuşuna ihtiyaç duyan uygulamalarda jestleri kapatın",
    "Open Settings…": "Ayarları Aç…",

    # Trigger button / modifier titles
    "Right button": "Sağ tuş",
    "Middle button": "Orta tuş",
    "⌥ Option": "⌥ Option",
    "⌃ Control": "⌃ Control",
    "⌘ Command": "⌘ Command",
    "⇧ Shift": "⇧ Shift",

    # Action categories (also "None" and "Custom" above/below)
    "Window": "Pencere",
    "App": "Uygulama",
    "Navigation": "Gezinme",
    "System": "Sistem",
    "Media": "Medya",
    "Custom": "Özel",

    # Actions
    "No action": "Eylem yok",
    "Tile window left": "Pencereyi sola yerleştir",
    "Tile window right": "Pencereyi sağa yerleştir",
    "Tile window top": "Pencereyi üste yerleştir",
    "Tile window bottom": "Pencereyi alta yerleştir",
    "Maximize window": "Pencereyi büyüt",
    "Center window": "Pencereyi ortala",
    "Move window to next display": "Pencereyi sonraki ekrana taşı",
    "Toggle full screen": "Tam ekranı aç/kapat",
    "Minimize window": "Pencereyi küçült",
    "Close window": "Pencereyi kapat",
    "Hide app": "Uygulamayı gizle",
    "Quit app": "Uygulamadan çık",
    "Open application": "Uygulama aç",
    "Back (mouse button 4)": "Geri (fare tuşu 4)",
    "Forward (mouse button 5)": "İleri (fare tuşu 5)",
    "Open URL": "URL aç",
    "Mission Control": "Mission Control",
    "Show desktop": "Masaüstünü göster",
    "Lock screen": "Ekranı kilitle",
    "Sleep display": "Ekranı uyut",
    "Play / pause": "Oynat / duraklat",
    "Next track": "Sonraki parça",
    "Previous track": "Önceki parça",
    "Volume up": "Sesi aç",
    "Volume down": "Sesi kıs",
    "Mute": "Sessiz",
    "Keyboard shortcut": "Klavye kısayolu",
    "Run shell command": "Kabuk komutu çalıştır",
    "Run AppleScript": "AppleScript çalıştır",

    # Shape groups
    "Directional": "Yönler",
    "Diagonal": "Çaprazlar",
    "Corners": "Köşeler",
    "U / Arch": "U / Kemer",
    "U / Arch (round)": "U / Kemer (yuvarlak)",
    "C": "C",
    "Chevron": "Köşeli Ok",

    # Built-in shapes
    "Up": "Yukarı",
    "Down": "Aşağı",
    "Left": "Sol",
    "Right": "Sağ",
    "Diagonal ↗": "Çapraz ↗",
    "Diagonal ↖": "Çapraz ↖",
    "Diagonal ↘": "Çapraz ↘",
    "Diagonal ↙": "Çapraz ↙",
    "L Shape": "L Şekli",
    "L Shape Rev": "L Şekli (Ters)",
    "Gamma": "Gama",
    "Gamma Rev": "Gama (Ters)",
    "Down-Left": "Aşağı-Sol",
    "Down-Left Rev": "Aşağı-Sol (Ters)",
    "Up-Right": "Yukarı-Sağ",
    "Up-Right Rev": "Yukarı-Sağ (Ters)",
    "U Shape": "U Şekli",
    "U Shape Rev": "U Şekli (Ters)",
    "U Shape Mirror": "U Şekli (Ayna)",
    "U Shape Mirror Rev": "U Şekli (Ayna, Ters)",
    "U Round": "Yuvarlak U",
    "U Round Rev": "Yuvarlak U (Ters)",
    "U Round Mirror": "Yuvarlak U (Ayna)",
    "U Round Mirror Rev": "Yuvarlak U (Ayna, Ters)",
    "C Shape": "C Şekli",
    "C Shape Rev": "C Şekli (Ters)",
    "C Mirror": "C (Ayna)",
    "C Mirror Rev": "C (Ayna, Ters)",
    "Chevron Right": "Sağ Köşeli Ok",
    "Chevron Right Rev": "Sağ Köşeli Ok (Ters)",
    "Chevron Left": "Sol Köşeli Ok",
    "Chevron Left Rev": "Sol Köşeli Ok (Ters)",

    # Redesigned settings and welcome guide
    "Active · %@": "Etkin · %@",
    "App-Specific Gestures": "Uygulamaya Özel Jestler",
    "Appearance": "Görünüm",
    "Closest shapes": "En yakın şekiller",
    "Default (%@)": "Varsayılan (%@)",
    "Draw your own shape and give it an action.": "Kendi şeklinizi çizin ve ona bir eylem atayın.",
    "Gesture name": "Jest adı",
    "Gestures are off": "Jestler kapalı",
    "Get Started": "Başlayalım",
    "How mgestures looks and sounds while you draw.": "Çizerken mgestures'ın görünümü ve sesi.",
    "Later": "Sonra",
    "No custom gestures yet": "Henüz özel jest yok",
    "No excluded apps. Gestures work everywhere.": "Hariç uygulama yok. Jestler her yerde çalışır.",
    "On/off shortcut, sound and haptics": "Aç/kapat kısayolu, ses ve dokunsal geri bildirim",
    "Preview": "Önizleme",
    "Record Gesture…": "Jest Kaydet…",
    "Remove App…": "Uygulamayı Kaldır…",
    "Settings file": "Ayar dosyası",
    "Shapes set to Default use the All Apps setting. Choose “No action” to turn a shape off in %@.": "Varsayılan olarak bırakılan şekiller Tüm Uygulamalar ayarını kullanır. Bir şekli %@ içinde kapatmak için “Eylem yok”u seçin.",
    "Shorter strokes act as a normal click. A lower tolerance means fewer accidental matches, but shapes must be drawn more precisely. Strokes that match no shape, or a shape without an action, also act as a normal click.": "Daha kısa çizgiler normal tıklama gibi davranır. Düşük tolerans yanlışlıkla eşleşmeyi azaltır ama şekillerin daha özenli çizilmesi gerekir. Hiçbir şekle uymayan ya da eylemi olmayan bir şekle uyan çizgiler de normal tıklama gibi davranır.",
    "Show": "Göster",
    "Sound and haptics": "Ses ve dokunsal geri bildirim",
    "Test area": "Deneme alanı",
    "Test strokes before you use them": "Çizgileri kullanmadan önce deneyin",
    "The result appears here.": "Sonuç burada görünür.",
    "Trail": "İz",
    "Waiting for Accessibility access": "Erişilebilirlik izni bekleniyor",
    "Window, media and system actions, scripts": "Pencere, medya ve sistem eylemleri, betikler",
    "mgestures": "mgestures",

    # Calibration and Advanced
    "%d of %d": "%d / %d",
    "Advanced": "Gelişmiş",
    "All set": "Hazır",
    "Calibrate Again…": "Yeniden Kalibre Et…",
    "Calibrate Gestures": "Jestleri Kalibre Et",
    "Calibrate again if gestures are missed or happen by accident.": "Jestler kaçırılıyor ya da istemeden tetikleniyorsa yeniden kalibre edin.",
    "Calibrate…": "Kalibre Et…",
    "Calibration": "Kalibrasyon",
    "Calibration fits recognition to the way you draw. Manual settings are in Advanced.": "Kalibrasyon, tanımayı sizin çizim şeklinize uydurur. Elle yapılan ayarlar Gelişmiş bölümündedir.",
    "Draw each shape twice, the way you normally would. mgestures adjusts itself to your hand.": "Her şekli normalde nasıl çiziyorsanız öyle, ikişer kez çizin. mgestures kendini elinize göre ayarlar.",
    "Draw with the left mouse button, from the dot in the direction of the arrow.": "Sol fare tuşuyla, noktadan başlayıp ok yönünde çizin.",
    "Draw “%@”": "“%@” çizin",
    "Fit it to your hand": "Elinize uydurun",
    "Manual settings for troubleshooting. Calibration in Recognition sets these for you.": "Sorun giderme için elle ayarlar. Tanıma bölümündeki kalibrasyon bunları sizin için ayarlar.",
    "Optional, about 30 seconds: draw four shapes twice and mgestures tunes recognition to your strokes.": "İsteğe bağlı, yaklaşık 30 saniye: dört şekli ikişer kez çizin, mgestures tanımayı çizgilerinize göre ayarlasın.",
    "Personal examples": "Kişisel örnekler",
    "Recognition is now fitted to your strokes. Your drawings are also kept as examples, so shapes are recognized the way you draw them.": "Tanıma artık çizgilerinize göre ayarlandı. Çizimleriniz örnek olarak da saklanır; şekiller sizin çizdiğiniz gibi tanınır.",
    "Reset Recognition": "Tanımayı Sıfırla",
    "Start Over": "Baştan Başla",
    "Takes about 30 seconds: draw four shapes twice.": "Yaklaşık 30 saniye sürer: dört şekli ikişer kez çizin.",
    "That looked like “%@”. Try again.": "Bu “%@” gibi göründü. Yeniden deneyin.",
    "Fitted to your strokes": "Çizgilerinize göre ayarlandı",
    "Using the standard settings": "Standart ayarlar kullanılıyor",
    "%d strokes": "%d çizgi",
}


def escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def main() -> None:
    out = pathlib.Path(__file__).resolve().parent.parent / "Support" / "tr.lproj" / "Localizable.strings"
    out.parent.mkdir(parents=True, exist_ok=True)
    lines = ["/* Turkish. Generated by scripts/tr_strings.py — edit that file, not this one. */", ""]
    lines += [f'"{escape(k)}" = "{escape(v)}";' for k, v in sorted(TR.items(), key=lambda kv: kv[0].lower())]
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {len(TR)} entries to {out}")


if __name__ == "__main__":
    main()
