<#	
	.NOTES
	===========================================================================
	 Created with: 	SAPIEN Technologies, Inc., PowerShell Studio 2018 v5.5.152
	 Created on:   	03.05.2019 10:32
	 Created by:   	Dominic Schmutz
	 Organization: 	Unico Data AG
	 Filename:     	Add-UDSCCMComputerNutanix
	===========================================================================
	.DESCRIPTION
		A description of the file.
#>

# Load Classes/Modules
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")
add-type @"
				using System.Net;
			    using System.Security.Cryptography.X509Certificates;
			    public class TrustAllCertsPolicy : ICertificatePolicy {
			        public bool CheckValidationResult(
			            ServicePoint srvPoint, X509Certificate certificate,
			            WebRequest request, int certificateProblem) {
			            return true;
			        }
			    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy

Import-Module (Join-Path $(Split-Path $env:SMS_ADMIN_UI_PATH) ConfigurationManager.psd1)
$SiteCode = "P01"
Set-Location $SiteCode":"
$SMSProvider = (Get-CMSite -SiteCode $SiteCode).ServerName



#Variables / classes
$global:disk_counter = 0
$global:nic_counter = 0
$NTNXClusters = @('b1ntnx-clusvip1', 'b2ntnx-clusvip2','B0NTNX-LAB')
$Errors = ""
$global:sccm_input_filled = $false
$modify_mode = ""
$ip_configs = @{ }

class ip_config {
	[string]$name
	[string]$ipaddresslist
	[string]$subnetmask
	[string]$gateways
	[string]$dnsserverlist
	[string]$dnsdomain
}




#Functions

function create_vm()
{
	if (!$vm_input_form_computer_input.Text)
	{
		[System.Windows.Forms.MessageBox]::Show("Please fill out 'Machine name'", "Error", 0)
	}
	elseif (!$vm_input_form_ram_input.Text)
	{
		[System.Windows.Forms.MessageBox]::Show("Please fill out 'vRam Size'", "Error", 0)
	}
	elseif (!$vm_input_form_cpu_input.Text)
	{
		[System.Windows.Forms.MessageBox]::Show("Please fill out 'Numbers of vCPUs'", "Error", 0)
	}
	elseif (!$vm_input_form_core_input.Text)
	{
		[System.Windows.Forms.MessageBox]::Show("Please fill out 'Cores each vCPU'", "Error", 0)
	}
	elseif (!$vm_input_protection_domain_input.Text)
	{
		[System.Windows.Forms.MessageBox]::Show("Please fill out 'Protection domain'", "Error", 0)
	}
	elseif (!$vm_input_sla_domain_input.Text)
	{
		[System.Windows.Forms.MessageBox]::Show("Please fill out 'SLA domain'", "Error", 0)
	}
	elseif (!$vm_input_sla_domain_input.Text)
	{
		[System.Windows.Forms.MessageBox]::Show("Please fill out 'SLA domain'", "Error", 0)
	}
	elseif (!($vm_input_sccm_location_input.Text -and $vm_input_sccm_os_input.Text -and $vm_input_sccm_role_input.Text -and $vm_input_sccm_maintenance_input.Text))
	{
		[System.Windows.Forms.MessageBox]::Show("Please fill out all SCCM fields", "Error", 0)
	}
	elseif ($nic_table.Items.Count -eq 0)
	{
		[System.Windows.Forms.MessageBox]::Show("Please add at least 1 NIC", "Error", 0)
	}
	else
	{
		
		$vm_input_form.Enabled = $false
		
		$method = "GET"
		$uri = "https://$($cluster_selection_form_combobox.SelectedItem):9440/api/nutanix/v2.0/vms/?filter=vm_name%3D%3D$($vm_input_form_computer_input.Text)"
		$response = Invoke-WebRequest -ContentType "application/json" -Headers $headers -Method $method -Uri $uri
		if ((ConvertFrom-Json -InputObject $response).Entities)
		{
			[System.Windows.Forms.MessageBox]::Show("VM with that name already exists.", "Error", 0)
		}
		else
		{
			
			$global:progress_form = New-Object System.Windows.Forms.Form
			$global:progress_form.Size = New-Object System.Drawing.Size(170, 100)
			$global:progress_form.AutoSize = $true
			$global:progress_form.StartPosition = "CenterScreen"
			$global:progress_form.ControlBox = $false
			$global:progress_form.FormBorderStyle = 'FixedSingle'
			$global:progress_form.BringToFront()
			#$global:progress_form.TopMost = $true
			
			$progress_label = New-Object System.Windows.Forms.Label
			$progress_label.Size = New-Object System.Drawing.Size(150, 25)
			$progress_label.AutoSize = $true
			$progress_label.Location = New-Object System.Drawing.Size(10, 20)
			
			$progress_ok_button = New-Object System.Windows.Forms.Button
			$progress_ok_button.Location = New-Object System.Drawing.Size(60, 65)
			$progress_ok_button.Size = New-Object System.Drawing.Size(50, 23)
			$progress_ok_button.Text = "OK"
			$progress_ok_button.Visible = $false
			$progress_ok_button.Enabled = $false
			$progress_ok_button.Add_Click({
					$global:progress_form.Close()
					$cluster_selection_form.Visible = $true
					$cluster_selection_form.BringToFront()
				})
			
			$global:progress_form.Controls.Add($progress_ok_button)
			$global:progress_form.Controls.Add($progress_label)
			
			$global:progress_form.Show()
			
			
			$progress_label.Text = "Creating VM..."
			
			
			# Create VM
			$body = @{
				'name'	   = $vm_input_form_computer_input.Text
				'description' = $vm_input_form_description_input.Text
				'memory_mb' = $vm_input_form_ram_input.Text
				'num_vcpus' = $vm_input_form_cpu_input.Text
				'num_cores_per_vcpu' = $vm_input_form_core_input.Text
				'timezone' = "Europe/Zurich"
			}
			
			$body = $body | ConvertTo-Json
			$method = "POST"
			$uri = "https://$($cluster_selection_form_combobox.SelectedItem):9440/api/nutanix/v2.0/vms/"
			
			$response = Invoke-WebRequest -ContentType "application/json" -Headers $headers -Body $body -Method $method -Uri $uri
			$response = @{ "StatusCode" = 201 }
			if ($response.StatusCode -eq 201)
			{
				$method = "GET"
				$uri = "https://$($cluster_selection_form_combobox.SelectedItem):9440/api/nutanix/v2.0/vms/?filter=vm_name%3D%3D$($vm_input_form_computer_input.Text)"
				$response = Invoke-WebRequest -ContentType "application/json" -Headers $headers -Method $method -Uri $uri
				
				if (($vm_uuid = (ConvertFrom-Json -InputObject $response).Entities.uuid).Count -eq 1)
				{
					try
					{
						$progress_label.Text = "Adding CD-ROM..."
						#AD CD-ROM
						$body = "
						{
							`"uuid`": `"$($vm_uuid)`",
							`"vm_disks`": [
								{
								`"is_cdrom`": true,
								`"is_empty`": true
								}
							]
						}
						"
						$uri = "https://$($cluster_selection_form_combobox.SelectedItem):9440/api/nutanix/v2.0/vms/$($vm_uuid)/disks/attach"
						$method = "POST"
						
						$response = Invoke-WebRequest -ContentType "application/json" -Headers $headers -Body $body -Method $method -Uri $uri
					}
					catch
					{
						$Errors += "Error while creating CD-ROM;"
					}
					
					#Add disks
					$progress_label.Text = "Creating Disks..."
					try
					{
						foreach ($line in $disk_table.Items)
						{
							$body = "
						{
							`"uuid`": `"$($vm_uuid)`",
							`"vm_disks`": [
								{
								`"is_cdrom`": false,
								`"vm_disk_create`": {
									`"size`": $([int]$line.SubItems.Text[0] * [math]::pow(1024, 3)),
									`"storage_container_uuid`": `"$(($storage_containers | where { $_.name -eq $line.SubItems.Text[1] }).storage_container_uuid)`"
									}
								}
							]
						}
						"
							$uri = "https://$($cluster_selection_form_combobox.SelectedItem):9440/api/nutanix/v2.0/vms/$($vm_uuid)/disks/attach"
							$method = "POST"
							
							$response = Invoke-WebRequest -ContentType "application/json" -Headers $headers -Body $body -Method $method -Uri $uri
							
						}
					}
					catch
					{
						$Errors += "Error while creating disks;"
					}
					
					#Add NICs
					$progress_label.Text = "Creating NIC's..."
					
					try
					{
						foreach ($line in $nic_table.Items)
						{
							switch ($line.SubItems.Text[1])
							{
								"Connected"{ $con_status = "true" }
								"Disconnected"{ $con_status = "false" }
								default { $con_status = "true" }
							}
							$body = "
							{
								`"spec_list`": [
									{
										`"is_connected`": $($con_status),
										`"network_uuid`": `"$(($vnetworks | where { $_.Name -eq $line.SubItems.Text[0] }).uuid)`"
									}
								],
								`"uuid`": `"$($vm_uuid)`"
							}
							"
							$uri = "https://$($cluster_selection_form_combobox.SelectedItem):9440/api/nutanix/v2.0/vms/$($vm_uuid)/nics/"
							$method = "POST"
							
							$response = Invoke-WebRequest -ContentType "application/json" -Headers $headers -Body $body -Method $method -Uri $uri
														
							if ($line -eq $nic_table.Items[0])
							{
								$uri = "https://$($cluster_selection_form_combobox.SelectedItem):9440/api/nutanix/v2.0/vms/$($vm_uuid)/nics/"
								$method = "GET"
								
								$response = Invoke-WebRequest -ContentType "application/json" -Headers $headers -Method $method -Uri $uri
								$mac_address = (ConvertFrom-Json -InputObject $response).Entities.mac_address
							}
						}
					}
					catch
					{
						$Errors += "Error while creating NIC's;"
					}
					
					#Add to Protection Domain
					$progress_label.Text = "Adding VM to Protection domain..."
					
					try
					{
						$body = "{
						`"ids`": [
							`"$($vm_uuid)`"
						],
						`"ignore_dup_or_missing_vms`": true,
						`"uuids`": [
							`"$($vm_uuid)`"
						]
						}"
						
						$uri = "https://$($cluster_selection_form_combobox.SelectedItem):9440/PrismGateway/services/rest/v2.0/protection_domains/$($vm_input_protection_domain_input.Text -replace (' \(\d*\)', ''))/protect_vms"
						$method = "POST"
						
						$response = Invoke-WebRequest -ContentType "application/json" -Headers $headers -Body $body -Method $method -Uri $uri
					}
					catch
					{
						$Errors += "Error while adding to Protection domain;"
					}
					
					#Add to SLA Domain
					$progress_label.Text = "Adding VM to SLA domain..."
					
					try
					{
						
						$uri = "https://nutanix-prismcental:9440/api/nutanix/v3/vms/$($vm_uuid)"
						$method = "GET"
						$response = Invoke-WebRequest -ContentType "application/json" -Headers $headers -Method $method -Uri $uri -ErrorAction Stop
						$central_vm = (ConvertFrom-Json -InputObject $response)
						
						$uri = "https://nutanix-prismcental:9440/api/nutanix/v3/categories/RubrikSLADomains/list"
						$method = "POST"
						$response = Invoke-WebRequest -ContentType "application/json" -Headers $headers -Body "{}" -Method $method -Uri $uri -ErrorAction Stop
						$central_sla_domains = (ConvertFrom-Json -InputObject $response).Entities
						
						if ($central_sla_domains.value -notcontains $vm_input_sla_domain_input.Text)
						{
							$uri = "https://nutanix-prismcental:9440/api/nutanix/v3/categories/RubrikSLADomains/$($vm_input_sla_domain_input.Text)"
							$method = "PUT"
							$body = @{ "value" = $vm_input_sla_domain_input.Text }
							$body = $body | ConvertTo-Json -Depth 100
							
							$response = Invoke-WebRequest -ContentType "application/json" -Headers $headers -Body $body -Method $method -Uri $uri -ErrorAction Stop
						}
						
						$central_vm.PSObject.Properties.Remove("status")
						$central_vm.metadata.categories | Add-Member -MemberType NoteProperty -Name "RubrikSLADomains" -Value $vm_input_sla_domain_input.Text -PassThru
						$central_vm.metadata.categories | Add-Member -MemberType NoteProperty -Name "AppTier" -Value "Default" -PassThru
						$body = $central_vm | ConvertTo-Json -Depth 100
						
						$uri = "https://nutanix-prismcental:9440/api/nutanix/v3/vms/$($vm_uuid)"
						$method = "PUT"
						
						$response = Invoke-WebRequest -ContentType "application/json" -Headers $headers -Body $body -Method $method -Uri $uri -ErrorAction Stop
						<#
						$method = "GET"
						$uri = "https://rubrik/api/internal/nutanix/cluster"
						$response = Invoke-WebRequest -ContentType "application/json" -Headers $rubrik_headers -Method $method -Uri $uri
						$nutanix_cluster_id = ((ConvertFrom-Json -InputObject $response).data | where{ $_.name -eq $cluster_selection_form_combobox.SelectedItem }).id
						
						$method = "POST"
						$uri = "https://rubrik/api/internal/nutanix/cluster/$($nutanix_cluster_id)/refresh"
						$response = Invoke-WebRequest -ContentType "application/json" -Headers $rubrik_headers -Method $method -Uri $uri
						
						$loop_count = 0
						while ($true)
						{
							$method = "GET"
							$uri = "https://rubrik/api/internal/nutanix/vm"
							$response = Invoke-WebRequest -ContentType "application/json" -Headers $rubrik_headers -Method $method -Uri $uri
							if ($vm_rubrik_id = ((ConvertFrom-Json -InputObject $response).data | where { $_.id -like "*$($vm_uuid)" }).id)
							{
								break
							}
							Start-Sleep -Seconds 5
							$loop_count++
							if ($loop_count -gt 20)
							{
								$Errors += "Waiting loop count exceeded;"
								Throw "Waiting loop count exceeded."
							}
						}
						
						$method = "POST"
						$uri = "https://rubrik/api/internal/sla_domain/$(($sla_domains | where { $_.Name -eq $vm_input_sla_domain_input.Text }).id)/assign"
						$body = "{
						`"managedIds`":[
						`"$($vm_rubrik_id)`"
						]
						}"
						$response = Invoke-WebRequest -ContentType "application/json" -Headers $rubrik_headers -Body $body -Method $method -Uri $uri
						#>
					}
					catch
					{
						Write-Host $_.Exception.Message
						$Errors += "Error while adding to SLA domain;"
					}
					
					# SCCM
					$progress_label.Text = "Adding VM to SCCM..."
					
					try
					{
						Import-CMComputerInformation -CollectionName "All Systems" -ComputerName "$($vm_input_form_computer_input.Text)" -MacAddress "$mac_address"
						
						$progress_label.Text = "Adding VM to SCCM-Collections..."
						$CollectionsLOCToUse = $CollectionsLOC | Where { $_.Name -eq $vm_input_sccm_location_input.Text }
						$CollectionsOSDToUse = $CollectionsOSD | Where { $_.Name -eq $vm_input_sccm_os_input.Text }
						$CollectionsROLToUse = $CollectionsROL | Where { $_.Name -eq $vm_input_sccm_role_input.Text }
						$CollectionsMAWToUse = $CollectionsMAW | Where { $_.Name -eq $vm_input_sccm_maintenance_input.Text }
						
						do
						{
							Start-Sleep -Seconds 5
							$ObjNewComputer = Get-CMDevice -Name "$($vm_input_form_computer_input.Text)"
						}
						while ([string]::IsNullOrEmpty($ObjNewComputer.ResourceID))
						
						If ($CollectionsLOCToUse)
						{
							#Add-CMDeviceCollectionDirectMembershipRule -CollectionId $CollectionsLOCToUse.CollectionID -ResourceId $ObjNewComputer.ResourceID
							Invoke-CMDeviceCollectionUpdate -CollectionId $CollectionsLOCToUse.CollectionID
						}
						
						If ($CollectionsOSDToUse)
						{
							Add-CMDeviceCollectionDirectMembershipRule -CollectionId $CollectionsOSDToUse.CollectionID -ResourceId $ObjNewComputer.ResourceID
							Invoke-CMDeviceCollectionUpdate -CollectionId $CollectionsOSDToUse.CollectionID
						}
						
						If ($CollectionsROLToUse)
						{
							Add-CMDeviceCollectionDirectMembershipRule -CollectionId $CollectionsROLToUse.CollectionID -ResourceId $ObjNewComputer.ResourceID
							Invoke-CMDeviceCollectionUpdate -CollectionId $CollectionsROLToUse.CollectionID
						}
						
						If ($CollectionsMAWToUse)
						{
							Add-CMDeviceCollectionDirectMembershipRule -CollectionId $CollectionsMAWToUse.CollectionID -ResourceId $ObjNewComputer.ResourceID
							Invoke-CMDeviceCollectionUpdate -CollectionId $CollectionsMAWToUse.CollectionID
						}
						
						#Ip Config
						
						$progress_label.Text = "Adding SCCM IP Config..."
						
						$uri = "https://$($cluster_selection_form_combobox.SelectedItem):9440/api/nutanix/v2.0/vms/$($vm_uuid)/nics/"
						$method = "GET"
						$response = Invoke-WebRequest -ContentType "application/json" -Headers $headers -Method $method -Uri $uri
						
						$vm_nics = (ConvertFrom-Json -InputObject $response).Entities
						
						$config_position = 0
						$config_counter = 0
						foreach ($line in $nic_table.Items)
						{
							$ip_config =  $ip_configs.($line.SubItems[2].Text)
							if ($ip_config)
							{
								New-CMDeviceVariable -DeviceName $vm_input_form_computer_input.Text -IsMask $false -VariableName ('UD_Adapter' + $config_counter + 'Index') -VariableValue $config_counter
								New-CMDeviceVariable -DeviceName $vm_input_form_computer_input.Text -IsMask $false -VariableName ('UD_Adapter' + $config_counter + 'Name') -VariableValue $ip_config.name
								New-CMDeviceVariable -DeviceName $vm_input_form_computer_input.Text -IsMask $false -VariableName ('UD_Adapter' + $config_counter + 'MacAddress') -VariableValue $vm_nics[$config_position].mac_address
								New-CMDeviceVariable -DeviceName $vm_input_form_computer_input.Text -IsMask $false -VariableName ('UD_Adapter' + $config_counter + 'EnableDHCP') -VariableValue 'FALSE'
								New-CMDeviceVariable -DeviceName $vm_input_form_computer_input.Text -IsMask $false -VariableName ('UD_Adapter' + $config_counter + 'IPAddressList') -VariableValue $ip_config.ipaddresslist
								New-CMDeviceVariable -DeviceName $vm_input_form_computer_input.Text -IsMask $false -VariableName ('UD_Adapter' + $config_counter + 'SubnetMask') -VariableValue $ip_config.subnetmask
								New-CMDeviceVariable -DeviceName $vm_input_form_computer_input.Text -IsMask $false -VariableName ('UD_Adapter' + $config_counter + 'Gateways') -VariableValue $ip_config.gateways
								New-CMDeviceVariable -DeviceName $vm_input_form_computer_input.Text -IsMask $false -VariableName ('UD_Adapter' + $config_counter + 'DNSServerList') -VariableValue $ip_config.dnsserverlist
								New-CMDeviceVariable -DeviceName $vm_input_form_computer_input.Text -IsMask $false -VariableName ('UD_Adapter' + $config_counter + 'DNSDomain') -VariableValue $ip_config.dnsdomain
								New-CMDeviceVariable -DeviceName $vm_input_form_computer_input.Text -IsMask $false -VariableName ('UD_Adapter' + $config_counter + 'EnableDNSRegistration') -VariableValue 'TRUE'
								New-CMDeviceVariable -DeviceName $vm_input_form_computer_input.Text -IsMask $false -VariableName ('UD_Adapter' + $config_counter + 'EnableFullDNSRegistration') -VariableValue 'TRUE'
								New-CMDeviceVariable -DeviceName $vm_input_form_computer_input.Text -IsMask $false -VariableName ('UD_Adapter' + $config_counter + 'GatewayCostMetric') -VariableValue 'automatic'
								$config_counter++
							}
							$config_position++
						}
						if ($config_counter -gt 0)
						{
							New-CMDeviceVariable -DeviceName $vm_input_form_computer_input.Text -IsMask $false -VariableName 'UD_AdapterCount' -VariableValue $config_counter
						}
					}
					catch
					{
						$Errors += "Error while adding to SCCM;"
					}
					
				}
				else
				{
					[System.Windows.Forms.MessageBox]::Show("Check if there is an existing VM with the same name", "Error", 0)
				}
			}
			else
			{
				$Errors += "Error while creating VM;"
			}
			
			if ($vm_input_form_start_vm_input.Checked -eq $true)
			{
				$progress_label.Text = "Starting VM..."
				$body = @{
					"transition" = "ON"
					"uuid"	     = "$vm_uuid"
				}
				$body = $body | ConvertTo-Json
				$method = "POST"
				$uri = "https://$($cluster_selection_form_combobox.SelectedItem):9440/api/nutanix/v2.0/vms/$($vm_uuid)/set_power_state"
				Start-Sleep -s 60
				$response = Invoke-WebRequest -ContentType "application/json" -Headers $headers -Body $body -Method $method -Uri $uri
			}
			
			
			if ($Errors)
			{
				$progress_label.Text = $Errors
			}
			else
			{
				$progress_label.Text = "VM Created successfully"
			}
			
			$progress_ok_button.Visible = $true
			$progress_ok_button.Enabled = $true
		}
	}
}

