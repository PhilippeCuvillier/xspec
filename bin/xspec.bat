@echo off

rem
rem ##############################################################################
rem ##
rem ## This script is used to compile a test suite to XSLT, run it, format
rem ## the report and open it in a browser.
rem ##
rem ## It relies on the environment variable SAXON_HOME to be set to the
rem ## dir Saxon has been installed to (i.e. the containing the Saxon JAR
rem ## file), or on SAXON_CP to be set to a full classpath containing
rem ## Saxon (and maybe more).  The latter has precedence over the former.
rem ##
rem ## It also uses the environment variable XSPEC_HOME.  It must be set
rem ## to the XSpec install directory.  By default, it uses this script's
rem ## parent dir.
rem ##
rem ## TODO: Not aware of the EXPath Packaging System
rem ##
rem ##############################################################################
rem
rem Comments (rem)
rem    Comments starting with '#' are derived from xspec.sh (possibly with
rem    some modifications).
rem
rem Environment variables (%FOO%)
rem    Environment variables are tried to be on parity with xspec.sh,
rem    except that those starting with 'WIN_' are only for this batch
rem    file.
rem
rem Labels (:foo)
rem    Labels are tried to be on parity with functions in xspec.sh, except
rem    that those starting with 'win_' are only for this batch file.
rem

rem
rem Skip over "utility functions"
rem
goto :win_main_enter

rem ##
rem ## utility functions #########################################################
rem ##

:usage
    if not "%~1"=="" (
        call :win_echo %1
        echo:
    )
    echo Usage: xspec [-t^|-q^|-s^|-c^|-j^|-catalog file^|-h] file [coverage]
    echo:
    echo   file           the XSpec document
    echo   -t             test an XSLT stylesheet (the default)
    echo   -q             test an XQuery module (mutually exclusive with -t and -s)
    echo   -s             test a Schematron schema (mutually exclusive with -t and -q)
    echo   -c             output test coverage report
    echo   -j             output JUnit report
    echo   -catalog file  use XML Catalog file to locate resources
    echo   -h             display this help message
    echo   coverage       deprecated, use -c instead
    goto :EOF

:die
    echo:
    echo *** %~1 >&2
    rem
    rem Now, to exit the batch file, you must go to :win_main_error_exit from
    rem the main code flow.
    rem
    goto :EOF

:xslt
    java -cp "%CP%" net.sf.saxon.Transform %CATALOG% %*
    goto :EOF

:win_xslt_trace
    rem
    rem Inner Redirect:
    rem    By swapping stdout and stderr, send stderr to pipe (as stdout)
    rem    while allowing original stdout to survive (as stderr)
    rem
    rem Pipe:
    rem    To keep the output XML well-formed, remove the stdout lines
    rem    that don't look like XML element, assuming %COVERAGE_CLASS%
    rem    emits every required line in this format
    rem
    rem Outer Redirect:
    rem    To restore the original direction, swap stdout and stderr again 
    rem
    ( java -cp "%CP%" net.sf.saxon.Transform %CATALOG% %* 3>&2 2>&1 1>&3 | findstr /r /c:"^<..*>$" ) 3>&2 2>&1 1>&3
    goto :EOF

:xquery
    java -cp "%CP%" net.sf.saxon.Query %CATALOG% %*
    goto :EOF

:win_xquery_trace
    rem
    rem As for redirect and pipe, see :win_xslt_trace
    rem
    ( java -cp "%CP%" net.sf.saxon.Query %CATALOG% %* 3>&2 2>&1 1>&3 | findstr /r /c:"^<..*>$" ) 3>&2 2>&1 1>&3
    goto :EOF

:win_reset_options
    set XSLT=
    set XQUERY=
    set SCHEMATRON=
    set SCH_PARAMS=
    set COVERAGE=
    set JUNIT=
    set WIN_HELP=
    set WIN_UNKNOWN_OPTION=
    set WIN_DEPRECATED_COVERAGE=
    set WIN_EXTRA_OPTION=
    set XSPEC=
    set CATALOG=
    goto :EOF

