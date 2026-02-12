@echo off
setlocal enabledelayedexpansion

set "OUT_DIR=output"
if not exist "%OUT_DIR%" (
    mkdir "%OUT_DIR%"
    echo [OK] Output folder created.
)

echo ========================================
echo        FFMPEG INTERACTIVE ENCODER (PRO)
echo ========================================

:: --- Hardware Acceleration Option ---
echo Do you want to use Fully Hardware Acceleration (CUDA)?
echo [1] Yes (Faster, uses NVIDIA GPU for Decode/Filter/Encode)
echo [2] No (Standard, uses CPU for Decode/Filter)
set /p "HW_ACCEL_CHOICE=Choice (1 or 2): "

set "HW_ACCEL_CMD="
set "USE_CUDA_FILTER=0"
if "!HW_ACCEL_CHOICE!"=="1" (
    set "HW_ACCEL_CMD=-hwaccel cuda -hwaccel_output_format cuda"
    set "USE_CUDA_FILTER=1"
    echo [INFO] CUDA Hardware Acceleration Enabled.
)

:: --- Input Mode ---
echo.
echo Select Input Mode:
echo [1] Process ALL videos in folder
echo [2] Select a video by NUMBER
set /p "MODE=Choice (1 or 2): "

if "!MODE!"=="2" (
    echo.
    echo Available Videos:
    set "count=0"
    for %%f in (*.mp4 *.mkv *.avi *.ts *.mov) do (
        set /a "count+=1"
        set "file[!count!]=%%f"
        echo [!count!] %%f
    )
    if !count!==0 (echo No video files found! & pause & exit /b)
    set /p "FILE_CHOICE=Enter file number: "
    for /l %%n in (1,1,!count!) do (if "!FILE_CHOICE!"=="%%n" set "TARGET_FILE=!file[%%n]!")
)

echo.
set /p "EXT=Enter output container (e.g., mkv, mp4): "
set /p "SEEK=Enter -ss value (e.g., 20 or 0 for none): "

echo.
echo Select Video Codec:
echo [1] h264 (libx264 - CPU)
echo [2] h265 (libx265 - CPU)
echo [3] h264_nvenc (NVIDIA GPU)
echo [4] hevc_nvenc (NVIDIA GPU - h265)
set /p "CODEC_CHOICE=Choice (1, 2, 3 or 4): "

if "!CODEC_CHOICE!"=="1" (set "VCODEC=libx264" & set "P_HINT=ultrafast, medium, slow")
if "!CODEC_CHOICE!"=="2" (set "VCODEC=libx265" & set "P_HINT=ultrafast, medium, slow")
if "!CODEC_CHOICE!"=="3" (set "VCODEC=h264_nvenc" & set "P_HINT=p1 to p7")
if "!CODEC_CHOICE!"=="4" (set "VCODEC=hevc_nvenc" & set "P_HINT=p1 to p7")

:: --- Bit Depth Logic ---
echo.
echo Select Bit Depth:
echo [1] 8-bit (Standard)
if "!CODEC_CHOICE!"=="3" (
    echo [X] 10-bit is NOT supported for h264_nvenc.
    set "BIT_CHOICE=1"
) else (
    echo [2] 10-bit (High Quality - Low Color Banding)
    set /p "BIT_CHOICE=Choice (1 or 2): "
)

:: Set Color Format based on Hardware/Software and Bit Depth
if "!BIT_CHOICE!"=="2" (
    if "!USE_CUDA_FILTER!"=="1" (set "V_FORMAT=p010le") else (set "V_FORMAT=yuv420p10le")
) else (
    if "!USE_CUDA_FILTER!"=="1" (set "V_FORMAT=nv12") else (set "V_FORMAT=yuv420p")
)

echo.
set /p "PRESET=Enter preset (!P_HINT!): "
set /p "CRF=Enter CRF/CQ value (e.g., 23): "
set /p "MAXRATE=Enter maxrate (e.g., 1M): "
set /p "BUFSIZE=Enter bufsize (e.g., 2M): "

echo.
echo Select Resolution: [1] 480p [2] 720p [3] 1080p [4] Original
set /p "RES_CHOICE=Choice: "

set "W=" & set "H=" & set "RES=Original"
if "!RES_CHOICE!"=="1" (set "W=720" & set "H=-2" & set "RES=480")
if "!RES_CHOICE!"=="2" (set "W=1280" & set "H=-2" & set "RES=720")
if "!RES_CHOICE!"=="3" (set "W=1920" & set "H=-2" & set "RES=1080")

:: --- Filter Pipeline Logic ---
if "!USE_CUDA_FILTER!"=="1" (
    if "!RES_CHOICE!"=="4" (
        set "VF_CMD=-vf hwupload_cuda,format=!V_FORMAT!"
    ) else (
        set "VF_CMD=-vf scale_cuda=!W!:!H!:format=!V_FORMAT!"
    )
) else (
    if "!RES_CHOICE!"=="4" (
        set "VF_CMD=-vf format=!V_FORMAT!"
    ) else (
        set "VF_CMD=-vf scale=!W!:!H!,format=!V_FORMAT!"
    )
)

echo.
echo Select Audio: [1] Original [2] Stereo [3] Mono
set /p "CH_CHOICE=Choice: "
set "AUDIO_CH="
if "!CH_CHOICE!"=="2" (set "AUDIO_CH=-ac 2")
if "!CH_CHOICE!"=="3" (set "AUDIO_CH=-ac 1")

echo.
echo [STARTING ENCODING...]

if "!MODE!"=="2" (call :process "!TARGET_FILE!") else (for %%i in (*.mp4 *.mkv *.avi *.ts *.mov) do (call :process "%%i"))

echo.
echo ========================================
echo          FINISHED ALL TASKS!
echo ========================================
pause
exit /b

:process
set "input_file=%~1"
if not exist "!input_file!" goto :eof

echo.
echo Processing: !input_file!

set "SS_CMD="
if not "!SEEK!"=="0" set SS_CMD=-ss !SEEK!

:: Quality & RC Logic
set "QUALITY_PARAM="
set "AQ_PARAM="

if "!CODEC_CHOICE!"=="1" (set "QUALITY_PARAM=-crf !CRF!")
if "!CODEC_CHOICE!"=="2" (set "QUALITY_PARAM=-crf !CRF! -x265-params aq-mode=3")
if "!CODEC_CHOICE!"=="3" (set "QUALITY_PARAM=-rc vbr -cq !CRF! -qmin !CRF! -qmax !CRF!" & set "AQ_PARAM=-spatial-aq 1")
if "!CODEC_CHOICE!"=="4" (set "QUALITY_PARAM=-rc vbr -cq !CRF! -qmin !CRF! -qmax !CRF!" & set "AQ_PARAM=-spatial-aq 1")

:: Final FFmpeg Execution
ffmpeg -hide_banner !HW_ACCEL_CMD! !SS_CMD! -i "!input_file!" ^
-c:v !VCODEC! -preset !PRESET! !QUALITY_PARAM! ^
-maxrate !MAXRATE! -bufsize !BUFSIZE! ^
!VF_CMD! ^
-rc-lookahead 32 !AQ_PARAM! ^
!AUDIO_CH! -c:a aac -b:a 128k ^
-movflags +faststart ^
-y "!OUT_DIR!\%~n1_!RES!p.!EXT!"

if errorlevel 1 echo [ERROR] Failed to process: !input_file!
goto :eof