function relocate_objects()
{
	$nic_table.Height = ($nic_table.Items.Count * 17) + 30
	$disk_table.Height = ($disk_table.Items.Count * 17) + 30
	$nic_groupbox.Location = New-Object System.Drawing.Size(5, ($disk_groupbox.Location.Y + $disk_groupbox.Height + 10))
	$vm_input_form_create_button.Location = New-Object System.Drawing.Size(165, ($vm_input_form_start_vm_input.Location.Y + $vm_input_form_start_vm_input.Height + 10))
}


# Input form to create VM -----------------------------------------

function show_input_form()
{
	
		#SCCM
		$server = "g0rsrw-sccmps01.source.local\SCCM01"
	$db = "CM_P01"
	
	$SQLQuery = "Select col.Name, col.CollectionID, Count(dep.DependentCollectionID) as dependencies_count from v_Collection as col
left join vSMS_CollectionDependencies as dep
on col.CollectionID = dep.DependentCollectionID
group by col.Name, col.CollectionID"
			
	$Datatable = New-Object System.Data.DataTable
	
	$Connection = New-Object System.Data.SQLClient.SQLConnection
	$Connection.ConnectionString = "server='$Server';database='$db';trusted_connection=true;"
	$Connection.Open()
	$Command = New-Object System.Data.SQLClient.SQLCommand
	$Command.Connection = $Connection
	$Command.CommandText = $SQLQuery
	$Reader = $Command.ExecuteReader()
	$Datatable.Load($Reader)
	$Connection.Close()
	
	$Collections = $Datatable
	
	$CollectionsLOC = $Collections | Sort-Object -Property Name | Where-Object { $_.Name -match "LOC - *" }
	$CollectionsOSD = $Collections | Sort-Object -Property Name | Where-Object { ($_.Name -match "OSD - *") -and ($_.dependencies_count -lt 2) }
	$CollectionsROL = $Collections | Sort-Object -Property Name | Where-Object { ($_.Name -match "ROL - *") -and ($_.dependencies_count -lt 2) }
	$CollectionsMAW = $Collections | Sort-Object -Property Name | Where-Object { ($_.Name -match "MAW - *") -and ($_.dependencies_count -lt 2) }
	
	
	
	
	#Get Credentials
	$creds = Get-Credential -UserName "$($env:username)@mgmt.local" -Message "Enter credentails for Nutanix Cluster:`r`n$($cluster_selection_form_combobox.Text)`r`n`r`nUsername Format:`r`nabcd_support@mgmt.local"
		
	$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $creds.UserName.ToString(), ([Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($creds.Password))))))
	$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
	$headers.Add('Authorization', ('Basic {0}' -f $base64AuthInfo))
	
	$rubrik_headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
	$rubrik_headers.Add('Authorization', ('Bearer {0}' -f 'putyourtokenhere'))
	
	
	$method = "GET"
	
	try
	{
		# Get Data to populate Input Form
		
		
		$loading_form = New-Object System.Windows.Forms.Form
		$loading_form.Size = New-Object System.Drawing.Size(170, 100)
		$loading_form.AutoSize = $true
		$loading_form.StartPosition = "CenterScreen"
		$loading_form.ControlBox = $false
		$loading_form.FormBorderStyle = 'FixedSingle'
		$loading_form.BringToFront()
		$loading_form.TopMost = $true
		
		$loading_label = New-Object System.Windows.Forms.Label
		$loading_label.Size = New-Object System.Drawing.Size(150, 25)
		$loading_label.AutoSize = $true
		$loading_label.Location = New-Object System.Drawing.Size(10, 20)
		
		$loading_form.Controls.Add($loading_label)
		$loading_form.Show()
		
		# Nutanix/Rubrik Data
		
		$loading_label.Text = "Loading Nutanix/Rubrik data..."
		
		$uri = "https://$($cluster_selection_form_combobox.SelectedItem):9440/PrismGateway/services/rest/v2.0/storage_containers/"
		$response = Invoke-WebRequest -ContentType "application/json" -Headers $headers -Method $method -Uri $uri -ErrorAction Stop
		$storage_containers = (ConvertFrom-Json -InputObject $response).Entities
		
		$uri = "https://$($cluster_selection_form_combobox.SelectedItem):9440/PrismGateway/services/rest/v2.0/networks/"
		$response = Invoke-WebRequest -ContentType "application/json" -Headers $headers -Method $method -Uri $uri -ErrorAction Stop
		$vnetworks = (ConvertFrom-Json -InputObject $response).Entities
		
		$uri = "https://$($cluster_selection_form_combobox.SelectedItem):9440/PrismGateway/services/rest/v2.0/protection_domains/"
		$response = Invoke-WebRequest -ContentType "application/json" -Headers $headers -Method $method -Uri $uri -ErrorAction Stop
		$protection_domains = (ConvertFrom-Json -InputObject $response).Entities
		
		$uri = "https://rubrik/api/v1/sla_domain"
		$response = Invoke-WebRequest -ContentType "application/json" -Headers $rubrik_headers -Method $method -Uri $uri -ErrorAction Stop
		$sla_domains = (ConvertFrom-Json -InputObject $response).data
	}
	catch
	{
		[System.Windows.Forms.MessageBox]::Show("Failed to collect Nutanix data", "Error", 0)
		exit
	}
	
	
	$loading_form.Close()
	
	
	
	$vm_input_form = New-Object System.Windows.Forms.Form
	$vm_input_form.Text = "Create VM"
	#$vm_input_form.Size = New-Object System.Drawing.Size(400, 450)
	$vm_input_form.AutoSize = $true
	$vm_input_form.AutoSizeMode = 'GrowAndShrink'
	$vm_input_form.StartPosition = "CenterScreen"
	$vm_input_form.MinimizeBox = $false
	$vm_input_form.MaximizeBox = $false
	$vm_input_form.FormBorderStyle = 'FixedSingle'
	$vm_input_form.TopMost = $true
	$vm_input_form.Icon = $Icon
	$vm_input_form.KeyPreview = $True
	$vm_input_form.Add_KeyDown({
		switch ($_.KeyCode)
		{
			"Enter" {
			}
			"Escape" {
				$vm_input_form.Close()
			}
		}
	})
	
	#Computer groupbox
	$computer_groupbox = New-Object System.Windows.Forms.GroupBox
	$computer_groupbox.Location = New-Object System.Drawing.Size(5, 5)
	#$computer_groupbox.size = New-Object System.Drawing.Size(375, 150)
	$computer_groupbox.AutoSize = $true
	$computer_groupbox.text = "Computer"
	$vm_input_form.Controls.Add($computer_groupbox)
	
	$vm_input_form_computer_label = New-Object System.Windows.Forms.Label
	$vm_input_form_computer_label.Location = New-Object System.Drawing.Size(10, 20)
	$vm_input_form_computer_label.Size = New-Object System.Drawing.Size(150, 20)
	$vm_input_form_computer_label.Text = "Machine name:"
	$computer_groupbox.Controls.Add($vm_input_form_computer_label)
	
	$vm_input_form_computer_input = New-Object System.Windows.Forms.TextBox
	$vm_input_form_computer_input.Location = New-Object System.Drawing.Size(215, 20)
	$vm_input_form_computer_input.Size = New-Object System.Drawing.Size(150, 20)
	$computer_groupbox.Controls.Add($vm_input_form_computer_input)
	
	$vm_input_form_description_label = New-Object System.Windows.Forms.Label
	$vm_input_form_description_label.Location = New-Object System.Drawing.Size(10, 45)
	$vm_input_form_description_label.Size = New-Object System.Drawing.Size(150, 20)
	$vm_input_form_description_label.Text = "Description:"
	$computer_groupbox.Controls.Add($vm_input_form_description_label)
	
	$vm_input_form_description_input = New-Object System.Windows.Forms.TextBox
	$vm_input_form_description_input.Location = New-Object System.Drawing.Size(215, 45)
	$vm_input_form_description_input.Size = New-Object System.Drawing.Size(150, 20)
	$computer_groupbox.Controls.Add($vm_input_form_description_input)
	
	$vm_input_form_ram_label = New-Object System.Windows.Forms.Label
	$vm_input_form_ram_label.Location = New-Object System.Drawing.Size(10, 70)
	$vm_input_form_ram_label.Size = New-Object System.Drawing.Size(150, 20)
	$vm_input_form_ram_label.Text = "vRam Size (MB):"
	$computer_groupbox.Controls.Add($vm_input_form_ram_label)
	
	$vm_input_form_ram_input = New-Object System.Windows.Forms.TextBox
	$vm_input_form_ram_input.Location = New-Object System.Drawing.Size(215, 70)
	$vm_input_form_ram_input.Size = New-Object System.Drawing.Size(150, 20)
	$vm_input_form_ram_input.Text = "4096"
	$computer_groupbox.Controls.Add($vm_input_form_ram_input)
	
	$vm_input_form_cpu_label = New-Object System.Windows.Forms.Label
	$vm_input_form_cpu_label.Location = New-Object System.Drawing.Size(10, 95)
	$vm_input_form_cpu_label.Size = New-Object System.Drawing.Size(150, 20)
	$vm_input_form_cpu_label.Text = "Numbers of vCPUs:"
	$computer_groupbox.Controls.Add($vm_input_form_cpu_label)
	
	$vm_input_form_cpu_input = New-Object System.Windows.Forms.TextBox
	$vm_input_form_cpu_input.Location = New-Object System.Drawing.Size(215, 95)
	$vm_input_form_cpu_input.Size = New-Object System.Drawing.Size(150, 20)
	$vm_input_form_cpu_input.Text = "2"
	$computer_groupbox.Controls.Add($vm_input_form_cpu_input)
	
	$vm_input_form_core_label = New-Object System.Windows.Forms.Label
	$vm_input_form_core_label.Location = New-Object System.Drawing.Size(10, 120)
	$vm_input_form_core_label.Size = New-Object System.Drawing.Size(150, 20)
	$vm_input_form_core_label.Text = "Cores each vCPU:"
	$computer_groupbox.Controls.Add($vm_input_form_core_label)
	
	$vm_input_form_core_input = New-Object System.Windows.Forms.TextBox
	$vm_input_form_core_input.Location = New-Object System.Drawing.Size(215, 120)
	$vm_input_form_core_input.Size = New-Object System.Drawing.Size(150, 20)
	$vm_input_form_core_input.Text = "1"
	$computer_groupbox.Controls.Add($vm_input_form_core_input)
	
	$vm_input_protection_domain_label = New-Object System.Windows.Forms.Label
	$vm_input_protection_domain_label.Location = New-Object System.Drawing.Size(10, 145)
	$vm_input_protection_domain_label.Size = New-Object System.Drawing.Size(150, 20)
	$vm_input_protection_domain_label.Text = "Protection domain:"
	$computer_groupbox.Controls.Add($vm_input_protection_domain_label)
	
	$vm_input_protection_domain_input = New-Object System.Windows.Forms.ComboBox
	$vm_input_protection_domain_input.Sorted = $true
	$vm_input_protection_domain_input.DropDownWidth = 300
	$vm_input_protection_domain_input.DropDownStyle = 'DropDownList'
	$vm_input_protection_domain_input.Location = New-Object System.Drawing.Size(165, 145)
	$vm_input_protection_domain_input.Size = New-Object System.Drawing.Size(200, 20)
	foreach ($protection_domain in $protection_domains)
	{
		$vm_input_protection_domain_input.Items.Add("$($protection_domain.name) ($($protection_domain.vms.count))")
	}
	$computer_groupbox.Controls.Add($vm_input_protection_domain_input)
	
	$vm_input_sla_domain_label = New-Object System.Windows.Forms.Label
	$vm_input_sla_domain_label.Location = New-Object System.Drawing.Size(10, 170)
	$vm_input_sla_domain_label.Size = New-Object System.Drawing.Size(150, 20)
	$vm_input_sla_domain_label.Text = "SLA domain:"
	$computer_groupbox.Controls.Add($vm_input_sla_domain_label)
	
	$vm_input_sla_domain_input = New-Object System.Windows.Forms.ComboBox
	$vm_input_sla_domain_input.Sorted = $true
	$vm_input_sla_domain_input.DropDownWidth = 300
	$vm_input_sla_domain_input.DropDownStyle = 'DropDownList'
	$vm_input_sla_domain_input.Location = New-Object System.Drawing.Size(165, 170)
	$vm_input_sla_domain_input.Size = New-Object System.Drawing.Size(200, 20)
	foreach ($sla_domain in $sla_domains)
	{
		if ($sla_domain.name -ne "SLA_Unassigned")
		{
			$vm_input_sla_domain_input.Items.Add($sla_domain.name)
		}
	}
	$computer_groupbox.Controls.Add($vm_input_sla_domain_input)
	
	$vm_input_sccm_location_label = New-Object System.Windows.Forms.Label
	$vm_input_sccm_location_label.Location = New-Object System.Drawing.Size(10, 195)
	$vm_input_sccm_location_label.Size = New-Object System.Drawing.Size(150, 20)
	$vm_input_sccm_location_label.Text = "SCCM location:"
	$computer_groupbox.Controls.Add($vm_input_sccm_location_label)
	
	$vm_input_sccm_location_input = New-Object System.Windows.Forms.ComboBox
	$vm_input_sccm_location_input.Sorted = $true
	$vm_input_sccm_location_input.DropDownWidth = 300
	$vm_input_sccm_location_input.DropDownStyle = 'DropDownList'
	$vm_input_sccm_location_input.Location = New-Object System.Drawing.Size(165, 195)
	$vm_input_sccm_location_input.Size = New-Object System.Drawing.Size(200, 20)
	foreach ($CollectionLOC in $CollectionsLOC)
	{
		$vm_input_sccm_location_input.Items.Add($CollectionLOC.Name)
	}
	
	$computer_groupbox.Controls.Add($vm_input_sccm_location_input)
	
	$vm_input_sccm_os_label = New-Object System.Windows.Forms.Label
	$vm_input_sccm_os_label.Location = New-Object System.Drawing.Size(10, 220)
	$vm_input_sccm_os_label.Size = New-Object System.Drawing.Size(150, 20)
	$vm_input_sccm_os_label.Text = "SCCM Operating System:"
	$computer_groupbox.Controls.Add($vm_input_sccm_os_label)
	
	$vm_input_sccm_os_input = New-Object System.Windows.Forms.ComboBox
	$vm_input_sccm_os_input.Sorted = $true
	$vm_input_sccm_os_input.DropDownWidth = 300
	$vm_input_sccm_os_input.DropDownStyle = 'DropDownList'
	$vm_input_sccm_os_input.Location = New-Object System.Drawing.Size(165, 220)
	$vm_input_sccm_os_input.Size = New-Object System.Drawing.Size(200, 20)
	foreach ($CollectionOSD in $CollectionsOSD)
	{
		$vm_input_sccm_os_input.Items.Add($CollectionOSD.Name)
	}
	
	$computer_groupbox.Controls.Add($vm_input_sccm_os_input)
	
	$vm_input_sccm_role_label = New-Object System.Windows.Forms.Label
	$vm_input_sccm_role_label.Location = New-Object System.Drawing.Size(10, 245)
	$vm_input_sccm_role_label.Size = New-Object System.Drawing.Size(150, 20)
	$vm_input_sccm_role_label.Text = "SCCM Role:"
	$computer_groupbox.Controls.Add($vm_input_sccm_role_label)
	
	$vm_input_sccm_role_input = New-Object System.Windows.Forms.ComboBox
	$vm_input_sccm_role_input.Sorted = $true
	$vm_input_sccm_role_input.DropDownWidth = 300
	$vm_input_sccm_role_input.DropDownStyle = 'DropDownList'
	$vm_input_sccm_role_input.Location = New-Object System.Drawing.Size(165, 245)
	$vm_input_sccm_role_input.Size = New-Object System.Drawing.Size(200, 20)
	foreach ($CollectionROL in $CollectionsROL)
	{
		$vm_input_sccm_role_input.Items.Add($CollectionROL.Name)
	}
	
	$computer_groupbox.Controls.Add($vm_input_sccm_role_input)
	
	$vm_input_sccm_maintenance_label = New-Object System.Windows.Forms.Label
	$vm_input_sccm_maintenance_label.Location = New-Object System.Drawing.Size(10, 270)
	$vm_input_sccm_maintenance_label.Size = New-Object System.Drawing.Size(150, 20)
	$vm_input_sccm_maintenance_label.Text = "SCCM Maintenance window:"
	$computer_groupbox.Controls.Add($vm_input_sccm_maintenance_label)
	
	$vm_input_sccm_maintenance_input = New-Object System.Windows.Forms.ComboBox
	$vm_input_sccm_maintenance_input.Sorted = $true
	$vm_input_sccm_maintenance_input.DropDownWidth = 300
	$vm_input_sccm_maintenance_input.DropDownStyle = 'DropDownList'
	$vm_input_sccm_maintenance_input.Location = New-Object System.Drawing.Size(165, 270)
	$vm_input_sccm_maintenance_input.Size = New-Object System.Drawing.Size(200, 20)
	foreach ($CollectionMAW in $CollectionsMAW)
	{
		$vm_input_sccm_maintenance_input.Items.Add($CollectionMAW.Name)
	}
	
	$computer_groupbox.Controls.Add($vm_input_sccm_maintenance_input)
	
	#------------------------------------------------------------------
	
	
	# DISK groupbox
	$disk_groupbox = New-Object System.Windows.Forms.GroupBox
	$disk_groupbox.Location = New-Object System.Drawing.Size(5, ($computer_groupbox.Location.Y + $computer_groupbox.Height + 10))
	$disk_groupbox.AutoSize = $true
	$disk_groupbox.AutoSizeMode = 'GrowAndShrink'
	$disk_groupbox.Text = "Disks"
	$vm_input_form.Controls.Add($disk_groupbox)
	
	# Add disk form
	$add_disk_form = New-Object System.Windows.Forms.Form
	$add_disk_form.Text = "Disks"
	$add_disk_form.Size = New-Object System.Drawing.Size(350, 150)
	$add_disk_form.StartPosition = "CenterScreen"
	$add_disk_form.MinimizeBox = $false
	$add_disk_form.MaximizeBox = $false
	$add_disk_form.FormBorderStyle = 'FixedSingle'
	$add_disk_form.TopMost = $true
	$add_disk_form.Icon = $Icon
	
	$add_disk_form_storage_container_label = New-Object System.Windows.Forms.Label
	$add_disk_form_storage_container_label.Location = New-Object System.Drawing.Size(10, 45)
	$add_disk_form_storage_container_label.Size = New-Object System.Drawing.Size(150, 20)
	$add_disk_form_storage_container_label.Text = "Storage Container"
	$add_disk_form.Controls.Add($add_disk_form_storage_container_label)
	
	$add_disk_form_storage_container_input = New-Object System.Windows.Forms.ComboBox
	$add_disk_form_storage_container_input.Sorted = $true
	$add_disk_form_storage_container_input.Location = New-Object System.Drawing.Size(180, 45)
	$add_disk_form_storage_container_input.Size = New-Object System.Drawing.Size(150, 20)
	$add_disk_form_storage_container_input.DropDownStyle = 'DropDownList'
	$index = 0
	
	
	switch ($cluster_selection_form_combobox.SelectedItem)
	{
		"b1ntnx-clusvip1"
		{
			$container = "nxstco01"
			break
		}
		"b2ntnx-clusvip2"
		{
			$container = "nxstco02"
			break
		}
		"B0NTNX-LAB"
		{
			$container = "nxstcolab"
			break
		}
	}
	$add_disk_form_storage_container_input.Items.Add($container)
	<#foreach ($storage_container in $storage_containers)
	{
		$add_disk_form_storage_container_input.Items.Add($storage_container.name)
		if ($storage_container.name -like "nxstco*")
		{
			$add_disk_form_storage_container_input.SelectedIndex = $index
		}
		else
		{
			$index++
		}
	}#>
	
	$add_disk_form.Controls.Add($add_disk_form_storage_container_input)
	
	$add_disk_form_size_label = New-Object System.Windows.Forms.Label
	$add_disk_form_size_label.Location = New-Object System.Drawing.Size(10, 10)
	$add_disk_form_size_label.Size = New-Object System.Drawing.Size(150, 20)
	$add_disk_form_size_label.Text = "Disk size (GB)"
	$add_disk_form.Controls.Add($add_disk_form_size_label)
	
	$add_disk_form_size_input = New-Object System.Windows.Forms.TextBox
	$add_disk_form_size_input.Location = New-Object System.Drawing.Size(180, 10)
	$add_disk_form_size_input.Size = New-Object System.Drawing.Size(150, 20)
	$add_disk_form.Controls.Add($add_disk_form_size_input)
	
	
	$add_disk_form_add_button = New-Object System.Windows.Forms.Button
	$add_disk_form_add_button.Location = New-Object System.Drawing.Size(180, 80)
	$add_disk_form_add_button.Size = New-Object System.Drawing.Size(70, 23)
	$add_disk_form_add_button.Text = "Add"
	$add_disk_form_add_button.Add_Click({
			if ($add_disk_form_size_input.Text -and $add_disk_form_storage_container_input)
			{
				if ($modify_mode -eq "add")
				{
					$global:disk_counter++
					$list_item = New-Object System.Windows.Forms.ListViewItem($add_disk_form_size_input.Text)
					$list_item.SubItems.Add($add_disk_form_storage_container_input.Text)
					$disk_table.Items.Add($list_item)
					relocate_objects
					$add_disk_form.Close()
				}
				if ($modify_mode -eq "edit")
				{
					$disk_table.SelectedItems.Subitems[0].Text = $add_disk_form_size_input.Text
					$disk_table.SelectedItems.Subitems[1].Text = $add_disk_form_storage_container_input.Text
					$add_disk_form.Close()
				}
			}
			else
			{
				[System.Windows.Forms.MessageBox]::Show("Please fill out all Fields", "Error", 0)
			}
		})
	$add_disk_form.Controls.Add($add_disk_form_add_button)
	
	#------------------------------------------------------------------
	
	$add_disk_button = New-Object System.Windows.Forms.Button
	$add_disk_button.Location = New-Object System.Drawing.Size(295, 25)
	$add_disk_button.Size = New-Object System.Drawing.Size(70, 23)
	$add_disk_button.Text = "Add"
	$add_disk_button.Add_Click({
		$add_disk_form_add_button.Text = "Add"
		$modify_mode = "add"
			
		$add_disk_form_size_input.Text = ""
		$add_disk_form_storage_container_input.Text = ""
			
		$add_disk_form.ShowDialog()
	})
	$disk_groupbox.Controls.Add($add_disk_button)
	
	$edit_disk_button = New-Object System.Windows.Forms.Button
	$edit_disk_button.Enabled = $false
	$edit_disk_button.Location = New-Object System.Drawing.Size(295, 50)
	$edit_disk_button.Size = New-Object System.Drawing.Size(70, 23)
	$edit_disk_button.Text = "Edit"
	$edit_disk_button.Add_Click({
			$add_disk_form_add_button.Text = "Apply"
			$modify_mode = "edit"
			$add_disk_form_size_input.Text = $disk_table.SelectedItems.Subitems[0].Text
			$add_disk_form_storage_container_input.Text = $disk_table.SelectedItems.Subitems[1].Text
			$add_disk_form.ShowDialog()
		})
	$disk_groupbox.Controls.Add($edit_disk_button)
	
	$remove_disk_button = New-Object System.Windows.Forms.Button
	$remove_disk_button.Enabled = $false
	$remove_disk_button.Location = New-Object System.Drawing.Size(295, 75)
	$remove_disk_button.Size = New-Object System.Drawing.Size(70, 23)
	$remove_disk_button.Text = "Remove"
	$remove_disk_button.Add_Click({
			foreach($item in $disk_table.SelectedItems)
			{
				$disk_table.Items.Remove($item)
			}
			relocate_objects
		})
	$disk_groupbox.Controls.Add($remove_disk_button)
	
	
	#------------------------------------------------------------------
	
	
	#Disk table
	
	$disk_table = New-Object System.Windows.Forms.ListView
	$disk_table.Location = New-Object System.Drawing.Size(10, 25)
	$disk_table.Size = New-Object System.Drawing.Size(280, 30)
	$disk_table.Columns.Add("Size", 130)
	$disk_table.Columns.Add("Storage container", 130)
	$disk_table.View = 'Details'
	$disk_table.Scrollable = $false
	$disk_table.LabelWrap = $false
	$disk_table.LabelEdit = $false
	$disk_table.AllowColumnReorder = $false
	$disk_table.AllowDrop = $false
	$disk_table.FullRowSelect = $true
	$disk_table.add_ItemSelectionChanged({
			if ($disk_table.SelectedItems)
			{
				if ($disk_table.SelectedItems.Count -eq 1)
				{
					$edit_disk_button.Enabled = $true
				}
				else
				{
					$edit_disk_button.Enabled = $false
				}
				$remove_disk_button.Enabled = $true
			}
			else
			{
				$edit_disk_button.Enabled = $false
				$remove_disk_button.Enabled = $false
			}
		})
		
	$disk_groupbox.Controls.Add($disk_table)
	#------------------------------------------------------------------
	
	# NIC groupbox
	$nic_groupbox = New-Object System.Windows.Forms.GroupBox
	$nic_groupbox.Location = New-Object System.Drawing.Size(5, ($disk_groupbox.Location.Y + $disk_groupbox.Height + 10))
	$nic_groupbox.AutoSize = $true
	$nic_groupbox.AutoSizeMode = 'GrowAndShrink'
	$nic_groupbox.text = "NIC's (First NIC will be used for SCCM-Device)"
	$vm_input_form.Controls.Add($nic_groupbox)
	
	# Add nic form
	$add_nic_form = New-Object System.Windows.Forms.Form
	$add_nic_form.Text = "NIC"
	$add_nic_form.Size = New-Object System.Drawing.Size(350, 150)
	$add_nic_form.AutoSize = $true
	$add_nic_form.AutoSizeMode = 'GrowAndShrink'
	$add_nic_form.StartPosition = "CenterScreen"
	$add_nic_form.MinimizeBox = $false
	$add_nic_form.MaximizeBox = $false
	$add_nic_form.FormBorderStyle = 'FixedSingle'
	$add_nic_form.TopMost = $true
	$add_nic_form.Icon = $Icon
	
	$add_nic_form_vlan_label = New-Object System.Windows.Forms.Label
	$add_nic_form_vlan_label.Location = New-Object System.Drawing.Size(10, 10)
	$add_nic_form_vlan_label.Size = New-Object System.Drawing.Size(150, 20)
	$add_nic_form_vlan_label.Text = "VLAN"
	$add_nic_form.Controls.Add($add_nic_form_vlan_label)
	
	$add_nic_form_vlan_input = New-Object System.Windows.Forms.ComboBox
	$add_nic_form_vlan_input.Sorted = $true
	$add_nic_form_vlan_input.DropDownStyle = 'DropDownList'
	$add_nic_form_vlan_input.Location = New-Object System.Drawing.Size(180, 10)
	$add_nic_form_vlan_input.Size = New-Object System.Drawing.Size(150, 20)
	foreach ($vnet in $vnetworks)
	{
		$add_nic_form_vlan_input.Items.Add($vnet.Name)
	}
	$add_nic_form.Controls.Add($add_nic_form_vlan_input)
	
	$add_nic_form_net_con_state_label = New-Object System.Windows.Forms.Label
	$add_nic_form_net_con_state_label.Location = New-Object System.Drawing.Size(10, 45)
	$add_nic_form_net_con_state_label.Size = New-Object System.Drawing.Size(150, 20)
	$add_nic_form_net_con_state_label.Text = "Network connection state"
	$add_nic_form.Controls.Add($add_nic_form_net_con_state_label)
	
	$add_nic_form_net_con_state_input = New-Object System.Windows.Forms.ComboBox
	$add_nic_form_net_con_state_input.Sorted = $true
	$add_nic_form_net_con_state_input.DropDownStyle = 'DropDownList'
	$add_nic_form_net_con_state_input.Location = New-Object System.Drawing.Size(180, 45)
	$add_nic_form_net_con_state_input.Size = New-Object System.Drawing.Size(150, 20)
	$add_nic_form_net_con_state_input.Items.AddRange(@('Connected','Disconnected'))
	$add_nic_form.Controls.Add($add_nic_form_net_con_state_input)
	
	$add_nic_form_ip_config = New-Object System.Windows.Forms.CheckBox
	$add_nic_form_ip_config.Text = "Add IP Config"
	$add_nic_form_ip_config.Size = New-Object System.Drawing.Size(200, 25)
	$add_nic_form_ip_config.Location = New-Object System.Drawing.Size(10, 80)
	$add_nic_form_ip_config.add_CheckedChanged({
			if ($add_nic_form_ip_config.Checked -eq $true)
			{
				$add_nic_form_add_button.Location = New-Object System.Drawing.Size(150, ($ip_config_groupbox.Location.Y + $ip_config_groupbox.Height + 10))
				$ip_config_groupbox.Visible = $true
			}
			else
			{
				$add_nic_form_add_button.Location = New-Object System.Drawing.Size(150, 115)
				$ip_config_groupbox.Visible = $false
			}
		})
	$add_nic_form.Controls.Add($add_nic_form_ip_config)
	
	#SCCM IP Config
	$ip_config_groupbox = New-Object System.Windows.Forms.GroupBox
	$ip_config_groupbox.Location = New-Object System.Drawing.Size(5, 100)
	$ip_config_groupbox.AutoSize = $true
	$ip_config_groupbox.AutoSizeMode = 'GrowAndShrink'
	$ip_config_groupbox.Visible = $false
	
	$ip_config_name_label = New-Object System.Windows.Forms.Label
	$ip_config_name_label.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_name_label.Location = New-Object System.Drawing.Size(5, 10)
	$ip_config_name_label.Text = "Name:"
	$ip_config_groupbox.Controls.Add($ip_config_name_label)
	
	$ip_config_name_input = New-Object System.Windows.Forms.TextBox
	$ip_config_name_input.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_name_input.Location = New-Object System.Drawing.Size(165, 10)
	$ip_config_groupbox.Controls.Add($ip_config_name_input)
	
	
	$ip_config_ipaddresslist_label = New-Object System.Windows.Forms.Label
	$ip_config_ipaddresslist_label.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_ipaddresslist_label.Location = New-Object System.Drawing.Size(5, 45)
	$ip_config_ipaddresslist_label.Text = "IPAddressList:"
	$ip_config_groupbox.Controls.Add($ip_config_ipaddresslist_label)
	
	$ip_config_ipaddresslist_input = New-Object System.Windows.Forms.TextBox
	$ip_config_ipaddresslist_input.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_ipaddresslist_input.Location = New-Object System.Drawing.Size(165, 45)
	$ip_config_groupbox.Controls.Add($ip_config_ipaddresslist_input)
	
	$ip_config_mask_label = New-Object System.Windows.Forms.Label
	$ip_config_mask_label.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_mask_label.Location = New-Object System.Drawing.Size(5, 80)
	$ip_config_mask_label.Text = "SubnetMask:"
	$ip_config_groupbox.Controls.Add($ip_config_mask_label)
	
	$ip_config_mask_input = New-Object System.Windows.Forms.TextBox
	$ip_config_mask_input.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_mask_input.Location = New-Object System.Drawing.Size(165, 80)
	$ip_config_groupbox.Controls.Add($ip_config_mask_input)
	
	$ip_config_gateway_label = New-Object System.Windows.Forms.Label
	$ip_config_gateway_label.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_gateway_label.Location = New-Object System.Drawing.Size(5, 115)
	$ip_config_gateway_label.Text = "Gateways:"
	$ip_config_groupbox.Controls.Add($ip_config_gateway_label)
	
	$ip_config_gateway_input = New-Object System.Windows.Forms.TextBox
	$ip_config_gateway_input.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_gateway_input.Location = New-Object System.Drawing.Size(165, 115)
	$ip_config_groupbox.Controls.Add($ip_config_gateway_input)
	
	$ip_config_dns_label = New-Object System.Windows.Forms.Label
	$ip_config_dns_label.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_dns_label.Location = New-Object System.Drawing.Size(5, 150)
	$ip_config_dns_label.Text = "DNSServerList:"
	$ip_config_groupbox.Controls.Add($ip_config_dns_label)
	
	$ip_config_dns_input = New-Object System.Windows.Forms.TextBox
	$ip_config_dns_input.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_dns_input.Location = New-Object System.Drawing.Size(165, 150)
	$ip_config_groupbox.Controls.Add($ip_config_dns_input)
	
	$ip_config_dnsdomain_label = New-Object System.Windows.Forms.Label
	$ip_config_dnsdomain_label.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_dnsdomain_label.Location = New-Object System.Drawing.Size(5, 185)
	$ip_config_dnsdomain_label.Text = "DNSDomain:"
	$ip_config_groupbox.Controls.Add($ip_config_dnsdomain_label)
	
	$ip_config_dnsdomain_input = New-Object System.Windows.Forms.TextBox
	$ip_config_dnsdomain_input.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_dnsdomain_input.Location = New-Object System.Drawing.Size(165, 185)
	$ip_config_groupbox.Controls.Add($ip_config_dnsdomain_input)
	
	$add_nic_form.Controls.Add($ip_config_groupbox)
	
	#------------------------------------------------------------------
	
	$add_nic_form_add_button = New-Object System.Windows.Forms.Button
	$add_nic_form_add_button.Location = New-Object System.Drawing.Size(180, 115)
	$add_nic_form_add_button.Size = New-Object System.Drawing.Size(70, 23)
	$add_nic_form_add_button.Text = "Add"
	$add_nic_form_add_button.Add_Click({
			if ($add_nic_form_net_con_state_input.Text -and $add_nic_form_vlan_input.Text)
			{
				if ($modify_mode -eq "add")
				{
					$global:nic_counter++
					$list_item = New-Object System.Windows.Forms.ListViewItem($add_nic_form_vlan_input.Text)
					$list_item.SubItems.Add($add_nic_form_net_con_state_input.Text)
					$list_item.SubItems.Add($global:nic_counter)
					$nic_table.Items.Add($list_item)
					
					if ($add_nic_form_ip_config.Checked)
					{
						$config = [ip_config]::new()
						$config.name = $ip_config_name_input.Text
						$config.ipaddresslist = $ip_config_ipaddresslist_input.Text
						$config.subnetmask = $ip_config_mask_input.Text
						$config.gateways = $ip_config_gateway_input.Text
						$config.dnsserverlist = $ip_config_dns_input.Text
						$config.dnsdomain = $ip_config_dnsdomain_input.Text
						
						$ip_configs.Add([string]$global:nic_counter,$config)
					}
					
					relocate_objects
					$add_nic_form.Close()
				}
				if ($modify_mode -eq "edit")
				{
					$nic_table.SelectedItems.Subitems[0].Text = $add_nic_form_vlan_input.Text
					$nic_table.SelectedItems.Subitems[1].Text = $add_nic_form_net_con_state_input.Text
					
					if ($add_nic_form_ip_config.Checked)
					{
						$config = [ip_config]::new()
						$config.name = $ip_config_name_input.Text
						$config.ipaddresslist = $ip_config_ipaddresslist_input.Text
						$config.subnetmask = $ip_config_mask_input.Text
						$config.gateways = $ip_config_gateway_input.Text
						$config.dnsserverlist = $ip_config_dns_input.Text
						$config.dnsdomain = $ip_config_dnsdomain_input.Text
						
						if ($ip_configs.($nic_table.SelectedItems.Subitems[2].Text))
						{
							$ip_configs.($nic_table.SelectedItems.Subitems[2].Text) = $config
						}
						else
						{
							$ip_configs.Add($nic_table.SelectedItems.Subitems[2].Text, $config)
						}
					}
					else
					{
						$ip_configs.Remove($nic_table.SelectedItems.Subitems[2].Text)
					}
					$add_nic_form.Close()
				}
			}
			else
			{
				[System.Windows.Forms.MessageBox]::Show("Please fill out all Fields", "Error", 0)
			}
		})
	$add_nic_form.Controls.Add($add_nic_form_add_button)
	
	#------------------------------------------------------------------
	
	$add_nic_button = New-Object System.Windows.Forms.Button
	$add_nic_button.Location = New-Object System.Drawing.Size(295, 25)
	$add_nic_button.Size = New-Object System.Drawing.Size(70, 23)
	$add_nic_button.Text = "Add"
	$add_nic_button.Add_Click({
			$add_nic_form_add_button.Text = "Add"
			$modify_mode = "add"
			
			$add_nic_form_ip_config.Checked = $false
			$ip_config_name_input.Text = ""
			$ip_config_ipaddresslist_input.Text = ""
			$ip_config_mask_input.Text = ""
			$ip_config_gateway_input.Text = ""
			$ip_config_dns_input.Text = ""
			$ip_config_dnsdomain_input.Text = ""
			
			$add_nic_form_net_con_state_input.SelectedIndex = -1
			$add_nic_form_vlan_input.SelectedIndex = -1
			
			
			$add_nic_form.ShowDialog()
		})
	$nic_groupbox.Controls.Add($add_nic_button)
	
	$edit_nic_button = New-Object System.Windows.Forms.Button
	$edit_nic_button.Enabled = $false
	$edit_nic_button.Location = New-Object System.Drawing.Size(295, 50)
	$edit_nic_button.Size = New-Object System.Drawing.Size(70, 23)
	$edit_nic_button.Text = "Edit"
	$edit_nic_button.Add_Click({
			$add_nic_form_add_button.Text = "Apply"
			$modify_mode = "edit"
			
			$add_nic_form_vlan_input.Text = $nic_table.SelectedItems.Subitems[0].Text
			$add_nic_form_net_con_state_input.Text = $nic_table.SelectedItems.Subitems[1].Text
			
			$config = $ip_configs.($nic_table.SelectedItems.Subitems[2].Text)
			if ($config)
			{
				$add_nic_form_ip_config.Checked = $true
				$ip_config_name_input.Text = $config.name
				$ip_config_ipaddresslist_input.Text = $config.ipaddresslist
				$ip_config_mask_input.Text = $config.subnetmask
				$ip_config_gateway_input.Text = $config.gateways
				$ip_config_dns_input.Text = $config.dnsserverlist
				$ip_config_dnsdomain_input.Text = $config.dnsdomain
			}
			else
			{
				$add_nic_form_ip_config.Checked = $false
				$ip_config_name_input.Text = ""
				$ip_config_ipaddresslist_input.Text = ""
				$ip_config_mask_input.Text = ""
				$ip_config_gateway_input.Text = ""
				$ip_config_dns_input.Text = ""
				$ip_config_dnsdomain_input.Text =""
			}
			$add_nic_form.ShowDialog()
		})
	$nic_groupbox.Controls.Add($edit_nic_button)
	
	$remove_nic_button = New-Object System.Windows.Forms.Button
	$remove_nic_button.Enabled = $false
	$remove_nic_button.Location = New-Object System.Drawing.Size(295, 75)
	$remove_nic_button.Size = New-Object System.Drawing.Size(70, 23)
	$remove_nic_button.Text = "Remove"
	$remove_nic_button.Add_Click({
			foreach ($item in $nic_table.SelectedItems)
			{
				$nic_table.Items.Remove($item)
			}
			relocate_objects
		})
	$nic_groupbox.Controls.Add($remove_nic_button)
	
	
	#NIC table
	$nic_table = New-Object System.Windows.Forms.ListView
	$nic_table.Location = New-Object System.Drawing.Size(10, 25)
	$nic_table.Size = New-Object System.Drawing.Size(280, 30)
	$nic_table.Columns.Add("VLAN", 130)
	$nic_table.Columns.Add("Network Connection State", 130)
	$nic_table.View = 'Details'
	$nic_table.Scrollable = $false
	$nic_table.LabelWrap = $false
	$nic_table.LabelEdit = $false
	$nic_table.AllowColumnReorder = $false
	$nic_table.AllowDrop = $false
	$nic_table.FullRowSelect = $true
	$nic_table.add_ItemSelectionChanged({
			if ($nic_table.SelectedItems)
			{
				if ($nic_table.SelectedItems.Count -eq 1)
				{
					$edit_nic_button.Enabled = $true
				}
				else
				{
					$edit_nic_button.Enabled = $false
				}
				$remove_nic_button.Enabled = $true
			}
			else
			{
				$edit_nic_button.Enabled = $false
				$remove_nic_button.Enabled = $false
			}
		})
	
	
	#------------------------------------------------------------------
	$nic_groupbox.Controls.Add($nic_table)
	#------------------------------------------------------------------
	
	$vm_input_form_start_vm_input = New-Object System.Windows.Forms.CheckBox
	$vm_input_form_start_vm_input.Location = New-Object System.Drawing.Size(10, ($nic_groupbox.Location.Y + $nic_groupbox.Height + 10))
	$vm_input_form_start_vm_input.Size = New-Object System.Drawing.Size(200, 25)
	$vm_input_form_start_vm_input.Text = "Start VM when created"
	$vm_input_form.Controls.Add($vm_input_form_start_vm_input)
	
	$vm_input_form_create_button = New-Object System.Windows.Forms.Button
	$vm_input_form_create_button.Size = New-Object System.Drawing.Size(70, 23)
	$vm_input_form_create_button.Location = New-Object System.Drawing.Size(165, ($vm_input_form_start_vm_input.Location.Y + $vm_input_form_start_vm_input.Height + 10))
	$vm_input_form_create_button.Text = "Create"
	$vm_input_form_create_button.add_Click({
		$vm_input_form.TopMost = $false
		create_vm
	})
	
	$vm_input_form.Controls.Add($vm_input_form_create_button)
	
	$vm_input_form.ShowDialog();
	}


