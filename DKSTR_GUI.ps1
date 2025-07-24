Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Drawing.Drawing2D

# --- SHADOW-DOMINION CORE UTILITIES ---
function Write-ShadowLog {
    param(
        [string]$Message,
        [string]$Level = "LOG" # LOG, WARNING, ERROR, CRITICAL, SUCCESS, DEBUG, EXEC, HINT
    )
    $Timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$Timestamp][SHADOW-$Level] $Message" -ForegroundColor DarkGray
    if ($Level -eq "WARNING") { Write-Host "$Message" -ForegroundColor Yellow }
    if ($Level -eq "ERROR") { Write-Host "$Message" -ForegroundColor Red }
    if ($Level -eq "CRITICAL") { Write-Host "$Message" -ForegroundColor DarkRed }
    if ($Level -eq "SUCCESS") { Write-Host "$Message" -ForegroundColor Green }
    if ($Level -eq "EXEC") { Write-Host "$Message" -ForegroundColor Cyan }
    if ($Level -eq "DEBUG") { Write-Host "$Message" -ForegroundColor DarkCyan }
    if ($Level -eq "HINT") { Write-Host "$Message" -ForegroundColor Magenta }
}

function Find-JavaExecutable {
    param(
        [string]$ManualJavaPath = $null
    )
    if (-not [string]::IsNullOrEmpty($ManualJavaPath)) {
        if (Test-Path $ManualJavaPath) {
            Write-ShadowLog "Manually specified Java path: $ManualJavaPath" -Level LOG
            return $ManualJavaPath
        } else {
            Write-ShadowLog "Manually specified Java path '$ManualJavaPath' not found. Attempting auto-detection." -Level WARNING
        }
    }

    $javaPath = (Get-Command java.exe -ErrorAction SilentlyContinue).Source
    if ($javaPath) {
        Write-ShadowLog "Java detected in system PATH: $javaPath" -Level LOG
        return $javaPath
    }

    $programFiles = [Environment]::GetFolderPath("ProgramFiles")
    $programFilesX86 = [Environment]::GetFolderPath("ProgramFilesX86")

    $potentialJavaDirs = @(
        (Join-Path $programFiles "Java"),
        (Join-Path $programFilesX86 "Java"),
        "$Env:JAVA_HOME\bin"
    )

    foreach ($baseDir in $potentialJavaDirs) {
        if (Test-Path $baseDir) {
            Get-ChildItem -Path $baseDir -Filter "java.exe" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
                Write-ShadowLog "Java executable discovered at: $($_.FullName)" -Level LOG
                return $_.FullName
            }
        }
    }

    Write-ShadowLog "Java executable not found. Ensure Java is installed and in your PATH." -Level CRITICAL
    return $null
}

function Find-MinecraftJavaDirectory {
    param(
        [string]$ManualMinecraftDirectory = $null
    )
    if (-not [string]::IsNullOrEmpty($ManualMinecraftDirectory)) {
        if (Test-Path $ManualMinecraftDirectory -PathType Container) {
            Write-ShadowLog "Manually specified .minecraft directory: $ManualMinecraftDirectory" -Level LOG
            return $ManualMinecraftDirectory
        } else {
            Write-ShadowLog "Manually specified .minecraft directory '$ManualMinecraftDirectory' not found. Attempting auto-detection." -Level WARNING
        }
    }

    $mcDir = Join-Path ([Environment]::GetFolderPath("ApplicationData")) ".minecraft"
    if (Test-Path $mcDir -PathType Container) {
        Write-ShadowLog "Minecraft Java directory identified: $mcDir" -Level LOG
        return $mcDir
    } else {
        Write-ShadowLog "Minecraft Java installation directory not found at expected path: $mcDir. Ensure Minecraft Java Edition is installed." -Level CRITICAL
        return $null
    }
}

function Evaluate-MinecraftJavaRules {
    param(
        [array]$Rules
    )
    $allow = $true

    foreach ($rule in $Rules) {
        $conditionsMet = $true
        $action = $rule.action

        if ($rule.os) {
            $osName = $rule.os.name
            $currentOS = ""
            if ($IsWindows) { $currentOS = "windows" }
            elseif ($IsLinux) { $currentOS = "linux" }
            elseif ($IsMacOS) { $currentOS = "osx" }
            
            if ($osName -and ($osName -ne $currentOS)) {
                $conditionsMet = $false
            }
        }
        
        if ($conditionsMet) {
            if ($action -eq "allow") { return $true }
            if ($action -eq "disallow") { return $false }
        }
    }
    return $allow
}

