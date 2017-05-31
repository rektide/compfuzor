---
- hosts: all
  vars:
    TYPE: samba
    INSTANCE: main
    ETC_FILES:
    - "smb.conf"
    ETC_DIRS:
    - share.d
    VAR_DIRS:
    - state
    - usershares
    - winbindd_privileged
    RUN_DIRS:
    - lock
    - ncalrpc
    - ntp_signd
    - winbindd
    CACHE_DIRS: True
    LOG_DIRS: True
    PID_DIRS: True
    SYSTEMD_EXEC: "/usr/bin/smbd -F -S -s {{ETC}}/smb.conf"

    globalOptions:
    - header: "Browsing/Identification"
    - option: workgroup
      default: "{{INSTANCE}}"
      comment:
      - "Change this to the workgroup/NT-domain name your Samba server will part of"
    - option: wins support
      example: no
      comment:
      - "Windows Internet Name Serving Support Section:"
      - "WINS Support - Tells the NMBD component of Samba to enable its WINS Server"
    - option: wins server
      example: w.x.y.z
      comment:
      - "WINS Server - Tells the NMBD components of Samba to be a WINS Client"
      - "Note: Samba can be either a WINS Server, or a WINS Client, but NOT both"
    - option: dns proxy
      default: False
      comment: "This will prevent nmbd to search for NetBIOS names through DNS."

    - header: Networking
    - option: interfaces
      example: "127.0.0.0/8 eth0"
      comment:
      - "The specific set of interfaces / networks to bind to"
      - "This can be either the interface name or an IP address/netmask;"
      - "interface names are normally preferred"
    - option: bind interfaces only
      example: yes
      comment:
      - "Only bind to the named interfaces and/or networks; you must use the"
      - "'interfaces' option above to use this."
      - "It is recommended that you enable this feature if your Samba machine is"
      - "not protected by a firewall or is a firewall itself.  However, this"
      - "option cannot handle dynamic or non-broadcast interfaces correctly."

    - header: Debugging/Accounting
    - option: log file
      default: "{{LOG}}/log.%m"
      comment: "This tells Samba to use a separate log file for each machine that connects"
    - option: max log size
      default: 1000
      comment:
      - "Cap the size of the individual log files (in KiB)."
    - option: syslog only
      example: no
      comment:
      - "If you want Samba to only log through syslog then set the following"
      - "parameter to 'yes'."
    - option: syslog
      default: 0
      comment:
      - "We want Samba to log a minimum amount of information to syslog. Everything"
      - "should go to /var/log/samba/log.{smbd,nmbd} instead. If you want to log"
      - "through syslog you should set the following parameter to something higher."
    - option: panic action
      default: /usr/share/samba/panic-action %d
      comment:
      - "Do something sensible when Samba crashes: mail the admin a backtrace"

    - header: Authentication
    - option: server role
      default: standalone server
      comment:
      - "Server role. Defines in which mode Samba will operate. Possible"
      - "values are \"standalone server\", \"member server\", \"classic primary\""
      - "\"domain controller\", \"classic backup domain controller\", \"active directory domain controller\"."
      - ""
      - "Most people will want \"standalone sever\" or \"member server\"."
      - "Running as \"active directory domain controller\" will require first"
      - "running \"samba-tool domain provision\" to wipe databases and create a"
      - "new domain."

    - option: passdb backend
      default: tdbsam
      comment:
      - "If you are using encrypted passwords, Samba will need to know what"
      - "password database type you are using.  "
    - option: obey pam restrictions
      default: True
    - option: unix password sync
      default: True
      comment:
      - "This boolean parameter controls whether Samba attempts to sync the Unix"
      - "password with the SMB password when the encrypted SMB password in the"
      - "passdb is changed."
    - option: passwd chat
      default: "*Enter\\snew\\s*\\spassword:* %n\\n *Retype\\snew\\s*\\spassword:* %n\\n *password\\supdated\\ssuccessfully* ."
      comment:
      - "For Unix password sync to work on a Debian GNU/Linux system, the following"
      - "parameters must be set (thanks to Ian Kahan <<kahan@informatik.tu-muenchen.de> for"
      - "sending the correct chat script for the passwd program in Debian Sarge)."
    - option: passwd program
      default: "/usr/bin/passwd %u"
    - option: pam password change
      default: True
      comment:
      - "This boolean controls whether PAM will be used for password changes"
      - "when requested by an SMB client instead of the program listed in"
      - "'passwd program'. The default is 'no'."
    - option: map to guest
      default: "bad user"
      comment:
      - "This option controls how unsuccessful authentication attempts are mapped"
      - "to anonymous connections"

    - header: Domains
      comment:
      - "The following settings only takes effect if 'server role = primary"
      - "classic domain controller', 'server role = backup domain controller'"
      - "or 'domain logons' is set "
    - option: logon path
      example: "\\\\%N\\profiles\\%U"
      comment:
      - "It specifies the location of the user's"
      - "profile directory from the client point of view) The following"
      - "required a [profiles] share to be setup on the samba server (see"
      - "below)"
    - option: logon path
      example: "\\\\%N\\%U\\profile"
      comment:
      - "Another common choice is storing the profile in the user's home directory"
      - "(this is Samba's default)"
    - option:  logon drive
      example: "H:"
      comment:
      - "The following setting only takes effect if 'domain logons' is set"
      - "It specifies the location of a user's home directory (from the client"
      - "point of view)"
    - option: logon home
      example: "\\\\%N\\%U"
    - option: logon script
      example: logon.cmd
      comment:
      - "The following setting only takes effect if 'domain logons' is set"
      - " It specifies the script to run during logon. The script must be stored"
      - " in the [netlogon] share"
      - " NOTE: Must be store in 'DOS' file format convention"
    - option: user script
      example: "/usr/sbin/adduser --quiet --disabled-password --gecos \"\" %u"
      comment:
      - "This allows Unix users to be created on the domain controller via the SAMR"
      - "RPC pipe.  The example command creates a user account with a disabled Unix"
      - "password; please adapt to your needs"
    - option: add machine script
      example: "/usr/sbin/useradd -g machines -c \"%u machine account\" -d /var/lib/samba -s /bin/false %u"
      comment:
      - "This allows machine accounts to be created on the domain controller via the"
      - "SAMR RPC pipe."
      - "The following assumes a \"machines\" group exists on the system"
    - option: add group script
      example: /usr/sbin/addgroup --force-badname %g
      comment: "This allows Unix groups to be created on the domain controller via the SAMR RPC pipe."

    - header: Misc
    - option: include
      example: "/home/samba/etc/smb.conf.%m"
      comment:
      - "Using the following line enables you to customise your configuration"
      - "on a per machine basis. The %m gets replaced with the netbios name"
      - "of the machine that is connecting"
    - option: idmap uid
      example: 10000-20000
      comment: "Some defaults for winbind (make sure you're not using the ranges for something else.)"
    - option: idmap gid
      example: 10000-20000
      comment:
    - option: template shell
      example: /bin/bash
    - comment: "Setup usershare options to enable non-root users to share folders usershare max shares"
    - option: usershare allow guests
      default: True
      comment:
      - "Allow users who've been granted usershare privileges to create"
      - "public shares, not just authenticated ones"

    - header: Compfuzor options
    - option: cache directory
      default: "{{CACHE}}"
    - option: state directory
      default: "{{VAR}}/state"
    - option: lock directory
      default: "{{RUN}}/lock"
    - option: ncalrpc dir
      default: "{{RUN}}/ncalrpc"
    - option: ntp signd socket directory
      default: "{{RUN}}/ntp_signd"
    - option: pid directory
      default: "{{PID}}"
    - option: usershare path
      default: "{{VAR}}/usershares"
    - option: use sendfile
      default: True
    - option: utmp
      default: True
    - option: winbindd privileged socket directory
      default: "{{VAR}}/winbindd_privileged"
    - option: winbindd socket directory
      default: "{{RUN}}/winbindd"

    shares:
    - share: overthruster
      comment: "an example. has {{VAR}} wtf"
      enable: False
      options:
      - option: path
        default: "{{VAR}}/example"
  tasks:
  - include: tasks/compfuzor.includes type="srv"
  - template:
    args:
      src: files/samba/smb.conf
      dest: "{{ETC}}/share.d/{{item.share}}.conf"
    with_items: "{{shares|default([])}}"
