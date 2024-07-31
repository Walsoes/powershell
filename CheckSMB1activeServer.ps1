#requires -version 4.0

Write-Output "This script requires PowerShell 4.0 or higher."

# INFO: Skriptet tar in en CSV fil i variabeln $servers välj en plats. Kolumen ska ha namnen "servernamn" eller det man väljer själv.Skall lörs med serveradminkonto.  
# Tanken är att köra scriptet i powershell ISE och köra olika delar. Allt fram till rad 80 är bara för att kolla status om SMB1 - protocollet på servernivå är påslaget
# PÅ rad 63 kan man sätta igång audit SMB1 för att se om klienter ansluter mot servrarna 


#Funktionen nedan sorterar om man kan öppna en fjärrsession med server 

Function Domain-Check {
   Param (
      [Parameter(Mandatory, ValueFromPipeline)]
      [string[]]
      $serv)
      
      $session = New-CimSession -ComputerName $serv -ErrorAction SilentlyContinue -ErrorVariable err

    if ($err.count -gt 0){
        Return $serv
        $err.clear()
        }  else {
  Return $session
   }
 
}

$servers = Import-CSV -path "C:\PS\Slutrapport\inData.csv" -Delimiter "," | Select-object -ExpandProperty ServerNamn  #sorterad lista
# $servers =  get-content C:\PS\slutrapport\Scanservrar.txt # en kolumn .txt fil med server

$Cimsession = @()
$felDoman = @()
[System.Collections.ArrayList]$SMB1 = @()
[System.Collections.ArrayList]$SMBconnections = @()
[System.Collections.ArrayList]$Anslutningsforsok = @()
[System.Collections.ArrayList]$Message = @()
[System.Collections.ArrayList]$ID = @()
[System.Collections.ArrayList]$serverlogg = @()
[System.Collections.ArrayList]$ingaSMB1 = @()


$global:rapport = @()  


#Sorterar om det är ett felmeddelande eller CIMsession-object och hämtar SMB1-data från servrar somhar powershell > 4.0 och att PS-remoting är påslaget

Foreach ($server in $servers) {

 $CimOK = Domain-Check $server

if (($CimOK).getType().name -eq "String"){

    $felDoman += $server 
    Write-host "fel för $($server)"

} elseif (($CimOK).getType().name -eq "Cimsession") {

try { 

 # Set-SmbServerConfiguration -AuditSmb1Access $false -EnableSMB1Protocol $false -CimSession $cimOK -force -ErrorAction SilentlyContinue ; write-host $server

#  Get-SmbServerConfiguration -CimSession $cimOK | Select-object @{L=’ServerNamn’;E={$_.PSComputerName}}, EnableSMB1Protocol, EnableSMB2Protocol, AuditSmb1Access 

$SMB1 += Get-SmbServerConfiguration -CimSession $cimOK | Select-object @{L=’ServerNamn’;E={$_.PSComputerName}}, EnableSMB1Protocol, EnableSMB2Protocol, AuditSmb1Access 

 # Get-WindowsOptionalFeatur online -FeatureName SMB1Protocol 
}

catch { write-host $error + "Error! "}

}

 $CimOK = $null

 }

 ----------------------------------------------------------------------------------------------
 # Om man har slagit på -AuditSmb1Access på rad 63 och låtit det gå någon vecka kan man få fram vilka klienter som ansluter
 # mot servrar som har SMB1 aktiverat



 $ServerRemoteOk = $servers | Where-Object { $_ -notin $feldoman}

