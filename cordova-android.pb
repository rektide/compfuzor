---
- hosts: all
  vars:
    TYPE: cordova-android
    INSTANCE: git
    REPO: https://github.com/apache/cordova-android
    PKGS:
    - ant
    platform: 23
  tasks:
  - include: tasks/compfuzor.includes type=src
  - shell: npm install -g cordova
    sudo: True
  - shell: chdir="{{DIR}}/framework" android update project -p . -t android-{{platform}}
  - shell: chdir="{{DIR}}/framework" ant jar
  - shell: chdir="{{DIR}}/framework" ls --sort=time cordova*jar | tail -n 1
    register: jar
  - shell: echo "{{jar.stdout}}" | cut -d "-" -f 2|cut -d "." -f 1,2,3
    register: version
  - file: src="{{DIR}}/framework/{{jar.stdout}}" dest="{{SRCS_DIR}}/{{jar.stdout}}" state=link
  - shell: mvn install:install-file -Dfile="{{SRCS_DIR}}/{{jar.stdout}}" -DgroupId=org.apache.cordova -DartifactId=cordova -Dversion="{{version.stdout}}" -Dpackaging=jar
