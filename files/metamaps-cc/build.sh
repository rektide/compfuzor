#!/bin/sh

cd "{{DIR}}/repo"

sed -i "s/ruby '2\.1\..'/ruby '2.1.5'/" Gemfile
cp config/database.yml.default config/database.yml
sed -i "s/  host:.*/  host: {{pg_host}}/" config/database.yml
sed -i "s/  port:.*/  port: {{pg_port}}/" config/database.yml
sed -i "s/  database:.*/  database: {{pg_db}}/" config/database.yml
sed -i "s/  username: postgres/  username: {{pg_user}}/" config/database.yml
sed -i "s/  password:.*/  password: {{pg_pw}}/" config/database.yml

bundle install

#rake db:create
rake db:schema:load
rake db:fixtures:load

cd realtime
npm install