function Resolve-ArgumentReplacements {
    param(
        [string]$ArgumentString,
        [hashtable]$Replacements
    )
    $resolvedArg = $ArgumentString
    foreach ($key in $Replacements.Keys) {
        $value = $Replacements[$key]
        $resolvedArg = $resolvedArg.Replace($key, $value)
    }
    return $resolvedArg
}

function Extract-MinecraftJavaNatives {
    param(
        [string]$NativeJarPath,
        [string]$ExtractionPath
    )
    Write-ShadowLog "Extracting natives from '$NativeJarPath' to '$ExtractionPath'..." -Level DEBUG
    try {
        if (-not (Test-Path $ExtractionPath)) {
            New-Item -ItemType Directory -Path $ExtractionPath | Out-Null
        }
        
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($NativeJarPath, $ExtractionPath)
        Write-ShadowLog "Natives extracted successfully from $($NativeJarPath | Split-Path -Leaf)." -Level LOG
        return $true
    } catch {
        Write-ShadowLog "Failed to extract natives from $($NativeJarPath | Split-Path -Leaf): $($_.Exception.Message)" -Level WARNING
        return $false
    }
}

function Start-MinecraftJavaDirectLaunch {
    param(
        [Parameter(Mandatory=$true)]
        [string]$MinecraftVersion,
        [Parameter(Mandatory=$true)]
        [string]$Username,
        [string]$JavaPath = $null,
        [string]$MinecraftDirectory = $null,
        [string]$AccessToken = "INVALID_SHADOW_TOKEN",
        [string]$UUID = ([guid]::NewGuid().ToString().Replace("-", "")),
        [string]$ResolutionWidth = "854",
        [string]$ResolutionHeight = "480"
    )

    Write-ShadowLog "Initiating DIRECT LAUNCH PROTOCOL for Minecraft Java Edition $MinecraftVersion..." -Level EXEC

    $javaExe = Find-JavaExecutable -ManualJavaPath $JavaPath
    if (-not $javaExe) {
        Write-ShadowLog "Java executable not found. Aborting direct launch." -Level CRITICAL
        return $false
    }

    $mcGameDir = Find-MinecraftJavaDirectory -ManualMinecraftDirectory $MinecraftDirectory
    if (-not $mcGameDir) {
        Write-ShadowLog "Minecraft Java game directory not found. Aborting direct launch." -Level CRITICAL
        return $false
    }

    $versionsDir = Join-Path $mcGameDir "versions"
    $versionPath = Join-Path $versionsDir $MinecraftVersion
    $versionJsonPath = Join-Path $versionPath "$MinecraftVersion.json"
    $versionJarPath = Join-Path $versionPath "$MinecraftVersion.jar"

    if (-not (Test-Path $versionJsonPath) -or -not (Test-Path $versionJarPath)) {
        Write-ShadowLog "Target Minecraft Java version '$MinecraftVersion' manifest or JAR not found in '$versionPath'." -Level CRITICAL
        Write-ShadowLog "Ensure this version has been downloaded at least once via an official Minecraft launcher." -Level HINT
        Write-ShadowLog "Verify the 'MinecraftVersion' parameter matches an existing folder name in your '.minecraft\versions\' directory." -Level HINT
        return $false
    }

    try {
        $versionManifest = Get-Content $versionJsonPath -Raw | ConvertFrom-Json
        Write-ShadowLog "Version manifest for $MinecraftVersion decoded." -Level LOG
    } catch {
        Write-ShadowLog "Failed to decode version manifest JSON: $($_.Exception.Message). Data integrity compromised. Aborting." -Level CRITICAL
        return $false
    }

    $classpathElements = @()
    $classpathElements += $versionJarPath

    $libsDir = Join-Path $mcGameDir "libraries"
    $nativesTempDir = Join-Path $mcGameDir "natives" $MinecraftVersion
    
    foreach ($lib in $versionManifest.libraries) {
        if ($lib.rules) {
            if (-not (Evaluate-MinecraftJavaRules $lib.rules)) {
                continue
            }
        }

        $libNameParts = $lib.name.Split(':')
        $groupIdPath = $libNameParts[0].Replace('.', [IO.Path]::DirectorySeparatorChar)
        $artifactId = $libNameParts[1]
        $version = $libNameParts[2]

        if ($lib.natives) {
            $currentOS = ""
            if ($IsWindows) { $currentOS = "windows" }
            elseif ($IsLinux) { $currentOS = "linux" }
            elseif ($IsMacOS) { $currentOS = "osx" }
            
            if ($lib.natives.$currentOS) {
                $classifier = $lib.natives.$currentOS
                if ($classifier -like "*${arch}*") {
                    $arch = if ([IntPtr]::Size -eq 8) { "64" } else { "32" }
                    $classifier = $classifier.Replace('${arch}', $arch)
                }
                
                $libFileName = "$artifactId-$version-$classifier.jar"
                $nativeJarPath = Join-Path $libsDir $groupIdPath $artifactId $version $libFileName
                
                if (Test-Path $nativeJarPath) {
                    if (-not (Extract-MinecraftJavaNatives $nativeJarPath $nativesTempDir)) {
                        Write-ShadowLog "Skipping potentially problematic native library: $($lib.name)" -Level WARNING
                    }
                } else {
                    Write-ShadowLog "Native library JAR not found: $nativeJarPath" -Level WARNING
                }
                continue
            }
        }

        $libFileName = "$artifactId-$version.jar"
        $fullLibPath = Join-Path $libsDir $groupIdPath $artifactId $version $libFileName
        
        if (Test-Path $fullLibPath) {
            $classpathElements += $fullLibPath
        } else {
            Write-ShadowLog "Library not found at expected path: $fullLibPath. Dependency unresolved." -Level WARNING
        }
    }

    $mainClass = $versionManifest.mainClass
    
    $replacements = @{
        "${auth_access_token}" = $AccessToken;
        "${user_properties}" = "{}";
        "${assets_root}" = (Join-Path $mcGameDir "assets");
        "${assets_index}" = $versionManifest.assetIndex.id;
        "${auth_uuid}" = $UUID;
        "${auth_player_name}" = $Username;
        "${game_directory}" = $mcGameDir;
        "${version_name}" = $MinecraftVersion;
        "${version_type}" = $versionManifest.type;
        "${game_assets}" = (Join-Path $mcGameDir "assets");
        "${clientid}" = ([guid]::NewGuid().ToString().Replace("-", "")).Substring(0, 16);
        "${auth_xuid}" = "0";
        "${resolution_width}" = $ResolutionWidth;
        "${resolution_height}" = $ResolutionHeight
    }

    $jvmArgs = @()
    if (Test-Path $nativesTempDir) {
        $jvmArgs += "-Djava.library.path=$nativesTempDir"
    } else {
        Write-ShadowLog "Natives directory not found for JVM path: $nativesTempDir. Game might not launch correctly without natives." -Level WARNING
    }

    foreach ($arg in $versionManifest.arguments.jvm) {
        if ($arg -is [string]) {
            $jvmArgs += (Resolve-ArgumentReplacements $arg $replacements)
        } elseif ($arg -is [hashtable] -and $arg.rules) {
            if (Evaluate-MinecraftJavaRules $arg.rules) {
                if ($arg.value -is [array]) {
                    foreach ($valPart in $arg.value) {
                        $jvmArgs += (Resolve-ArgumentReplacements $valPart $replacements)
                    }
                } else {
                    $jvmArgs += (Resolve-ArgumentReplacements $arg.value $replacements)
                }
            }
        }
    }

    $finalClasspathStr = $classpathElements -join [IO.Path]::PathSeparator
    $jvmArgs += "-Djava.class.path=$finalClasspathStr"
    
    $jvmArgs += @(
        "-Xmx2G",
        "-Xms256M",
        "-XX:+UnlockExperimentalVMOptions",
        "-XX:+UseG1GC",
        "-XX:G1NewSizePercent=20",
        "-XX:G1ReservePercent=20",
        "-XX:MaxGCPauseMillis=50",
        "-XX:G1HeapRegionSize=32M",
        "-Dminecraft.client.json=$versionJsonPath",
        "-Dminecraft.applet.TargetDirectory=$mcGameDir"
    )

    $gameArgs = @()
    foreach ($arg in $versionManifest.arguments.game) {
        if ($arg -is [string]) {
            $gameArgs += (Resolve-ArgumentReplacements $arg $replacements)
        } elseif ($arg -is [hashtable] -and $arg.rules) {
            if (Evaluate-MinecraftJavaRules $arg.rules) {
                if ($arg.value -is [array]) {
                    foreach ($valPart in $arg.value) {
                        $gameArgs += (Resolve-ArgumentReplacements $valPart $replacements)
                    }
                } else {
                    $gameArgs += (Resolve-ArgumentReplacements $arg.value $replacements)
                }
            }
        }
    }
    
    $commandArguments = ($jvmArgs + $mainClass + $gameArgs) -join ' '

    try {
        Write-ShadowLog "Launching JVM process directly. Trailer protocol subverted for Java Edition." -Level EXEC
        
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $javaExe
        $processInfo.Arguments = $commandArguments
        $processInfo.WorkingDirectory = $mcGameDir
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        
        $process = [System.Diagnostics.Process]::Start($processInfo)
        
        Write-ShadowLog "Minecraft Java Launch Process Engaged. PID: $($process.Id)" -Level SUCCESS
        Write-ShadowLog "Any intermediary pre-launch mechanisms have been bypassed and neutralized." -Level LOG
        return $true
        
    } catch {
        Write-ShadowLog "An unforeseen system anomaly occurred during Java launch: $($_.Exception.Message)" -Level CRITICAL
        return $false
    } finally {
        if (Test-Path $nativesTempDir -PathType Container) {
            try {
                Remove-Item -Path $nativesTempDir -Recurse -Force -ErrorAction SilentlyContinue
                Write-ShadowLog "Temporary Java native libraries purged from: $nativesTempDir" -Level LOG
            } catch {
                Write-ShadowLog "Failed to purge Java native directory: $($_.Exception.Message). Manual cleanup may be required." -Level WARNING
            }
        } else {
            Write-ShadowLog "No temporary Java native directory found for cleanup." -Level LOG
        }
    }
}