#------------------------------------------------------------------

# Input form to Add IP Config^

function show_ip_config_form()
{
	$all_sccm_device = Get-CMDevice
	$string_collection = New-Object System.Windows.Forms.AutoCompleteStringCollection
	$string_collection.AddRange($all_sccm_device.name)
	
	$ip_config_form = New-Object System.Windows.Forms.Form
	$ip_config_form.Text = "Add IP Config"
	$ip_config_form.AutoSize = $true
	$ip_config_form.AutoSizeMode = 'GrowAndShrink'
	$ip_config_form.StartPosition = "CenterScreen"
	$ip_config_form.MinimizeBox = $false
	$ip_config_form.MaximizeBox = $false
	$ip_config_form.FormBorderStyle = 'FixedSingle'
	$ip_config_form.TopMost = $true
	$ip_config_form.Icon = $Icon
	
	
	$ip_config_devicename_label = New-Object System.Windows.Forms.Label
	$ip_config_devicename_label.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_devicename_label.Location = New-Object System.Drawing.Size(10, 10)
	$ip_config_devicename_label.Text = "Device name:"
	$ip_config_form.Controls.Add($ip_config_devicename_label)
	
	$ip_config_device_selection = New-Object System.Windows.Forms.TextBox
	$ip_config_device_selection.Location = New-Object System.Drawing.Size(10, 30)
	$ip_config_device_selection.Size = New-Object System.Drawing.Size(300, 20)
	$ip_config_device_selection.AutoCompleteMode = 'SuggestAppend'
	$ip_config_device_selection.AutoCompleteSource = 'CustomSource'
	$ip_config_device_selection.AutoCompleteCustomSource = $string_collection
	
	$ip_config_form.Controls.Add($ip_config_device_selection)
		
	$ip_config_groupbox = New-Object System.Windows.Forms.GroupBox
	$ip_config_groupbox.Location = New-Object System.Drawing.Size(5, 50)
	$ip_config_groupbox.AutoSize = $true
	$ip_config_groupbox.AutoSizeMode = 'GrowAndShrink'
	
	$ip_config_name_label = New-Object System.Windows.Forms.Label
	$ip_config_name_label.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_name_label.Location = New-Object System.Drawing.Size(5, 10)
	$ip_config_name_label.Text = "Name:"
	$ip_config_groupbox.Controls.Add($ip_config_name_label)
	
	$ip_config_name_input = New-Object System.Windows.Forms.TextBox
	$ip_config_name_input.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_name_input.Location = New-Object System.Drawing.Size(165, 10)
	$ip_config_groupbox.Controls.Add($ip_config_name_input)
	
	$ip_config_mac_label = New-Object System.Windows.Forms.Label
	$ip_config_mac_label.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_mac_label.Location = New-Object System.Drawing.Size(5, 45)
	$ip_config_mac_label.Text = "MacAddress"
	$ip_config_groupbox.Controls.Add($ip_config_mac_label)
	
	$ip_config_mac_input = New-Object System.Windows.Forms.TextBox
	$ip_config_mac_input.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_mac_input.Location = New-Object System.Drawing.Size(165, 45)
	$ip_config_groupbox.Controls.Add($ip_config_mac_input)
	
	$ip_config_ipaddresslist_label = New-Object System.Windows.Forms.Label
	$ip_config_ipaddresslist_label.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_ipaddresslist_label.Location = New-Object System.Drawing.Size(5, 80)
	$ip_config_ipaddresslist_label.Text = "IPAddressList:"
	$ip_config_groupbox.Controls.Add($ip_config_ipaddresslist_label)
	
	$ip_config_ipaddresslist_input = New-Object System.Windows.Forms.TextBox
	$ip_config_ipaddresslist_input.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_ipaddresslist_input.Location = New-Object System.Drawing.Size(165, 80)
	$ip_config_groupbox.Controls.Add($ip_config_ipaddresslist_input)
	
	$ip_config_mask_label = New-Object System.Windows.Forms.Label
	$ip_config_mask_label.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_mask_label.Location = New-Object System.Drawing.Size(5, 115)
	$ip_config_mask_label.Text = "SubnetMask:"
	$ip_config_groupbox.Controls.Add($ip_config_mask_label)
	
	$ip_config_mask_input = New-Object System.Windows.Forms.TextBox
	$ip_config_mask_input.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_mask_input.Location = New-Object System.Drawing.Size(165, 115)
	$ip_config_groupbox.Controls.Add($ip_config_mask_input)
	
	$ip_config_gateway_label = New-Object System.Windows.Forms.Label
	$ip_config_gateway_label.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_gateway_label.Location = New-Object System.Drawing.Size(5, 150)
	$ip_config_gateway_label.Text = "Gateways:"
	$ip_config_groupbox.Controls.Add($ip_config_gateway_label)
	
	$ip_config_gateway_input = New-Object System.Windows.Forms.TextBox
	$ip_config_gateway_input.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_gateway_input.Location = New-Object System.Drawing.Size(165, 150)
	$ip_config_groupbox.Controls.Add($ip_config_gateway_input)
	
	$ip_config_dns_label = New-Object System.Windows.Forms.Label
	$ip_config_dns_label.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_dns_label.Location = New-Object System.Drawing.Size(5, 185)
	$ip_config_dns_label.Text = "DNSServerList:"
	$ip_config_groupbox.Controls.Add($ip_config_dns_label)
	
	$ip_config_dns_input = New-Object System.Windows.Forms.TextBox
	$ip_config_dns_input.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_dns_input.Location = New-Object System.Drawing.Size(165, 185)
	$ip_config_groupbox.Controls.Add($ip_config_dns_input)
	
	$ip_config_dnsdomain_label = New-Object System.Windows.Forms.Label
	$ip_config_dnsdomain_label.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_dnsdomain_label.Location = New-Object System.Drawing.Size(5, 220)
	$ip_config_dnsdomain_label.Text = "DNSDomain:"
	$ip_config_groupbox.Controls.Add($ip_config_dnsdomain_label)
	
	$ip_config_dnsdomain_input = New-Object System.Windows.Forms.TextBox
	$ip_config_dnsdomain_input.Size = New-Object System.Drawing.Size(150, 20)
	$ip_config_dnsdomain_input.Location = New-Object System.Drawing.Size(165, 220)
	$ip_config_groupbox.Controls.Add($ip_config_dnsdomain_input)
	
	$ip_config_form.Controls.Add($ip_config_groupbox)
	
	$ip_config_add_button = New-Object System.Windows.Forms.Button
	$ip_config_add_button.Location = New-Object System.Drawing.Size(125, 325)
	$ip_config_add_button.Size = New-Object System.Drawing.Size(70, 23)
	$ip_config_add_button.Text = "Add"
	$ip_config_add_button.Add_Click({
			
			if ($ip_config_device_selection.Text -and ($device = ($all_sccm_device | where { $_.name -eq $ip_config_device_selection.Text })))
			{
				try
				{
					$adapter_count = (Get-CMDeviceVariable -DeviceName $device.name -VariableName "UD_AdapterCount").Value
					if (!$adapter_count)
					{
						$adapter_count = 0
					}
					New-CMDeviceVariable -DeviceName $ip_config_device_selection.Text -IsMask $false -VariableName ('UD_Adapter' + $adapter_count + 'Index') -VariableValue $adapter_count
					New-CMDeviceVariable -DeviceName $ip_config_device_selection.Text -IsMask $false -VariableName ('UD_Adapter' + $adapter_count + 'Name') -VariableValue $ip_config_name_input.Text
					New-CMDeviceVariable -DeviceName $ip_config_device_selection.Text -IsMask $false -VariableName ('UD_Adapter' + $adapter_count + 'MacAddress') -VariableValue ($ip_config_mac_input.Text -replace("-",":"))
					New-CMDeviceVariable -DeviceName $ip_config_device_selection.Text -IsMask $false -VariableName ('UD_Adapter' + $adapter_count + 'EnableDHCP') -VariableValue 'FALSE'
					New-CMDeviceVariable -DeviceName $ip_config_device_selection.Text -IsMask $false -VariableName ('UD_Adapter' + $adapter_count + 'IPAddressList') -VariableValue $ip_config_ipaddresslist_input.Text
					New-CMDeviceVariable -DeviceName $ip_config_device_selection.Text -IsMask $false -VariableName ('UD_Adapter' + $adapter_count + 'SubnetMask') -VariableValue $ip_config_mask_input.Text
					New-CMDeviceVariable -DeviceName $ip_config_device_selection.Text -IsMask $false -VariableName ('UD_Adapter' + $adapter_count + 'Gateways') -VariableValue $ip_config_gateway_input.Text
					New-CMDeviceVariable -DeviceName $ip_config_device_selection.Text -IsMask $false -VariableName ('UD_Adapter' + $adapter_count + 'DNSServerList') -VariableValue $ip_config_dns_input.Text
					New-CMDeviceVariable -DeviceName $ip_config_device_selection.Text -IsMask $false -VariableName ('UD_Adapter' + $adapter_count + 'DNSDomain') -VariableValue $ip_config_dnsdomain_input.Text
					New-CMDeviceVariable -DeviceName $ip_config_device_selection.Text -IsMask $false -VariableName ('UD_Adapter' + $adapter_count + 'EnableDNSRegistration') -VariableValue 'TRUE'
					New-CMDeviceVariable -DeviceName $ip_config_device_selection.Text -IsMask $false -VariableName ('UD_Adapter' + $adapter_count + 'EnableFullDNSRegistration') -VariableValue 'TRUE'
					New-CMDeviceVariable -DeviceName $ip_config_device_selection.Text -IsMask $false -VariableName ('UD_Adapter' + $adapter_count + 'GatewayCostMetric') -VariableValue 'automatic'
					
					New-CMDeviceVariable -DeviceName $ip_config_device_selection.Text -IsMask $false -VariableName 'UD_AdapterCount' -VariableValue ([int]$adapter_count + 1)
					[System.Windows.Forms.MessageBox]::Show("Variables successfully added", "Info", 0)
					$ip_config_name_input.Text = ""
					$ip_config_mac_input.Text = ""
					$ip_config_ipaddresslist_input.Text = ""
					$ip_config_mask_input.Text = ""
					$ip_config_gateway_input.Text = ""
					$ip_config_dns_input.Text = ""
					$ip_config_dnsdomain_input.Text = ""
				}
				catch
				{
					[System.Windows.Forms.MessageBox]::Show("Error while adding variables", "Error", 0)
				}
			}
			else
			{
				[System.Windows.Forms.MessageBox]::Show("Please enter valid SCCM Device Name", "Error", 0)
			}
			
		})
	$ip_config_form.Controls.Add($ip_config_add_button)
	
	$ip_config_form.ShowDialog()
	
}



