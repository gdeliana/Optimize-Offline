
Function Update_bcd
{
	param ($usbpartition)
	& bcdedit /store "$usbpartition\boot\bcd" /set '{default}' bootmenupolicy Legacy | Out-Null
	& bcdedit /store "$usbpartition\EFI\Microsoft\boot\bcd" /set '{default}' bootmenupolicy Legacy |Out-Null
	Set-ItemProperty -Path "$usbpartition\boot\bcd" -Name IsReadOnly -Value $true
	Set-ItemProperty -Path "$usbpartition\EFI\Microsoft\boot\bcd" -Name IsReadOnly -Value $true
}
Function Write-USB {

	[CmdletBinding()]

	Param (
		[Parameter(
			Mandatory = $true,
			HelpMessage = 'full path of the iso file to be flashed to the usb device'
		)]
		[String]$ISOPath,
		[Parameter(
			Mandatory = $true,
			HelpMessage = 'USB device drive object'
		)]
		[PSCustomObject]$USBDrive
	)

	Try {
		If ($USBDrive.Count -eq 0 -or $USBDrive.BusType -ne "USB") {
			Throw "Could not find USB drive"
		}
		$ISO = (Get-Item $ISOPath)
		$ISOSize = $ISO.Length
		If (!$ISO -or $ISOSize -eq 0) {
			Throw "Invalid iso file"
		}
		If ($USBDrive.Size -lt $ISOSize + 200MB) {
			Throw "USB disk size is smaller than ISO size"
		}

		Stop-Service ShellHWDetection -erroraction silentlycontinue | Out-Null
	
		[Void]($USBDrive | Clear-Disk -RemoveData -RemoveOEM -Confirm:$false -PassThru)
	
		If ($USBDrive.PartitionStyle -eq 'RAW') {
			[Void]($USBDrive | Initialize-Disk -PartitionStyle GPT)
		} Else {
			[Void]($USBDrive | Set-Disk -PartitionStyle GPT)
		}
	
		$Volumes = (Get-Volume).Where({$_.DriveLetter}).DriveLetter
		[Void](Mount-DiskImage -ImagePath $ISOPath)
		$ISOMount = (Compare-Object -ReferenceObject $Volumes -DifferenceObject (Get-Volume).Where({$_.DriveLetter}).DriveLetter).InputObject

		$USBUEFIVolume = $USBDrive |
		New-Partition -Size 1GB -AssignDriveLetter |
		Format-Volume -FileSystem FAT32 -NewFileSystemLabel "BOOT"

		Copy-Item -Path "$($ISOMount):\bootmgr*" -Destination "$($USBUEFIVolume.DriveLetter):\"
		Copy-Item -Path "$($ISOMount):\boot" -Destination "$($USBUEFIVolume.DriveLetter):\boot" -Recurse
		Copy-Item -Path "$($ISOMount):\efi" -Destination "$($USBUEFIVolume.DriveLetter):\efi" -Recurse
		
		If (!(Test-Path -path "$($USBUEFIVolume.DriveLetter):\sources")) {
			New-Item "$($USBUEFIVolume.DriveLetter):\sources" -Type Directory | Out-Null
		}
		Copy-Item -Path "$($ISOMount):\sources\boot.wim" -Destination "$($USBUEFIVolume.DriveLetter):\sources"

		Update_bcd $($USBUEFIVolume.DriveLetter+":")
		
	
		$USBVolume = $USBDrive |
		New-Partition -UseMaximumSize -AssignDriveLetter |
		Format-Volume -FileSystem NTFS -NewFileSystemLabel "Windows Setup"

		Copy-Item -Path "$($ISOMount):\*" -Destination "$($USBVolume.DriveLetter):" -Recurse -Force -Exclude "boot.wim"

		Update_bcd $($USBVolume.DriveLetter+":")
		
		Get-Volume -Drive $USBUEFIVolume.DriveLetter | Get-Partition | Remove-PartitionAccessPath -accesspath "$($USBUEFIVolume.DriveLetter):\"
	} Catch {
		Throw $Error[0]
	} Finally {
		If ($ISOPath) {
			[Void](Dismount-DiskImage -ImagePath $ISOPath)
		}
		Start-Service ShellHWDetection -erroraction silentlycontinue | Out-Null
	}
}