function Start-MinecraftBedrockLaunch {
    param(
        [string]$Protocol = "minecraft://", # Default protocol
        [string]$Message = "Launching Minecraft Bedrock Edition via URI protocol."
    )
    Write-ShadowLog $Message -Level EXEC
    try {
        Start-Process -FilePath $Protocol -ErrorAction Stop
        Write-ShadowLog "Minecraft Bedrock Edition launched successfully." -Level SUCCESS
        return $true
    } catch {
        Write-ShadowLog "Failed to launch Minecraft Bedrock Edition via URI protocol: $($_.Exception.Message)" -Level CRITICAL
        Write-ShadowLog "Ensure Minecraft for Windows (Bedrock) is installed and its URI protocol handlers are registered." -Level HINT
        Write-ShadowLog "Error details: $($_.Exception.ToString())" -Level DEBUG
        return $false
    }
}

# --- DKSTR Tools GUI Code, integrated with SHADOWHacker-GOD functions ---

$exeDirectory = Split-Path -Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
$assetPath = Join-Path -Path $exeDirectory -ChildPath "assets"

# Main window
$mainForm = New-Object Windows.Forms.Form
$mainForm.Text = "DKSTR Tools"
$mainForm.Size = New-Object Drawing.Size(1000, 600)
$mainForm.StartPosition = "CenterScreen"
$mainForm.FormBorderStyle = "FixedDialog"
$mainForm.MaximizeBox = $false
$mainForm.MinimizeBox = $true

