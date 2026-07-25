#!/bin/sh
set -u

export PATH="/var/jb/usr/bin:/var/jb/usr/sbin:/usr/bin:/usr/sbin:/bin:/sbin:$PATH"
PKG="com.nightvibes33.darkboot"
PREF_BUNDLE="/var/jb/Library/PreferenceBundles/DarkBootPrefs.bundle"
LOADER_PLIST="/var/jb/Library/PreferenceLoader/Preferences/DarkBoot.plist"
TWEAK_DYLIB="/var/jb/Library/MobileSubstrate/DynamicLibraries/DarkBoot.dylib"
TWEAK_FILTER="/var/jb/Library/MobileSubstrate/DynamicLibraries/DarkBoot.plist"

echo '=== DARK-BOOT LIVE DIAGNOSTIC ==='
printf 'date_utc='; date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || true
printf 'identity='; id
printf 'device='; sysctl -n hw.model 2>/dev/null || uname -m
printf 'kernel='; uname -a
printf 'rootless_prefix='; ls -ld /var/jb 2>/dev/null || echo missing

echo '--- package state ---'
dpkg-query -W -f='package=${Package}\nversion=${Version}\nstatus=${db:Status-Status}\narchitecture=${Architecture}\ndepends=${Depends}\n' "$PKG" 2>&1 || true
dpkg-query -W -f='preferenceloader=${Version}\n' preferenceloader 2>&1 || true
dpkg-query -W -f='ellekit=${Version}\n' ellekit 2>&1 || true

echo '--- installed paths ---'
dpkg -L "$PKG" 2>&1 || true
for path in "$TWEAK_DYLIB" "$TWEAK_FILTER" "$PREF_BUNDLE" "$PREF_BUNDLE/DarkBootPrefs" "$PREF_BUNDLE/Info.plist" "$PREF_BUNDLE/Root.plist" "$LOADER_PLIST"; do
  if [ -e "$path" ]; then
    ls -ld "$path"
  else
    echo "MISSING $path"
  fi
done

echo '--- plist validation ---'
for plist in "$TWEAK_FILTER" "$PREF_BUNDLE/Info.plist" "$PREF_BUNDLE/Root.plist" "$LOADER_PLIST"; do
  echo "plist=$plist"
  if [ -f "$plist" ]; then
    plutil -lint "$plist" 2>&1 || plutil "$plist" 2>&1 || true
  else
    echo missing
  fi
done

echo '--- loader registration ---'
cat "$LOADER_PLIST" 2>/dev/null || true

echo '--- binary inspection ---'
file "$TWEAK_DYLIB" "$PREF_BUNDLE/DarkBootPrefs" 2>&1 || true
if command -v otool >/dev/null 2>&1; then
  echo '[DarkBoot dylib dependencies]'
  otool -L "$TWEAK_DYLIB" 2>&1 || true
  echo '[DarkBootPrefs dependencies]'
  otool -L "$PREF_BUNDLE/DarkBootPrefs" 2>&1 || true
fi
if command -v ldid >/dev/null 2>&1; then
  echo '[DarkBootPrefs entitlements/signature]'
  ldid -e "$PREF_BUNDLE/DarkBootPrefs" 2>&1 || true
fi

echo '--- PreferenceLoader filesystem ---'
find /var/jb/Library/PreferenceLoader -maxdepth 3 -type f -iname '*DarkBoot*' -o -iname '*PreferenceLoader*' 2>/dev/null | head -100 || true
find /var/jb/Library/PreferenceBundles -maxdepth 2 -type d -name 'DarkBootPrefs.bundle' -print 2>/dev/null || true

echo '--- processes ---'
ps aux 2>/dev/null | grep -E 'SpringBoard|Preferences|preference' | grep -v grep || true

echo '--- recent relevant crash reports ---'
for dir in /var/mobile/Library/Logs/CrashReporter /var/mobile/Library/Logs/CrashReporter/DiagnosticLogs /var/mobile/Library/Logs/CrashReporter/Retired; do
  [ -d "$dir" ] || continue
  find "$dir" -type f \( -iname '*Preferences*' -o -iname '*SpringBoard*' -o -iname '*DarkBoot*' \) -mtime -2 -print 2>/dev/null | tail -20
 done

echo 'diagnostic_result=completed'