:win_get_options
    set WIN_ARGV=%~1

    if not defined WIN_ARGV (
        goto :EOF
    ) else if "%WIN_ARGV%"=="-t" (
        set XSLT=1
    ) else if "%WIN_ARGV%"=="-q" (
        set XQUERY=1
    ) else if "%WIN_ARGV%"=="-s" (
        set SCHEMATRON=1
    ) else if "%WIN_ARGV%"=="-c" (
        set COVERAGE=1
    ) else if "%WIN_ARGV%"=="-j" (
        set JUNIT=1
    ) else if "%WIN_ARGV%"=="-h" (
        set WIN_HELP=1
    ) else if "%WIN_ARGV%"=="-catalog" (
        set "XML_CATALOG=%~2"
        shift
    ) else if "%WIN_ARGV:~0,1%"=="-" (
        set "WIN_UNKNOWN_OPTION=%WIN_ARGV%"
    ) else if defined XSPEC (
        if "%WIN_ARGV%"=="coverage" (
            set WIN_DEPRECATED_COVERAGE=1
        ) else (
            set "WIN_EXTRA_OPTION=%WIN_ARGV%"
            goto :EOF
        )
    ) else (
        set "XSPEC=%WIN_ARGV%"
    )

    shift

    rem
    rem %* doesn't reflect shift. Pass %n individually.
    rem
    call :win_get_options %1 %2 %3 %4 %5 %6 %7 %8 %9
    goto :EOF


