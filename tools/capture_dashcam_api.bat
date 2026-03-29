@echo off
echo ============================================
echo  Onelap Dashcam API Capture Tool
echo ============================================
echo.
echo This will capture ALL network traffic on your Wi-Fi adapter
echo while you use the Onelap app on your phone.
echo.
echo INSTRUCTIONS:
echo  1. Connect BOTH your PC and phone to the dashcam Wi-Fi
echo  2. Run this script
echo  3. Open the Onelap app on your phone
echo  4. Browse files, play a video, check live stream
echo  5. Come back here and press Ctrl+C to stop
echo  6. Share the generated .pcap file
echo.
echo Starting capture in 3 seconds...
timeout /t 3 >nul

set TSHARK="C:\Program Files\Wireshark\tshark.exe"
set OUTPUT=%~dp0dashcam_capture.pcap

echo.
echo Capturing to: %OUTPUT%
echo Press Ctrl+C to stop when done using the Onelap app...
echo.

%TSHARK% -i "Wi-Fi" -w %OUTPUT% -f "host 192.168.169.1" 2>&1

echo.
echo ============================================
echo Capture saved to: %OUTPUT%
echo.
echo Now analyzing the capture...
echo.

echo === All HTTP requests ===
%TSHARK% -r %OUTPUT% -Y "http.request" -T fields -e http.request.method -e http.request.uri -e http.host 2>&1

echo.
echo === All TCP conversations ===
%TSHARK% -r %OUTPUT% -q -z conv,tcp 2>&1

echo.
echo === HTTP response bodies (first 500 bytes each) ===
%TSHARK% -r %OUTPUT% -Y "http.response" -T fields -e http.response.code -e http.content_type -e http.file_data 2>&1

echo.
echo === TCP payload data (port 5000) ===
%TSHARK% -r %OUTPUT% -Y "tcp.port==5000 and data" -T fields -e data.text 2>&1

echo.
echo ============================================
echo Analysis complete. Share the output above.
echo The pcap file is at: %OUTPUT%
echo ============================================
pause
