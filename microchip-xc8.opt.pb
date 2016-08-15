---
- hosts: all
  vars:
    TYPE: microchip-xc8
    INSTANCE: main
    GET_URLS:
    # recent
    - "http://www.microchip.com/mplabxc8linux"
    - "http://ww1.microchip.com/downloads/en/softwarelibrary/mla_v2016_04_27_linux_installer.run"
    # colorhug
    - "http://ww1.microchip.com/downloads/en/DeviceDoc/xc8-v1.34-full-install-linux-installer.run"
    - "https://bitbucket.org/simbuckone/simbuckbaseproject/downloads/mplabc18-v3.40-linux-full-installer.run"
    - "http://ww1.microchip.com/downloads/en/softwarelibrary/microchip-libraries-for-applications-v2013-06-15-linux-installer.run"


    # misc pic18
    #- "ftp://Compilers-RO:C0mP!0511@ftp.microchip.com/HI-TECH%20C%20for%20PIC18%20(PRO)/picc-18-pro_9.66-linux.run"
    #- "ftp://Compilers-RO:C0mP!0511@ftp.microchip.com/HI-TECH%20C%20for%20PIC18%20(Standard)/picc-18-std_9.52-linux.run"
    # misc pic32/24
    #- "ftp://Compilers-RO:C0mP!0511@ftp.microchip.com/HI-TECH%20C%20for%20PIC32/HCPIC32-9.60PL2-linux.run"
    #- "ftp://Compilers-RO:C0mP!0511@ftp.microchip.com/HI-TECH%20C%20for%20dsPIC-PIC24/HCDSPIC-std-9.60PL3-linux.run"
    #- "ftp://Compilers-RO:C0mP!0511@ftp.microchip.com/HI-TECH%20C%20for%20PIC10-12-16%20(PRO%20and%20Standard)/picc-9_82-linux.run"
    #- "ftp://Compilers-RO:C0mP!0511@ftp.microchip.com/HI-TECH%20C%20for%20PIC10-12-16%20(PRO%20and%20Standard)/picc-pro_9.80a-linux.run"
    #- "http://www.microchip.com/mplabx-ide-linux-installer"

    # older misc
    #- "ftp://Compilers-RO:C0mP!0511@ftp.microchip.com/HI-TECH%20C%20for%20PIC18%20(PRO)/HCPIC18-pro-9.63PL3-linux.run"
    #- "ftp://Compilers-RO:C0mP!0511@ftp.microchip.com/HI-TECH%20C%20for%20PIC18%20(Standard)/HCPIC18-std-9.50PL3-linux.run"
    PKGS:
    - libc6-i386
  tasks:
  - include: tasks/compfuzor.includes