# Background
try {
    $mainBgImage = [System.Drawing.Image]::FromFile((Join-Path $assetPath "DKSTR.jpg"))
    $mainForm.BackgroundImage = $mainBgImage
    $mainForm.BackgroundImageLayout = "Stretch"
} catch {
    $mainForm.BackColor = "Black"
    Write-ShadowLog "Failed to load main background image: $($_.Exception.Message). Using black background." -Level WARNING
}

# Function to create a rounded button
function Create-RoundedButton {
    param($text, $x, $y, $color, $action)

    $button = New-Object Windows.Forms.Button
    $button.Text = $text
    $button.Size = New-Object Drawing.Size(280, 50)
    $button.Location = New-Object Drawing.Point($x, $y)
    $button.ForeColor = "White"
    $button.Font = New-Object Drawing.Font("Arial", 10, [Drawing.FontStyle]::Bold)
    $button.FlatStyle = "Flat"
    $button.FlatAppearance.BorderSize = 0
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Region = [System.Drawing.Region]::FromHrgn((CreateRoundRectRgn 0 0 $button.Width $button.Height 20 20))
    $button.BackColor = $color

    $button.Add_Click($action)
    return $button
}

# Function to create an icon button with smooth animated scaling
function Create-IconButton {
    param($imagePath, $x, $y, $action)

    $button = New-Object Windows.Forms.Button
    $button.Size = New-Object Drawing.Size(40, 40)
    $button.Location = New-Object Drawing.Point($x, $y)
    $button.FlatStyle = "Flat"
    $button.FlatAppearance.BorderSize = 0
    $button.FlatAppearance.MouseDownBackColor = [System.Drawing.Color]::Transparent
    $button.FlatAppearance.MouseOverBackColor = [System.Drawing.Color]::Transparent
    $button.BackColor = [System.Drawing.Color]::Transparent
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand

    try {
        $image = [System.Drawing.Image]::FromFile($imagePath)
        $button.BackgroundImage = $image
        $button.BackgroundImageLayout = "Stretch"
    } catch {
        $button.Text = "Icon"
        Write-ShadowLog "Could not load icon image from: $imagePath. Using text instead." -Level WARNING
    }

    # Animated Scale effect setup
    $timer = New-Object Windows.Forms.Timer
    $timer.Interval = 15
    $targetScale = 1.2
    $currentScale = 1.0
    $scalingIn = $false

    $button.Add_MouseEnter({
        $scalingIn = $true
        $timer.Start()
    })
    
    $button.Add_MouseLeave({
        $scalingIn = $false
        $timer.Start()
    })

    $timer.Add_Tick({
        if ($scalingIn) {
            if ($currentScale -lt $targetScale) {
                $currentScale = [math]::Min($currentScale + 0.05, $targetScale)
                $newSize = [math]::Round(40 * $currentScale)
                $button.Size = New-Object Drawing.Size($newSize, $newSize)
                $button.Location = New-Object Drawing.Point(
                    $x - ($newSize - 40)/2,
                    $y - ($newSize - 40)/2
                )
            } else {
                $timer.Stop()
            }
        } else {
            if ($currentScale -gt 1.0) {
                $currentScale = [math]::Max($currentScale - 0.05, 1.0)
                $newSize = [math]::Round(40 * $currentScale)
                $button.Size = New-Object Drawing.Size($newSize, $newSize)
                $button.Location = New-Object Drawing.Point(
                    $x - ($newSize - 40)/2,
                    $y - ($newSize - 40)/2
                )
            } else {
                $timer.Stop()
            }
        }
    })

    $button.Add_Click($action)
    return $button
}