#Cluster Selection Form -------------------------------------------
$cluster_selection_form = New-Object System.Windows.Forms.Form
$cluster_selection_form.Text = "Select action"
$cluster_selection_form.Size = New-Object System.Drawing.Size(275, 160)
$cluster_selection_form.StartPosition = "CenterScreen"
$cluster_selection_form.MinimizeBox = $false
$cluster_selection_form.MaximizeBox = $false
$cluster_selection_form.FormBorderStyle = 'FixedSingle'

$Icon = New-Object system.drawing.icon ("$Env:ICONDIR\icon_unico_settings_minimal.ico")
$cluster_selection_form.Icon = $Icon

$cluster_selection_form.KeyPreview = $True
$cluster_selection_form.Add_KeyDown({
		switch ($_.KeyCode)
		{
			"Enter" {
				$cluster_selection_form.Visible = $false
				switch ($cluster_selection_form_action.SelectedIndex)
				{
					0{
						if ($vm_input_form)
						{
							$vm_input_form.Enabled = $true
							$vm_input_form.BringToFront()
						}
						else
						{
							show_input_form
						}
					}
					1{ show_ip_config_form }
				}
			}
			"Escape" {
				$cluster_selection_form.Close()
			}
		}
	})

$cluster_selection_form_ok_button = New-Object System.Windows.Forms.Button
$cluster_selection_form_ok_button.Location = New-Object System.Drawing.Size(100, 90)
$cluster_selection_form_ok_button.Size = New-Object System.Drawing.Size(50, 23)
$cluster_selection_form_ok_button.Text = "OK"
$cluster_selection_form_ok_button.DialogResult = "OK"
$cluster_selection_form_ok_button.Add_Click({
		$cluster_selection_form.Visible = $false
		switch ($cluster_selection_form_action.SelectedIndex)
		{
			0{
				if ($vm_input_form)
				{
					$vm_input_form.Enabled = $true
					$vm_input_form.BringToFront()
				}
				else
				{
					show_input_form
				}
			}
			1	{ show_ip_config_form }
		}
	})
