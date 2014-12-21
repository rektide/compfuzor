# http://gis.stackexchange.com/questions/14432/how-to-migrate-gdb-data-into-postgis-without-esri-apps
---
- hosts: all
  gather_facts: False
  vars:
    TYPE: geo
    INSTANCE: dc
    VAR_URLS:
      dc_east: http://ims.er.usgs.gov/gda_services/download?item_id=6051346
      dc_west: http://ims.er.usgs.gov/gda_services/download?item_id=6050207
      nbd: ftp://rockyftp.cr.usgs.gov/vdelivery/Datasets/Staged/GovtUnit/Shape/GOVTUNIT_11_District_of_Columbia_GU_STATEORTERRITORY.zip
      gnis: http://geonames.usgs.gov/docs/stategaz/DC_Features.zip
      ned: ftp://rockyftp.cr.usgs.gov/vdelivery/Datasets/Staged/NED/19/IMG/ned19_n39x50_w077x75_md_washingtonco_2012.zip
   tasks:
   - include: tasks/compfuzor.includes