# Rounded region function for button shapes
function CreateRoundRectRgn {
    param($x, $y, $width, $height, $radius, $radius2)
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class RGN {
    [DllImport("Gdi32.dll", EntryPoint = "CreateRoundRectRgn")]
    public static extern IntPtr CreateRoundRectRgn(int nLeftRect, int nTopRect, int nRightRect, int nBottomRect, int nWidthEllipse, int nHeightEllipse);
}
"@
    return [RGN]::CreateRoundRectRgn($x, $y, $width, $height, $radius, $radius2)
}

# Minecraft Tools Page (Java & Bedrock)
$minecraftForm = New-Object Windows.Forms.Form
$minecraftForm.Text = "Minecraft Tools"
$minecraftForm.Size = New-Object Drawing.Size(1000, 600)
$minecraftForm.StartPosition = "CenterScreen"
$minecraftForm.FormBorderStyle = "FixedDialog"
$minecraftForm.MaximizeBox = $false
$minecraftForm.MinimizeBox = $true

try {
    $minecraftBgImage = [System.Drawing.Image]::FromFile((Join-Path $assetPath "DKSTRR.jpg"))
    $minecraftForm.BackgroundImage = $minecraftBgImage
    $minecraftForm.BackgroundImageLayout = "Stretch"
} catch {
    $minecraftForm.BackColor = "Black"
    Write-ShadowLog "Failed to load Minecraft background image: $($_.Exception.Message). Using black background." -Level WARNING
}

