@echo off
chcp 65001 >nul
echo ========================================
echo        AUTO-LOGO FIXER v2.0
echo ========================================
echo.
echo  Checking system...
echo.

:: Test if logo file exists
if exist "C:\logos\logo_files\Full Logo no buffer PNG-07-01.png" (
    echo  Logo file found!
    echo  Path: C:\logos\logo_files\Full Logo no buffer PNG-07-01.png
    echo  Size: 
    for %%F in ("C:\logos\logo_files\Full Logo no buffer PNG-07-01.png") do echo        %%~zF bytes
) else (
    echo  ERROR: Logo file NOT FOUND!
    echo Please check: C:\logos\logo_files\Full Logo no buffer PNG-07-01.png
)

echo.
echo  Current configuration:
type "C:\logos\logo_config.txt" 2>nul || echo No config file found

echo.
echo  Opening test page...
start "" "C:\logo_test_fixed.html"

echo.
echo  Opening dashboard...
start "" "dashboard.html" 2>nul || echo Dashboard not found in current folder

echo.
echo ========================================
echo     System check complete!
echo ========================================
echo.
pause
