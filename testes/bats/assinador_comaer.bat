@echo off

SET ASSINADOR_HOME=%HOMEPATH%\Assinador Digital COMAER

reg Query "HKLM\Hardware\Description\System\CentralProcessor\0" | find /i "x86" > NUL && set OSTYPE=32BIT || set OSTYPE=64BIT

if %OSTYPE%==32BIT SET JAVABIN=java32\bin\java.exe
if %OSTYPE%==64BIT SET JAVABIN=java64\bin\java.exe

set torun=wmic os get FreePhysicalMemory /format:value
for /f "tokens=2 delims==" %%a in ('%torun%') do set FREEMEMORY=%%a

IF %FREEMEMORY% LSS 262144 (
    %JAVABIN% -Dassinador.logdir="%ASSINADOR_HOME%" -cp assinador-ccasj.jar br.ccasj.sigadaer.assinador.addon.RespondError "Erro ao iniciar o Assinador" "Memoria INSUFICIENTE"
    @EXIT /b
)

@SET XMX=-Xmx256m

IF %FREEMEMORY% GTR 524288 (
     @SET XMX=-Xmx512m
)

IF %FREEMEMORY% GTR 1048576 (
     @SET XMX=-Xmx1024m
)

%JAVABIN% -Xms256m %XMX% -Dassinador.logdir="%ASSINADOR_HOME%" -cp assinador-ccasj.jar br.ccasj.sigadaer.assinador.addon.AssinadorWebExt