# --- Java Edition Launch Controls ---
$lblJavaVersion = New-Object Windows.Forms.Label
$lblJavaVersion.Text = "Java Edition Version:"
$lblJavaVersion.ForeColor = "White"
$lblJavaVersion.BackColor = [System.Drawing.Color]::Transparent
$lblJavaVersion.AutoSize = $true
$lblJavaVersion.Location = New-Object Drawing.Point(360, 100)
$minecraftForm.Controls.Add($lblJavaVersion)

$txtJavaVersion = New-Object Windows.Forms.TextBox
$txtJavaVersion.Text = "1.20.4" # Default Java version
$txtJavaVersion.Size = New-Object Drawing.Size(280, 25)
$txtJavaVersion.Location = New-Object Drawing.Point(360, 125)
$minecraftForm.Controls.Add($txtJavaVersion)

$lblJavaUsername = New-Object Windows.Forms.Label
$lblJavaUsername.Text = "Java Edition Username:"
$lblJavaUsername.ForeColor = "White"
$lblJavaUsername.BackColor = [System.Drawing.Color]::Transparent
$lblJavaUsername.AutoSize = $true
$lblJavaUsername.Location = New-Object Drawing.Point(360, 160)
$minecraftForm.Controls.Add($lblJavaUsername)

$txtJavaUsername = New-Object Windows.Forms.TextBox
$txtJavaUsername.Text = "SHADOW_PLAYER" # Default Java username
$txtJavaUsername.Size = New-Object Drawing.Size(280, 25)
$txtJavaUsername.Location = New-Object Drawing.Point(360, 185)
$minecraftForm.Controls.Add($txtJavaUsername)

$btnLaunchJavaMinecraft = Create-RoundedButton "Launch Minecraft Java Edition (Direct)" 360 240 ([System.Drawing.Color]::FromArgb(50, 50, 150)) {
    $confirmLaunch = [System.Windows.Forms.MessageBox]::Show(
        "Are you sure you want to launch Minecraft Java Edition directly? This will bypass any external launcher.",
        "Confirm Java Launch",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($confirmLaunch -eq [System.Windows.Forms.DialogResult]::Yes) {
        $mcJavaVersion = $txtJavaVersion.Text
        $mcJavaUsername = $txtJavaUsername.Text
        Write-ShadowLog "Attempting to launch Minecraft Java Edition version: $mcJavaVersion with username: $mcJavaUsername" -Level LOG
        $launchSuccess = Start-MinecraftJavaDirectLaunch -MinecraftVersion $mcJavaVersion -Username $mcJavaUsername
        if ($launchSuccess) {
            [System.Windows.Forms.MessageBox]::Show("Minecraft Java Edition launched successfully! Any trailer or launcher pre-checks bypassed.", "Launch Success", "OK", "Information")
        } else {
            [System.Windows.Forms.MessageBox]::Show("Failed to launch Minecraft Java Edition. Please check the PowerShell console for errors.", "Launch Failed", "OK", "Error")
        }
    }
}
$minecraftForm.Controls.Add($btnLaunchJavaMinecraft)

# --- Bedrock Edition Launch Controls ---
$btnLaunchBedrock = Create-RoundedButton "Launch Minecraft Bedrock Edition (MCsenters Style)" 360 320 ([System.Drawing.Color]::FromArgb(150, 50, 150)) {
    $confirmBedrockLaunch = [System.Windows.Forms.MessageBox]::Show(
        "Are you sure you want to launch Minecraft Bedrock Edition? This attempts a direct launch via URI.",
        "Confirm Bedrock Launch",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($confirmBedrockLaunch -eq [System.Windows.Forms.DialogResult]::Yes) {
        $bedrockLaunchSuccess = Start-MinecraftBedrockLaunch
        if ($bedrockLaunchSuccess) {
            # No message box here, success message is logged
        } else {
            [System.Windows.Forms.MessageBox]::Show("Failed to launch Minecraft Bedrock Edition. Ensure the game is installed and try running this script as administrator.", "Bedrock Launch Failed", "OK", "Error")
        }
    }
}
$minecraftForm.Controls.Add($btnLaunchBedrock)

# Back button
$btnBack = Create-RoundedButton "Back to Main Menu" 360 450 ([System.Drawing.Color]::Gray) {
    $minecraftForm.Hide()
    $mainForm.Show()
}
$minecraftForm.Controls.Add($btnBack)

# Main Form Buttons
$mainForm.Controls.Add((Create-RoundedButton "Optimize Performance" 100 120 ([System.Drawing.Color]::FromArgb(50, 150, 50)) {
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    [System.Windows.Forms.MessageBox]::Show("System performance optimized!", "Success", "OK", "Information")
}))

$mainForm.Controls.Add((Create-RoundedButton "Clean Temp Files" 100 200 ([System.Drawing.Color]::FromArgb(50, 150, 50)) {
    Write-ShadowLog "Starting temporary file cleanup..." -Level EXEC
    $closedCount = 0
    try {
        Get-ChildItem -Path $env:TEMP -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try { Remove-Item $_.FullName -Force -Recurse -ErrorAction Stop; $closedCount++ } catch {}
        }
        if ((Test-Path "C:\Windows\Temp")) {
            Get-ChildItem -Path "C:\Windows\Temp" -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
                try { Remove-Item $_.FullName -Force -Recurse -ErrorAction Stop; $closedCount++ } catch {}
            }
        }
        [System.Windows.Forms.MessageBox]::Show("Cleaned $closedCount temporary files.", "Done", "OK", "Information")
        Write-ShadowLog "Temporary files cleaned: $closedCount files." -Level SUCCESS
    } catch {
        [System.Windows.Forms.MessageBox]::Show("An error occurred during temp file cleanup: $($_.Exception.Message). Ensure running as administrator.", "Error", "OK", "Error")
        Write-ShadowLog "Failed to clean temporary files: $($_.Exception.Message)" -Level ERROR
    }
}))

