# Kör scriptet som SA
#installeras automatiskt

function Load-Module ($m) {

    # If module is imported say that and do nothing
    if (Get-Module | Where-Object {$_.Name -eq $m}) {
        write-host "Module $m is already imported."
    }
    else {

        # If module is not imported, but available on disk then import
        if (Get-Module -ListAvailable | Where-Object {$_.Name -eq $m}) {
            Import-Module $m -Verbose
        }
        else {

            # If module is not imported, not available on disk, but is in online gallery then install and import
            if (Find-Module -Name $m | Where-Object {$_.Name -eq $m}) {
                Install-Module -Name $m -Force -Verbose -Scope CurrentUser
                Import-Module $m -Verbose
            }
            else {

                # If the module is not imported, not available and not in the online gallery then abort
                write-host "Module $m not imported, not available and not in an online gallery, exiting."
                EXIT 1
            }
        }
    }
}

Load-Module "JoinModule"

#behöver modulen Joinmodule

$credpath = "C:\PS\Credentials.cred"

if (Test-path $credpath) {

            $creds = Import-Clixml -Path C:\PS\bens.cred
        } else {
            $creds = Get-credential
            
            $creds | Export-Clixml -Path C:\PS\bens.cred                
        }






$servers = invoke-command -ComputerName <AD-server> -Credential $creds -ScriptBlock { 
    Get-ADComputer -Properties operatingsystem -filter 'operatingsystem -like "Windows Server*"' | Select-object -ExpandProperty name } | sort-object

$serversOchOS = invoke-command -ComputerName <AD-server> -Credential $creds -ScriptBlock { 
    Get-ADComputer -Properties operatingsystem -filter 'operatingsystem -like "Windows Server*"' | Select-object -property @{Label="server";Expression={$_.name}},operatingsystem } | Sort-Object

[System.Collections.ArrayList]$RemoteOK = @()
[System.Collections.ArrayList]$NoRemote = @()
[System.Collections.ArrayList]$Rapport = @()
[System.Collections.ArrayList]$IngenJava = @()


foreach ($server in $servers) {
    
   $RemoteBoolean = [System.Net.Sockets.TcpClient]::new().ConnectAsync($server, 5985).Wait(250) 

    if($RemoteBoolean) {
        
        $RemoteOK += $server

    } else  {
        $NoRemote += $server
      
}
}

  
$ResultatJava = Invoke-command -Computername $RemoteOK -Credential $creds `
     -ErrorAction SilentlyContinue `
     -ErrorVariable ErrCon `
     -ThrottleLimit 100 `
     -scriptblock { 


      $Alldrives = [System.IO.DriveInfo]::getdrives() | Where-Object { $_.DriveType -eq "Fixed" } | Select-Object -ExpandProperty Name


       $JavaPaths = get-childitem -Path $alldrives -Recurse -Include java.exe -ErrorAction SilentlyContinue |
       Select-Object -Expandproperty VersionInfo | select ProductName, ProductVersion, CompanyName, LegalCopyright, FileName
        
 
        $JavaPaths

        }
 


        # ProductName,ProductVersion,CompanyName,LegalCopyright,FileName


Foreach($server in $Resultatjava) {

       $Rapport += [pscustomobject]@{

         "Server"           = $server.PSComputerName
         "ProductName"      = $server.ProductName
         "CompanyName"      = $server.CompanyName
         "ProductVersion"   = $server.ProductVersion
         "LegalCopyright"   = $server.LegalCopyright
         "FileName"         = $server.FileName
         "Java"             = $true    
         "Info vid fel"     = "" 

       }
}

    
 $Errorvidkorning = $errcon | select @{
                                        label='Server'
                                        expression={if ($_.targetobject) {$_.targetobject} else { $_.OriginInfo }}},FullyQualifiedErrorId 

  
Foreach($server in $errorvidkorning) {
       $Rapport += [pscustomobject]@{

        "Server"           = $server.Server
        "ProductName"      = ""
        "CompanyName"      = ""
        "ProductVersion"   = ""
        "LegalCopyright"   = ""
        "FileName"         = ""
        "Java"             = "Unknown"   
        "Info vid fel"     = $server.FullyQualifiedErrorId

       }
}
 
  
 Foreach ($server in $remoteOK) {
 
        if($server -notin $rapport.Server){

               $Rapport += [pscustomobject]@{

                          "Server"         = $server
                          "ProductName"    = ""
                          "CompanyName"    = ""
                          "ProductVersion" = ""
                          "LegalCopyright" = ""
                          "FileName"       = ""   
                          "Java"           = $false
                          "Info vid fel"   = ""

                        }
             
           }

}

  
 Foreach ($server in $Noremote) {
 
               $Rapport += [pscustomobject]@{

                          "Server"         = $server
                          "ProductName"    = ""
                          "CompanyName"    = ""
                          "ProductVersion" = ""
                          "LegalCopyright" = ""
                          "FileName"       = ""   
                          "Java"           = "Unknown"
                          "Info vid fel"   = "Port 5985 ej öppen (WSman) eller rättigheter saknas. " 

                        } 

}
  
 
 $rapportobject = Join-Object -LeftObject $rapport -RightObject $serversOchOS -On server | Select-Object -Property Server,operatingsystem,Productname,CompanyName,Productversion,legalcopyright,filename,java,"info vid fel" `
     -ExcludeProperty Pscomputername,runspaceid




 $rapportobject | Export-Csv -Path "C:\PS\Rapport0till545.csv" -Force -Encoding UTF8 -NoTypeInformation
