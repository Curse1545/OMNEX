from pathlib import Path
p = Path('android/app/src/main/AndroidManifest.xml')
s = p.read_text()
if 'android.permission.INTERNET' not in s:
    i = s.index('>', s.index('<manifest')) + 1
    s = s[:i] + '\n    <uses-permission android:name="android.permission.INTERNET" />' + s[i:]
p.write_text(s)