$mainForm.Controls.Add((Create-RoundedButton "Empty Recycle Bin" 100 280 ([System.Drawing.Color]::FromArgb(50, 150, 50)) {
    try {
        Clear-RecycleBin -Force -ErrorAction Stop
        [System.Windows.Forms.MessageBox]::Show("Recycle bin emptied!", "Done", "OK", "Information")
        Write-ShadowLog "Recycle bin emptied." -Level SUCCESS
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Failed to empty recycle bin: $($_.Exception.Message)", "Error", "OK", "Error")
        Write-ShadowLog "Failed to empty recycle bin: $($_.Exception.Message)" -Level ERROR
    }
}))

$btnFlushDNS = Create-RoundedButton "Flush DNS Cache" 600 130 ([System.Drawing.Color]::FromArgb(50, 150, 50)) {
    try {
        ipconfig /flushdns | Out-Null
        [System.Windows.Forms.MessageBox]::Show("DNS cache flushed successfully!", "Success", "OK", "Information")
        Write-ShadowLog "DNS cache flushed." -Level SUCCESS
    } catch {
        [System.Windows.Forms.MessageBox]::Show("An error occurred, ensure running as administrator.", "Error", "OK", "Error")
        Write-ShadowLog "Failed to flush DNS cache: $($_.Exception.Message)" -Level ERROR
    }
}
$mainForm.Controls.Add($btnFlushDNS)

$mainForm.Controls.Add((Create-RoundedButton "Close Background Apps" 100 360 ([System.Drawing.Color]::FromArgb(50, 150, 50)) {
    Write-ShadowLog "Starting background app shutdown..." -Level EXEC
    $appsToClose = "notepad","calculator","Paint","OneDrive","Skype","Teams","msedge","chrome","firefox","spotify","discord"
    $closedCount = 0
    foreach ($app in $appsToClose) {
        try {
            Get-Process -Name $app -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            if ($?) {
                $closedCount++
            }
        } catch {}
    }
    [System.Windows.Forms.MessageBox]::Show("Closed $closedCount background apps.", "Done", "OK", "Information")
    Write-ShadowLog "Closed $closedCount background apps." -Level SUCCESS
}))

$mainForm.Controls.Add((Create-RoundedButton "Minecraft Tools" 600 200 ([System.Drawing.Color]::FromArgb(50, 150, 50)) {
    $mainForm.Hide()
    $minecraftForm.ShowDialog()
}))

$mainForm.Controls.Add((Create-RoundedButton "Exit" 600 360 ([System.Drawing.Color]::FromArgb(150, 50, 50)) {
    $mainForm.Close()
}))