$cluster_selection_form.Controls.Add($cluster_selection_form_ok_button)

$cluster_selection_form_action = New-Object System.Windows.Forms.ComboBox
$cluster_selection_form_action.Location = New-Object System.Drawing.Size(25, 25)
$cluster_selection_form_action.Size = New-Object System.Drawing.Size(200, 23)
$cluster_selection_form_action.DropDownStyle = 'DropDownList'
$cluster_selection_form_action.Items.AddRange(@("Add VM", "Add SCCM IP Config"))
$cluster_selection_form_action.SelectedIndex = 0
$cluster_selection_form_action.add_SelectedValueChanged({
		if ($cluster_selection_form_action.SelectedIndex -eq 0)
		{
			$cluster_selection_form_combobox.Visible = $true
			$cluster_selection_form_combobox.Enabled = $true
		}
		else
		{
			$cluster_selection_form_combobox.Visible = $false
			$cluster_selection_form_combobox.Enabled = $false
		}
	})
$cluster_selection_form.Controls.Add($cluster_selection_form_action)




$cluster_selection_form_combobox = New-Object System.Windows.Forms.ComboBox
$cluster_selection_form_combobox.Location = New-Object System.Drawing.Size(25, 60)
$cluster_selection_form_combobox.Size = New-Object System.Drawing.Size(200, 23)
$cluster_selection_form_combobox.DropDownStyle = 'DropDownList'

ForEach ($NTNXCluster in $NTNXClusters)
{
	$cluster_selection_form_combobox.Items.Add($NTNXCluster)
}

$cluster_selection_form_combobox.SelectedIndex = 0
$cluster_selection_form.Controls.Add($cluster_selection_form_combobox)


$cluster_selection_form.ShowDialog()
#------------------------------------------------------------------