Foreach ($server in $ServerRemoteOk) {

try { $Loggcheck = Invoke-Command -ComputerName $server -ErrorAction Stop -scriptBlock {get-winevent -listlog Microsoft-Windows-SMBServer/audit} 

 write-host "Det finns $($Loggcheck.RecordCount) loggentries för servern $($server)" -ForegroundColor Magenta }

catch { write-host "Kunde inte ansluta till servern: $($server)" -ForegroundColor Red; continue } 

#Finns loggevent - Ja spara -properties... / Nej - meddela och spara i Arrayen $ingaSMB1
    if($Loggcheck.RecordCount -gt 0) {

   $eventLogs = Invoke-Command -ComputerName $server -ErrorAction SilentlyContinue -scriptBlock { get-winevent -Logname Microsoft-Windows-SMBServer/audit <# hämtar 10 event ta bort om du vill hämta alla. #> | 
   Select-Object -property PScomputername, TimeCreated, Id, Leveldisplayname, Message } 
      


   $Message += $eventLogs.Message   

    } else {  
    write-host "`n Inga klienter för servern: $($server) har anslutit med SMB1 sedan 2022-11-18" -ForegroundColor Green
    $ingaSMB1 += $server 

    }


<#
#Scriptet nedan hittar Servernamn i loggeventet. Det kommer som en Sträng och ipadress. Ett logg-entry ser ut såhär:
SMB1 access

Client Address: 192.165.149.12      

Guidance:

This event indicates that a client attempted to access the server using SMB1. To stop auditing SMB1 access, use the Windows PowerShell cmdlet Set-SmbServerConfiguration.
SMB1 access

 #>


[System.Collections.ArrayList]$klientLookUp = @()

foreach ($eventlog in $eventLogs) {
 
$indexStart = $eventlog.message.IndexOf(':')+1

$indexSlut = $eventlog.message.indexOf('Guidance') 

$subdiff = $indexslut-$indexstart

$check = $eventlog.message.Substring($indexStart,$subdiff).trim()

if($klientlookup -notcontains $check) {

$klientLookUp += $check

    }
}



#DNS-Lookup som sorterar om det är en iP-adress eller en redan utredd klient

[System.Collections.ArrayList]$dnsnamn = @()
[System.Collections.ArrayList]$noDNSName = @()

foreach($klientIP in $klientLookUp){

if($klientIP -match "^((25[0-5]|(2[0-4]|1\d|[1-9]|)\d)\.?\b){4}$"){


try {
    $dns = Resolve-DnsName $klientIP -ErrorAction Stop | Select-Object -First 1 -ExpandProperty NameHost

    $dnsnamn += $dns
}

catch {

    Write-host "$($klientIP) ansluter mot $($server) och har ingen dns"
    

    $dnsnamn += $klientIP 
}
 
} else {

$dnsnamn += $klientIp

}

}


#   Get-CimSession | Remove-CimSession #avslutar cim-session


#skapar rapporten

for ($i = 0; $i -lt $eventLogs.Count; $i++){ 

 if ($dnsnamn[$i] -ne $null -and $dnsnamn[$i] -notin $scanServers) { 

     write-host "$($dnsnamn[$i]) använder SMB1protokollet mot $($eventLogs[$i].PScomputername)`r" -ForegroundColor red 


$rapport += [pscustomobject]@{
        Servernamn           = $eventLogs[$i].PScomputername                  
        AnslutandeKlient     = $dnsnamn[$i]
        ipAdressKlient       = $klientLookUp[$i]
        TidpunktLogg         = $eventlogs[$i].TimeCreated
      #  TotAntalanslutningar = $Loggcheck.RecordCount
      # ID                   = $eventLogs[$i].Id

   #    Meddelande       = $Message
  }
    
  }

  }


# else {Write-host "Något annat gick fel!"}
 
# $CimOK = $null

}






#Ska köras om en månad när auditen gått längre. Rensar för alla scanningservrar. 
<#
$scanServers =  get-content C:\PS\slutrapport\Scanservrar.txt

 switch ($rapport)
 {
     {$_.AnslutandeKlient -notin $Scanningsserverar} { 
     write-host "$($_.AnslutandeKlient) använder SMB1protokollet mot $($_.Servernamn)`r`n" -ForegroundColor red }
 }
    
#>


 
 # Utfiler från det grunläggande skriptet som finns på RAD 78

# Out-file -FilePath C:\PS\MINAserver\MINAservrarFELdoman.txt -InputObject $felDoman -Force 

# $SMB1 | Export-Csv -Path C:\PS\MINAserver\MINA_vercheck.csv -NoTypeInformation -Force -Encoding UTF8

# $SMBconnections | Export-Csv -Path C:\PS\MINAserver\MINA_Connectioncheck.csv -NoTypeInformation -Force -Encoding UTF8



#skapar CSVrapport för enkel import i Excel - bara att välja plats 

<#

$rapport | Export-Csv "C:\PS\Slutrapport\dataSlutrapport.csv" -Force -NoTypeInformation 

$smb1r = $rapport | Group-Object servernamn | Select-Object -ExpandProperty Name

[System.Collections.ArrayList]$INGETSMB1 = @()

foreach($servo in $servers){

if($servo -notin $smb1r) {

$INGETSMB1 += $servo

}
}

#>