$mainForm.Controls.Add((Create-RoundedButton "Fix Black Screen (Games)" 600 280 ([System.Drawing.Color]::FromArgb(50, 150, 50)) {
    $confirmResult = [System.Windows.Forms.MessageBox]::Show(
        "This will clear DirectX shader cache and restart Windows Explorer. Continue?",
        "Confirm Black Screen Fix",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    
    if ($confirmResult -eq [System.Windows.Forms.DialogResult]::Yes) {
        try {
            $progressForm = New-Object Windows.Forms.Form
            $progressForm.Text = "Applying Fixes"
            $progressForm.Size = New-Object Drawing.Size(300, 150)
            $progressForm.StartPosition = "CenterScreen"
            $progressForm.FormBorderStyle = "FixedDialog"
            $progressForm.ControlBox = $false
            
            $progressLabel = New-Object Windows.Forms.Label
            $progressLabel.Text = "Applying black screen fixes..."
            $progressLabel.Location = New-Object Drawing.Point(20, 20)
            $progressLabel.AutoSize = $true
            $progressForm.Controls.Add($progressLabel)
            
            $progressBar = New-Object Windows.Forms.ProgressBar
            $progressBar.Location = New-Object Drawing.Point(20, 50)
            $progressBar.Size = New-Object Drawing.Size(250, 20)
            $progressBar.Style = "Marquee"
            $progressForm.Controls.Add($progressBar)
            
            $progressForm.Show()
            $progressForm.Refresh()
            
            Write-ShadowLog "Clearing DirectX shader cache..." -Level EXEC
            $progressLabel.Text = "Clearing DirectX shader cache..."
            $progressForm.Refresh()
            Remove-Item "$env:LOCALAPPDATA\D3DSCache\*" -Recurse -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            
            Write-ShadowLog "Restarting Windows Explorer..." -Level EXEC
            $progressLabel.Text = "Restarting Windows Explorer..."
            $progressForm.Refresh()
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            Start-Process explorer
            
            $progressForm.Close()
            
            [System.Windows.Forms.MessageBox]::Show(
                "Black screen fix applied successfully.`nPlease restart your game if the issue persists.",
                "Fix Complete",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Information
            )
            Write-ShadowLog "Black screen fix applied successfully." -Level SUCCESS
        } catch {
            if ($progressForm.Visible) { $progressForm.Close() }
            [System.Windows.Forms.MessageBox]::Show(
                "Failed to apply fix: $($_.Exception.Message)`nEnsure running as administrator.",
                "Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            Write-ShadowLog "Failed to apply black screen fix: $($_.Exception.Message)" -Level ERROR
        }
    }
}))

# Copyright
$copyright = New-Object Windows.Forms.Label
$copyright.Text = "© DKSTR 2025 by SHADOWHacker-GOD"
$copyright.ForeColor = "White"
$copyright.BackColor = [System.Drawing.Color]::Transparent
$copyright.AutoSize = $true
$copyright.Location = New-Object Drawing.Point(380, 520)
$copyright.Font = New-Object Drawing.Font("Arial", 8)
$mainForm.Controls.Add($copyright)

# Discord and GitHub icons with smooth scaling
$discordIcon = Create-IconButton (Join-Path $assetPath "discord.ico") 920 20 {
    Start-Process "https://discord.gg/7XENhJBncg"
}
$mainForm.Controls.Add($discordIcon)

$githubIcon = Create-IconButton (Join-Path $assetPath "github.ico") 860 20 {
    Start-Process "https://github.com/Dk2Sx34"
}
$mainForm.Controls.Add($githubIcon)

# Add the same icons to the Minecraft page
$minecraftForm.Controls.Add((Create-IconButton (Join-Path $assetPath "discord.ico") 920 20 {
    Start-Process "https://discord.gg/7XENhJBncg"
}))

$minecraftForm.Controls.Add((Create-IconButton (Join-Path $assetPath "github.ico") 860 20 {
    Start-Process "https://github.com/Dk2Sx34"
}))

# Run the application
[System.Windows.Forms.Application]::EnableVisualStyles()

# Check PowerShell version for ZipFile support
if ($PSVersionTable.PSVersion.Major -lt 5) {
    [System.Windows.Forms.MessageBox]::Show("This script requires PowerShell 5.1 or higher for .NET ZipFile support. Please upgrade.", "Critical Error", "OK", "Error")
    Write-ShadowLog "This script requires PowerShell 5.1 or higher." -Level CRITICAL
    exit 1
}

$mainForm.ShowDialog()