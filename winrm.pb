---
# since this playbook writes a bunch of files to setup winrm in the first place (to get ansible running),
# it's more of an example of what steps are needed than a practical runnable thing.
- hosts: all
  vars:
    TYPE: winrm
    INSTANCE: main

    BINS:
      - name: prep-ansible-host.sh
        become: True
        exec:
          pip3 install "pywinrm>=0.4.3"
      - name: policy-unrestricted.ps1
        exec: Set-ExecutionPolicy Unrestricted
      - name: cert.ps1
        exec:
          # https://woshub.com/powershell-remoting-over-https/
          $hostName = $env:COMPUTERNAME
          $hostIP=(Get-NetAdapter| Get-NetIPAddress).IPv4Address|Out-String
          # host
          $cert = New-SelfSignedCertificate -DnsName $hostName,$hostIP -CertStoreLocation Cert:\LocalMachine\My
          # localuser
          #$cert = New-SelfSignedCertificate -DnsName $hostName,$hostIP -CertStoreLocation Cert:\CurrentUser\My
          $thumbprint = $cert.Thumbprint
          $cert
          $cert.Thumbprint
      - name: get-thumbprint.ps1
          $thumbprint = Get-ChildItem -Path cert:\LocalMachine\My -Recurse | Where-Object { $_.Subject -eq "CN=$hostName" } | Select-Object PSChildName
      - name: start-listener.ps1
        exec:
          # winrm create winrm/config/Listener?Address=*+Transport=HTTPS '@{Hostname="{{hostname}}"; CertificateThumbprint="<COPIED_CERTIFICATE_THUMBPRINT>"}'
          $selector_set = @{
              Address = "*"
              Transport = "HTTPS"
          }
          $value_set = @{
              CertificateThumbprint = $thumbprint
          }
          New-WSManInstance -ResourceURI "winrm/config/Listener" -SelectorSet $selector_set -ValueSet $value_set
      - name: set-netpolicy-private.ps1
        exec:
          # https://4sysops.com/archives/enabling-powershell-remoting-fails-due-to-public-network-connection-type/
          # NetworkCategory=Public is poison
          Get-NetConnectionProfile 
          Set-NetConnectionProfile -NetworkCategory Private
      - name: psremoting-enable.ps1
        exec:
          #Enable-PSRemoting -SkipNetworkProfileCheck    
          Enable-PSRemoting
      - name: quickconfig.ps1
          Set-WSManQuickConfig -SkipNetworkProfileCheck -UseSSL
      - name: open-firewall.bat
        exec:
          # psremoting-enable.ps1 might be doing this maybe?
          # https://www.visualstudiogeeks.com/devops/how-to-configure-winrm-for-https-manually
          # would also need to configure listener for this to work
          port={{port}}
          netsh advfirewall firewall add rule name="Windows Remote Management (HTTPS-In)" dir=in action=allow protocol=TCP localport=$port
      - name: verify.ps1
        exec:
          $hostName="{{hostname}}" # example: "mywindowsvm.westus.cloudapp.azure.com"
          $winrmPort = {{port}}
          # Get the credentials of the machine
          $cred = Get-Credential
          # Connect to the machine
          $soptions = New-PSSessionOption -SkipCACheck
          Enter-PSSession -ComputerName $hostName -Port $winrmPort -Credential $cred -SessionOption $soptions -UseSSL
      - name: policy-allsigned.ps1
        exec: Set-ExecutionPolicy AllSigned
      - name: env.ps1
        exec:
          # collected vars for ref
          $hostName = "{{hostname}}"
          $winrmPort = {{port}}
          $user = {{user}}
          #$password = "no"
          $timeout = 30
          $hostIP=(Get-NetAdapter| Get-NetIPAddress).IPv4Address|Out-String
    ETC_FILES:
      - name: example.inv
        content:
          [win]
          {{hostname}}

          [win:vars]
          ansible_user={{user}}
          ansible_password={{password}}
          ansible_connection=winrm
          ansible_winrm_transport=ntlm
          ansible_winrm_server_cert_validation=ignore
          ansible_winrm_operation_timeout_sec={{timeout|default(30)|int - 1}}
          ansible_winrm_read_timeout_sec={{timeout|default(30)|int}}

    hostname: yoyodyne.example
    port: 5986
    user: example_user
    password: example_password
    timeout: 30