:schematron_compile
    echo Setting up Schematron...
    
    if not defined SCHEMATRON_XSLT_INCLUDE set "SCHEMATRON_XSLT_INCLUDE=%XSPEC_HOME%\src\schematron\iso-schematron\iso_dsdl_include.xsl"
    if not defined SCHEMATRON_XSLT_EXPAND set "SCHEMATRON_XSLT_EXPAND=%XSPEC_HOME%\src\schematron\iso-schematron\iso_abstract_expand.xsl"
    if not defined SCHEMATRON_XSLT_COMPILE set "SCHEMATRON_XSLT_COMPILE=%XSPEC_HOME%\src\schematron\iso-schematron\iso_svrl_for_xslt2.xsl"
    
    rem # get URI to Schematron file and phase/parameters from the XSpec file
    call :xquery -qs:"declare namespace output = 'http://www.w3.org/2010/xslt-xquery-serialization'; declare option output:method 'text'; replace(iri-to-uri(concat(replace(document-uri(/), '(.*)/.*$', '$1'), '/', /*[local-name() = 'description']/@schematron)), concat(codepoints-to-string(94), 'file:/'), '')" ^
        -s:"%XSPEC%" >"%TEST_DIR%\%TARGET_FILE_NAME%-var.txt" ^
        || ( call :die "Error getting Schematron location" & goto :win_main_error_exit )
    set /P SCH=<"%TEST_DIR%\%TARGET_FILE_NAME%-var.txt"
    
    call :xquery -qs:"declare namespace output = 'http://www.w3.org/2010/xslt-xquery-serialization'; declare option output:method 'text'; declare function local:escape($v) { let $w := if (matches($v,codepoints-to-string((91,92,115,34,93)))) then codepoints-to-string(34) else '' return concat($w, replace($v,codepoints-to-string(34),codepoints-to-string((34,34))), $w)}; string-join(for $p in /*/*[local-name() = 'param'] return if ($p/@select) then concat('?',$p/@name,'=',local:escape($p/@select)) else concat($p/@name,'=',local:escape($p/string())),' ')" ^
        -s:"%XSPEC%" >"%TEST_DIR%\%TARGET_FILE_NAME%-var.txt" ^
        || ( call :die "Error getting Schematron phase and parameters" & goto :win_main_error_exit )
    set /P SCH_PARAMS=<"%TEST_DIR%\%TARGET_FILE_NAME%-var.txt"
    echo Paramaters: %SCH_PARAMS%
    set SCHUT=%XSPEC%-compiled.xspec
    set SCH_COMPILED=%SCH%-compiled.xsl
    
    echo:
    echo Compiling the Schematron...
    call :xslt -o:"%TEST_DIR%\%TARGET_FILE_NAME%-sch-temp1.xml" -s:"%SCH%" ^
        -xsl:"%SCHEMATRON_XSLT_INCLUDE%" -versionmsg:off ^
        || ( call :die "Error compiling the Schematron on step 1" & goto :win_main_error_exit )
    call :xslt -o:"%TEST_DIR%\%TARGET_FILE_NAME%-sch-temp2.xml" -s:"%TEST_DIR%\%TARGET_FILE_NAME%-sch-temp1.xml" ^
        -xsl:"%SCHEMATRON_XSLT_EXPAND%" -versionmsg:off ^
        || ( call :die "Error compiling the Schematron on step 2" & goto :win_main_error_exit )
    call :xslt -o:"%SCH_COMPILED%" -s:"%TEST_DIR%\%TARGET_FILE_NAME%-sch-temp2.xml" ^
        -xsl:"%SCHEMATRON_XSLT_COMPILE%" -versionmsg:off ^
        %SCH_PARAMS% ^
        || ( call :die "Error compiling the Schematron on step 3" & goto :win_main_error_exit )
    
    rem use XQuery to get full URI to compiled Schematron
    rem echo SCH_COMPILED %SCH_COMPILED%
    rem call :xquery -qs:"declare namespace output = 'http://www.w3.org/2010/xslt-xquery-serialization'; declare option output:method 'text'; replace(iri-to-uri(document-uri(/)), concat(codepoints-to-string(94), 'file:/'), '')" ^
    rem     -s:"%SCH_COMPILED%" >"%TEST_DIR%\%TARGET_FILE_NAME%-var.txt" ^
    rem     || ( call :die "Error getting compiled Schematron location" & goto :win_main_error_exit )
    rem set /P SCH_COMPILED=<"%TEST_DIR%\%TARGET_FILE_NAME%-var.txt"
    rem echo SCH_COMPILED %SCH_COMPILED%
    
    echo:
    echo Compiling the Schematron tests...
    set TEST_DIR_URI=file:///%TEST_DIR:\=/%
    call :xslt -o:"%SCHUT%" -s:"%XSPEC%" ^
        -xsl:"%XSPEC_HOME%\src\schematron\schut-to-xspec.xsl" ^
        stylesheet="%SCH_COMPILED%" ^
        test_dir="%TEST_DIR_URI%" ^
        || ( call :die "Error compiling the Schematron tests" & goto :win_main_error_exit )
    set XSPEC=%SCHUT%
    echo:
    goto :EOF

:cleanup
	if defined SCHEMATRON (
		del /q "%SCHUT%" 2>nul
		del /q "%TEST_DIR%\context-*.xml" 2>nul
		del /q "%TEST_DIR%\%TARGET_FILE_NAME%-var.txt" 2>nul
		del /q "%TEST_DIR%\%TARGET_FILE_NAME%-sch-temp1.xml" 2>nul
		del /q "%TEST_DIR%\%TARGET_FILE_NAME%-sch-temp2.xml" 2>nul
		del /q "%SCH_COMPILED:/=\%" 2>nul
	)
	goto :EOF

