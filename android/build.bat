@echo off
rem Build the KPW3 Frame APK without Gradle:
rem   aapt2 (resources) -> javac -> d8 (dex) -> add classes.dex -> zipalign -> apksigner
setlocal enabledelayedexpansion

set "PROJ=%~dp0"
set "SDK=C:\Android"
set "BT=%SDK%\build-tools\35.0.0"
set "ANDROID_JAR=%SDK%\platforms\android-34\android.jar"
set "OUT=%PROJ%build"

set "PY=python"
if exist "%PROJ%..\.venv\Scripts\python.exe" set "PY=%PROJ%..\.venv\Scripts\python.exe"

if not exist "%ANDROID_JAR%" (
  echo [x] android.jar not found: %ANDROID_JAR%
  exit /b 1
)

if exist "%OUT%" rmdir /s /q "%OUT%"
mkdir "%OUT%" 2>nul
mkdir "%OUT%\gen" 2>nul
mkdir "%OUT%\classes" 2>nul
mkdir "%OUT%\dex" 2>nul

echo [1/6] aapt2 compile
"%BT%\aapt2.exe" compile --dir "%PROJ%res" -o "%OUT%\res.zip" || goto :err

echo [2/6] aapt2 link
"%BT%\aapt2.exe" link -o "%OUT%\base.apk" -I "%ANDROID_JAR%" --manifest "%PROJ%AndroidManifest.xml" -R "%OUT%\res.zip" --java "%OUT%\gen" --auto-add-overlay || goto :err

echo [3/6] javac
del "%OUT%\sources.txt" 2>nul
for /r "%PROJ%java" %%f in (*.java) do echo %%f>>"%OUT%\sources.txt"
for /r "%OUT%\gen" %%f in (*.java) do echo %%f>>"%OUT%\sources.txt"
javac -encoding UTF-8 -nowarn -source 17 -target 17 -classpath "%ANDROID_JAR%" -d "%OUT%\classes" "@%OUT%\sources.txt" || goto :err

echo [4/6] d8
del "%OUT%\classes.txt" 2>nul
for /r "%OUT%\classes" %%f in (*.class) do echo %%f>>"%OUT%\classes.txt"
call "%BT%\d8.bat" --lib "%ANDROID_JAR%" --min-api 26 --output "%OUT%\dex" "@%OUT%\classes.txt" || goto :err

echo [5/6] package + align
"%PY%" "%PROJ%..\tools\add_dex.py" "%OUT%\base.apk" "%OUT%\dex\classes.dex" "%OUT%\app.apk" || goto :err
"%BT%\zipalign.exe" -f -p 4 "%OUT%\app.apk" "%OUT%\app-aligned.apk" || goto :err

echo [6/6] sign
if not exist "%PROJ%debug.keystore" (
  echo     generating debug keystore
  keytool -genkeypair -v -keystore "%PROJ%debug.keystore" -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Android Debug,O=Android,C=US" || goto :err
)
call "%BT%\apksigner.bat" sign --ks "%PROJ%debug.keystore" --ks-pass pass:android --key-pass pass:android --ks-key-alias androiddebugkey --out "%OUT%\kpw3-frame-debug.apk" "%OUT%\app-aligned.apk" || goto :err
call "%BT%\apksigner.bat" verify "%OUT%\kpw3-frame-debug.apk" || goto :err

echo.
echo [OK] %OUT%\kpw3-frame-debug.apk
dir /b "%OUT%\kpw3-frame-debug.apk"
exit /b 0

:err
echo.
echo [FAILED] build stopped. See the messages above.
exit /b 1
