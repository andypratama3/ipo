@echo off
cd /d %~dp0..
D:\web\flutter\bin\flutter.bat test test/ui_preview_test.dart --update-goldens
echo.
echo Preview disimpan di: test\preview
pause

