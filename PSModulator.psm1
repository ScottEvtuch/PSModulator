# Setup variables

    $ExportParams = @{}

#region Persistent Configuration

    # Setup variables
    $ModuleName = Split-Path $PSScriptRoot -Leaf

    function Get-ModuleConfigRoot
    {
        [CmdletBinding()]
        Param
        (
            [Parameter()]
            [ValidateSet("User", "Computer", "Module")]
            [String]
            $Scope = "User"
        )

        Process
        {
            # Establish configuration folder and file path from Scope
            $ConfigRoot = switch ($Scope)
            {
                'User' {"$env:APPDATA\PSModuleConfig"}
                'Computer' {"$env:ProgramData\PSModuleConfig"}
                'Module' {$PSScriptRoot}
                Default {}
            }

            return $ConfigRoot
        }
    }

    function Set-ModuleConfig
    {
        [CmdletBinding()]
        Param
        (
            [Parameter(Mandatory=$true,
                       Position=0)]
            [System.Collections.Hashtable]
            $ModuleConfig,

            [Parameter()]
            [ValidateSet("User", "Computer", "Module")]
            [String]
            $Scope = "User"
        )

        Process
        {
            # Establish the configuration path
            $ConfigRoot = Get-ModuleConfigRoot -Scope $Scope
            $ConfigPath = "$ConfigRoot\$ModuleName.xml"

            # Write the configuration
            try
            {
                $ModuleConfig | Export-Clixml -Path $ConfigPath
            }
            catch
            {
                throw "Could not write to configuration file: $_"
            }
        }
    }

    function Get-ModuleConfig
    {
        [CmdletBinding()]
        Param
        (
            [Parameter()]
            [ValidateSet("User", "Computer", "Module")]
            [String]
            $Scope = "User"
        )

        Process
        {
            # Establish the configuration path
            $ConfigRoot = Get-ModuleConfigRoot -Scope $Scope
            $ConfigPath = "$ConfigRoot\$ModuleName.xml"

            # Check for a configuration folder
            if (!(Test-Path -Path $ConfigRoot))
            {
                # Configuration folder does not exist, try to create it
                try
                {
                    New-Item -Path $ConfigRoot -ItemType Directory -ErrorAction Stop
                    if ($Scope -eq "Computer")
                    {
                        # Update the ACL to make the files editable by users if it is computer config
                        $ConfigRootAcl = Get-Acl -Path $ConfigRoot -ErrorAction Stop
                        $ConfigRootAclRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Users","Modify","ContainerInherit,ObjectInherit","None","Allow")
                        $ConfigRootAcl.AddAccessRule($ConfigRootAclRule)
                        Set-Acl -Path $ConfigRoot -AclObject $ConfigRootAcl -ErrorAction Stop
                    }
                }
                catch
                {
                    throw "Failed to create configuration directory: $_"
                }
            }
            
            # Check for a configuration file
            if (Test-Path -Path $ConfigPath)
            {
                # We have a configuration file, try to import it
                try
                {
                    $ModuleConfig = Import-Clixml -Path $ConfigPath -ErrorAction Stop
                    return $ModuleConfig
                }
                catch
                {
                    throw "Failed to load configuration file: $_"
                }
            }
            else
            {
                # We don't have a config file, create one from a blank hashtable
                try
                {
                    $ModuleConfig = @{}
                    $ModuleConfig | Export-Clixml -Path $ConfigPath -ErrorAction Stop
                    return $ModuleConfig
                }
                catch
                {
                    throw "Failed to create configuration file: $_"
                }
            }
        }
    }

    function Get-ModuleConfigValue
    {
        [CmdletBinding()]
        Param
        (
            # Name of the configuration item
            [Parameter(Mandatory=$true,
                       Position=0)]
            [String]
            $Name,

            [Parameter()]
            [ValidateSet("User", "Computer", "Module")]
            [String]
            $Scope = "User"
        )

        Process
        {
            $ModuleConfig = Get-ModuleConfig -Scope $Scope

            return $ModuleConfig.$Name
        }
    }

    function Set-ModuleConfigValue
    {
        [CmdletBinding()]
        Param
        (
            # Name of the configuration item
            [Parameter(Mandatory=$true,
                       Position=0)]
            [String]
            $Name,

            # Value of the configuration item
            [Parameter(Mandatory=$true)]
            $Value,

            [Parameter()]
            [ValidateSet("User", "Computer", "Module")]
            [String]
            $Scope = "User"
        )

        Process
        {
            $ModuleConfig = Get-ModuleConfig -Scope $Scope

            if ($ModuleConfig.ContainsKey($Name))
            {
                $ModuleConfig.$Name = $Value
            }
            else
            {
                $ModuleConfig.Add($Name,$Value)
            }

            Set-ModuleConfig $ModuleConfig -Scope $Scope
        }
    }

#endregion

#region Public Functions

    # Name of the folder for public function ps1 files
    $PublicFunctionFolder = "Public"

    # Setup variables
    $PublicFunctionPath = "$PSScriptRoot\$PublicFunctionFolder"
    $PublicFunctions = @()
    $PublicAliases = @()

    # Get all of the public function files we'll be importing
    Write-Verbose "Searching for scripts in $PublicFunctionPath"
    $PublicFunctionFiles = Get-ChildItem -File -Filter *-*.ps1 -Path $PublicFunctionPath -Recurse -ErrorAction Continue
    Write-Debug "Found $($PublicFunctionFiles.Count) function files in $PublicFunctionPath"

    # Iterate through each of the public function files
    foreach ($PublicFunctionFile in $PublicFunctionFiles)
    {
        $PublicFunctionName = $PublicFunctionFile.BaseName
        Write-Verbose "Importing function $PublicFunctionName"
        try
        {
            # Dot source the file and extract the function name and any aliases
            . $PublicFunctionFile.FullName
            $PublicFunctions += $PublicFunctionName
            $PublicFunctionAliases = Get-Alias -Definition $PublicFunctionName -Scope Local -ErrorAction SilentlyContinue
            Write-Debug "Aliases for $PublicFunctionName`: $PublicFunctionAliases"
            $PublicAliases += $PublicFunctionAliases
        }
        catch
        {
            Write-Error "Failed to import $($PublicFunctionFile): $_"
        }
    }

    # Add to the export parameters
    $ExportParams.Add("Function",$PublicFunctions)
    $ExportParams.Add("Alias",$PublicAliases)

#endregion

#region Private Functions

    # Name of the folder for private function ps1 files
    $PrivateFunctionFolder = "Private"

    # Setup variables
    $PrivateFunctionPath = "$PSScriptRoot\$PrivateFunctionFolder"

    # Get all of the private function files we'll be importing
    Write-Verbose "Searching for scripts in $PrivateFunctionPath"
    $PrivateFunctionFiles = Get-ChildItem -File -Filter *-*.ps1 -Path $PrivateFunctionPath -Recurse -ErrorAction Continue
    Write-Debug "Found $($PrivateFunctionFiles.Count) function files in $PrivateFunctionPath"

    # Iterate through each of the private function files
    foreach ($PrivateFunctionFile in $PrivateFunctionFiles)
    {
        $PrivateFunctionName = $PrivateFunctionFile.BaseName
        Write-Verbose "Importing function $PrivateFunctionName"
        try
        {
            # Dot source the file
            . $PrivateFunctionFile.FullName
        }
        catch
        {
            Write-Error "Failed to import $PrivateFunctionFile`: $_"
        }
    }

#endregion

# Export the public items

    Export-ModuleMember @ExportParams