:win_echo
    rem
    rem Prints a message removing its surrounding quotes (")
    rem
    echo %~1
    goto :EOF

rem
rem Main #########################################################################
rem
:win_main_enter

rem
rem Begin localization of environment changes.
rem Also make sure the command processor extensions are enabled.
rem
verify other 2> NUL
setlocal enableextensions
if errorlevel 1 (
    echo Unable to enable extensions
    exit /b %ERRORLEVEL%
)

rem
rem To be compatible with xspec.sh, do not omit this message. It makes the
rem test automation easier.
rem
echo Saxon script not found, invoking JVM directly instead.
echo:

rem
rem ##
rem ## some variables ############################################################
rem ##
rem

rem
rem # the command to use to open the final HTML report
rem
rem Include the command line options (and consequently the double quotes)
rem if necessary.
rem
set OPEN=start "XSpec Report"

rem
rem # set XSPEC_HOME if it has not been set by the user (set it to the
rem # parent dir of this script)
rem
if not defined XSPEC_HOME set XSPEC_HOME=%~dp0..

rem
rem # safety checks
rem
for %%I in ("%XSPEC_HOME%") do echo "%%~aI" | find "d" > NUL
if errorlevel 1 (
    call :win_echo "ERROR: XSPEC_HOME is not a directory: %XSPEC_HOME%"
    exit /b 1
)
if not exist "%XSPEC_HOME%\src\compiler\generate-common-tests.xsl" (
    call :win_echo "ERROR: XSPEC_HOME seems to be corrupted: %XSPEC_HOME%"
    exit /b 1
)

rem
rem # set SAXON_CP (either it has been by the user, or set it from SAXON_HOME)
rem

rem
rem # Set this variable in your environment or here, if you don't set SAXON_CP
rem # set SAXON_HOME=C:\path\to\saxon\dir
rem
rem Since we don't use the delayed environment variable expansion,
rem SAXON_HOME must be set outside 'if' scope.
rem

if not defined SAXON_CP (
    if not defined SAXON_HOME (
        echo SAXON_CP and SAXON_HOME both not set!
    )
    if        exist "%SAXON_HOME%\saxon9ee.jar" (
        set "SAXON_CP=%SAXON_HOME%\saxon9ee.jar"
    ) else if exist "%SAXON_HOME%\saxon9pe.jar" (
        set "SAXON_CP=%SAXON_HOME%\saxon9pe.jar"
    ) else if exist "%SAXON_HOME%\saxon9he.jar" (
        set "SAXON_CP=%SAXON_HOME%\saxon9he.jar"
    ) else if exist "%SAXON_HOME%\saxon9sa.jar" (
        set "SAXON_CP=%SAXON_HOME%\saxon9sa.jar"
    ) else if exist "%SAXON_HOME%\saxon9.jar" (
        set "SAXON_CP=%SAXON_HOME%\saxon9.jar"
    ) else if exist "%SAXON_HOME%\saxonb9-1-0-8.jar" (
        set "SAXON_CP=%SAXON_HOME%\saxonb9-1-0-8.jar"
    ) else if exist "%SAXON_HOME%\saxon8sa.jar" (
        set "SAXON_CP=%SAXON_HOME%\saxon8sa.jar"
    ) else if exist "%SAXON_HOME%\saxon8.jar" (
        set "SAXON_CP=%SAXON_HOME%\saxon8.jar"
    ) else (
        call :win_echo "Saxon jar cannot be found in SAXON_HOME: %SAXON_HOME%"
    )
)
if defined SAXON_HOME (
    if exist "%SAXON_HOME%\xml-resolver-1.2.jar" (
        set "SAXON_CP=%SAXON_CP%;%SAXON_HOME%\xml-resolver-1.2.jar"
    )
)

set CP=%SAXON_CP%;%XSPEC_HOME%\java

rem
rem ##
rem ## options ###################################################################
rem ##
rem

rem
rem Saxon jar filename
rem
for %%I in ("%SAXON_CP:;=";"%") do if /i "%%~xI"==".jar" if /i "%%~nI" GEQ "saxon8" if /i "%%~nI" LSS "saxonb9a" set WIN_SAXON_JAR_N=%%~nI

rem
rem Parse command line
rem
call :win_reset_options
call :win_get_options %*

rem
rem # set CATALOG option for Saxon if XML_CATALOG has been set
rem
if defined XML_CATALOG (
    set CATALOG=-catalog:"%XML_CATALOG%"
)

rem
rem # Schematron
rem # XSLT
rem
if defined SCHEMATRON if defined XSLT (
    call :usage "-s and -t are mutually exclusive"
    exit /b 1
)

rem
rem # Schematron
rem # XQuery
rem
if defined SCHEMATRON if defined XQUERY (
    call :usage "-s and -q are mutually exclusive"
    exit /b 1
)

rem
rem # XSLT
rem # XQuery
rem
if defined XSLT if defined XQUERY (
    call :usage "-t and -q are mutually exclusive"
    exit /b 1
)

rem
rem # Coverage
rem
if defined COVERAGE (
    if /i not "%WIN_SAXON_JAR_N%"=="saxon9pe" if /i not "%WIN_SAXON_JAR_N%"=="saxon9ee" (
        echo Code coverage requires Saxon extension functions which are available only under Saxon9EE or Saxon9PE.
        exit /b 1
    )
)

rem
rem # JUnit report
rem
if defined JUNIT (
    if /i "%WIN_SAXON_JAR_N:~0,6%"=="saxon8" (
        echo Saxon8 detected. JUnit report requires Saxon9.
        exit /b 1
    )
)

rem
rem # Help!
rem
if defined WIN_HELP (
    call :usage
    exit /b 0
)

rem
rem # Unknown option!
rem
if defined WIN_UNKNOWN_OPTION (
    call :usage "Error: Unknown option: %WIN_UNKNOWN_OPTION%"
    exit /b 1
)

rem
rem # set XSLT if XQuery has not been set (that's the default)
rem
if not defined XSLT if not defined XQUERY set XSLT=1

if not exist "%XSPEC%" (
    call :usage "Error: File not found."
    exit /b 1
)

rem
rem Extra option
rem
if defined WIN_EXTRA_OPTION (
    call :usage "Error: Extra option: %WIN_EXTRA_OPTION%"
    exit /b 1
)

rem
rem Deprecated 'coverage' option
rem
if defined WIN_DEPRECATED_COVERAGE (
    echo Long-form option 'coverage' deprecated, use '-c' instead.
    if /i not "%WIN_SAXON_JAR_N%"=="saxon9pe" if /i not "%WIN_SAXON_JAR_N%"=="saxon9ee" (
        echo Code coverage requires Saxon extension functions which are available only under Saxon9EE or Saxon9PE.
        exit /b 1
    )
    set COVERAGE=1
)

rem
rem Env var no longer necessary
rem
set WIN_SAXON_JAR_N=

rem
rem ##
rem ## files and dirs ############################################################
rem ##
rem

if not defined TEST_DIR for %%I in ("%XSPEC%") do set TEST_DIR=%%~dpIxspec
for %%I in ("%XSPEC%") do set TARGET_FILE_NAME=%%~nI

if defined XSLT (
    set "COMPILED=%TEST_DIR%\%TARGET_FILE_NAME%.xsl"
) else (
    set "COMPILED=%TEST_DIR%\%TARGET_FILE_NAME%.xq"
)
set COVERAGE_XML=%TEST_DIR%\%TARGET_FILE_NAME%-coverage.xml
set COVERAGE_HTML=%TEST_DIR%\%TARGET_FILE_NAME%-coverage.html
set RESULT=%TEST_DIR%\%TARGET_FILE_NAME%-result.xml
set HTML=%TEST_DIR%\%TARGET_FILE_NAME%-result.html
set JUNIT_RESULT=%TEST_DIR%\%TARGET_FILE_NAME%-junit.xml
set COVERAGE_CLASS=com.jenitennison.xslt.tests.XSLTCoverageTraceListener

if not exist "%TEST_DIR%" (
    call :win_echo "Creating XSpec Directory at %TEST_DIR%..."
    mkdir "%TEST_DIR%"
    echo:
)

rem
rem ##
rem ## compile the suite #########################################################
rem ##
rem

if defined SCHEMATRON call :schematron_compile || goto :win_main_error_exit

if defined XSLT (
    set COMPILE_SHEET=generate-xspec-tests.xsl
) else (
    set COMPILE_SHEET=generate-query-tests.xsl
)
echo Creating Test Stylesheet...
call :xslt -o:"%COMPILED%" -s:"%XSPEC%" ^
    -xsl:"%XSPEC_HOME%\src\compiler\%COMPILE_SHEET%" ^
    || ( call :die "Error compiling the test suite" & goto :win_main_error_exit )
echo:

rem
rem ##
rem ## run the suite #############################################################
rem ##
rem

echo Running Tests...
if defined XSLT (
    rem
    rem # for XSLT
    rem
    if defined COVERAGE (
        echo Collecting test coverage data; suppressing progress report...
        call :win_xslt_trace -T:%COVERAGE_CLASS% ^
            -o:"%RESULT%" -s:"%XSPEC%" -xsl:"%COMPILED%" ^
            -it:{http://www.jenitennison.com/xslt/xspec}main 2> "%COVERAGE_XML%" ^
            || ( call :die "Error collecting test coverage data" & goto :win_main_error_exit )
    ) else (
        call :xslt -o:"%RESULT%" -s:"%XSPEC%" -xsl:"%COMPILED%" ^
            -it:{http://www.jenitennison.com/xslt/xspec}main ^
            || ( call :die "Error running the test suite" & goto :win_main_error_exit )
    )
) else (
    rem
    rem # for XQuery
    rem
    if defined COVERAGE (
        echo Collecting test coverage data; suppressing progress report...
        call :win_xquery_trace -T:%COVERAGE_CLASS% ^
            -o:"%RESULT%" -s:"%XSPEC%" "%COMPILED%" 2> "%COVERAGE_XML%" ^
            || ( call :die "Error collecting test coverage data" & goto :win_main_error_exit )
    ) else (
        call :xquery -o:"%RESULT%" -s:"%XSPEC%" "%COMPILED%" ^
            || ( call :die "Error running the test suite" & goto :win_main_error_exit )
    )
)

rem
rem ##
rem ## format the report #########################################################
rem ##
rem

echo:
echo Formatting Report...
call :xslt -o:"%HTML%" ^
    -s:"%RESULT%" ^
    -xsl:"%XSPEC_HOME%\src\reporter\format-xspec-report.xsl" ^
    inline-css=true ^
    || ( call :die "Error formatting the report" & goto :win_main_error_exit )

if defined COVERAGE (
    call :xslt -l:on ^
        -o:"%COVERAGE_HTML%" ^
        -s:"%COVERAGE_XML%" ^
        -xsl:"%XSPEC_HOME%\src\reporter\coverage-report.xsl" ^
        tests="%XSPEC%" ^
        inline-css=true ^
        || ( call :die "Error formating the coverage report" & goto :win_main_error_exit )
    call :win_echo "Report available at %COVERAGE_HTML%"
    rem %OPEN% "%COVERAGE_HTML%"
) else if defined JUNIT (
    call :xslt -o:"%JUNIT_RESULT%" ^
        -s:"%RESULT%" ^
        -xsl:"%XSPEC_HOME%\src\reporter\junit-report.xsl" ^
        || ( call :die "Error formating the JUnit report" & goto :win_main_error_exit )
    call :win_echo "Report available at %JUNIT_RESULT%"
) else (
    call :win_echo "Report available at %HTML%"
    rem %OPEN% "%HTML%"
)

call :cleanup

echo Done.
exit /b

rem 
rem Error exit ###################################################################
rem 
:win_main_error_exit
if errorlevel 1 (
    exit /b %ERRORLEVEL%
) else (
    exit /b 1
)
