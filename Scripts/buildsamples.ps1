# Param statement must be first non-comment, non-blank line in the script
Param(
    $LogsPath="g:\logs"
    )

$blocked_Arm = @(
)

$blocked_x86 = @(
)

$blocked_x64 = @(
    "BlinkyApp.sln"
)

$allowed_AnyCpu = @(
)

$blocked_always = @(
    "CompanionAppClient.sln",
    "CustomAdapter.sln",
    "IoTConnector.sln",
    "IoTConnectorClient.sln",
    "NodeBlinkyServer.sln",
    "NodeJsBlinky.sln",
    "IoTOnboarding.sln"
)

$blocked_endswith = @(
    "node.js\BlinkyClient.sln",
    "node.js\BlinkyClient.sln"
)

$drivers = @(
)

function PressAnyKey()
{
    Write-Host "Press any key to continue ..."
    $x = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}

function TestFullPathEndsWith($path, $list)
{
    foreach($s in $list)
    {
        if($path.EndsWith($s))
        {
            return $true;
        }
    }
    return $false;
}

function restoreConfigs($filename, $solutionDir)
{
	write-host -ForegroundColor Cyan "nuget.exe restore $filename"
	&"c:\Program Files (x86)\Microsoft Visual Studio\2017\Enterprise\MSBuild\ReadyRoll\OctoPack\build\NuGet.exe" restore $filename
	
    $configFiles = Get-ChildItem packages.config -Recurse
    foreach($c in $configFiles)
    {
        $fullname = $c.FullName
        write-host -ForegroundColor Cyan "nuget.exe restore $fullname -SolutionDirectory $path"
        &"c:\Program Files (x86)\Microsoft Visual Studio\2017\Enterprise\MSBuild\ReadyRoll\OctoPack\build\NuGet.exe" restore $fullname
    }
}

function SkipThisFile($file)
{
    $filename = $file.Name

    if (TestFullPathEndsWith $file.FullName $blocked_endswith)
    {
        return $true;
    }
    if (TestFullPathEndsWith $file.FullName $drivers)
    {
        return $true;
    }
    if ($blocked_always.Contains($filename))
    {
        return $true;
    }
    if ($platform -eq "ARM")
    {
        if ($blocked_Arm.Contains($filename))
        {
            return $true;
        }
    }
    if ($platform -eq "x86")
    {
        if ($blocked_x86.Contains($filename))
        {
            return $true;
        }
    }
    if ($platform -eq "x64")
    {
        if ($blocked_x64.Contains($filename))
        {
            return $true;
        }
    }
    if ($platform -eq '"Any CPU"')
    {
        if (!($allowed_AnyCpu.Contains($filename)))
        {
            return $true;
        }
    }
    return $false;
}

function restoreNuget($file)
{
    if (SkipThisFile $file)
    {
        return
    }

    $filename = $file.Name
    $path = split-path $file.FullName -Parent
    Write-Host -ForegroundColor Cyan "Found $file"
    pushd $path
    restoreConfigs "packages.config" $path
    restoreConfigs "project.json" $path
    popd
}

function Get-MSBuild-Path {

    $vs14key = "HKLM:\SOFTWARE\Microsoft\MSBuild\ToolsVersions\14.0"
    $vs15key = "HKLM:\SOFTWARE\wow6432node\Microsoft\VisualStudio\SxS\VS7"

    $msbuildPath = ""

    if (Test-Path $vs14key) {
        $key = Get-ItemProperty $vs14key
        $subkey = $key.MSBuildToolsPath
        if ($subkey) {
            $msbuildPath = Join-Path $subkey "msbuild.exe"
        }
    }

    if (Test-Path $vs15key) {
        $key = Get-ItemProperty $vs15key
        $subkey = $key."15.0"
        if ($subkey) {
            $msbuildPath = Join-Path $subkey "MSBuild\15.0\bin\msbuild.exe"
        }
    }

    return $msbuildPath

}

function buildSolution($file, $config, $platform, $logPlatform)
{
	$msbuildpath = Get-MSBuild-Path
    $filename = $file.Name
	
	$language = ""
	#write-host $file.FullName.ToLower()
	if ($file.FullName.ToLower().Contains("cpp")) {
		$language = ".CPP";
	} elseif ($file.FullName.ToLower().Contains("cs")) {
		$language = ".CS";
	} elseif ($file.FullName.ToLower().Contains("vb")) {
		$language = ".VB";
	} elseif ($file.FullName.ToLower().Contains("node.js")) {
		$language = ".Node-js";
	} elseif ($file.FullName.ToLower().Contains("python")) {
		$language = ".Python";
	}
	
    #write-host -ForegroundColor Cyan "$LogsPath\$filename.$config$language.$logPlatform.log"
    $logPath = "$LogsPath\$filename.$config$language.$logPlatform.log"
    if (Test-Path $logPath ){ del $logPath }

    if (SkipThisFile $file)
    {
         write-host "skipping $filename $config $platform"
		 Add-Content $logPath "Build skipped."
         return;
    }
	
    $logCommand = "/logger:FileLogger,Microsoft.Build.Engine;logfile=$logPath"
    write-host -ForegroundColor Cyan "${msbuildpath} $file `"/t:clean;restore;build /verbosity:normal`" `"/p:Configuration=$config`" `"/p:Platform=$platform`" $logCommand"
    &"$msbuildpath" $file "/t:clean;restore;build" /verbosity:normal /p:Configuration=$config /p:Platform=$platform ${logCommand}

    #$errors = findstr "Error\(s\)" "$logPath"
    #write-host -ForegroundColor Red $errors
}

$StartTime = $(get-date)

# del $LogsPath\*
$files = Get-ChildItem "*.sln" -Recurse

foreach ($f in $files)
{
    restoreNuget $f
    buildSolution $f "Release" "x86" "x86"
    buildSolution $f "Debug" "x86" "x86"
    buildSolution $f "Release" "x64" "x64"
    buildSolution $f "Debug" "x64" "x64"
    buildSolution $f "Release" "ARM" "ARM"
    buildSolution $f "Debug" "ARM" "ARM"
    buildSolution $f "Release" '"Any CPU"' "AnyCPU"
    buildSolution $f "Debug" '"Any CPU"' "AnyCPU"
}

$succeeded = Get-ChildItem -Recurse -Path $LogsPath -Include *.log | select-string "Build [sf][kua][~ ]*"
foreach ($bs in $succeeded) {
	$out = $bs -split ":[0-9]*:"
	$color = "Green"
	if ($out[1].Equals("Build FAILED.")) {
		$color = "Red"
	} elseif ($out[1].Equals("Build skipped.")) {
		$color = "Cyan"
	} 
	write-host -ForegroundColor $color $out[0] - $out[1]
}

$elapsedTime = $(get-date) - $StartTime

#write-host "Duration {0:HH:mm:ss}" -f ([datetime]$elapsedTime.Ticks)
