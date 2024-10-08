# TODO: turn this docker-compose into a podman container service or something
# systemd container

# version: "3"
services:
  vrising:
    image: docker.io/didstopia/vrising-server:latest
    #build: .
    container_name: vrising-primus
    restart: unless-stopped
    #restart: "no"
    environment:
      # Configure the server
      V_RISING_SERVER_PERSISTENT_DATA_PATH: "/app/vrising"
      V_RISING_SERVER_BRANCH: "public"
      V_RISING_SERVER_START_MODE: "0" # Install/update and start server
      # V_RISING_SERVER_START_MODE: "1" # Install/update and exit
      ##V_RISING_SERVER_START_MODE: "2" # Install, skip update check and start server
      V_RISING_SERVER_UPDATE_MODE: "1" # Enable update checking

      # Customize the server
      V_RISING_SERVER_NAME: "XDying XDead XDoom"
      V_RISING_SERVER_DESCRIPTION: "All the legions endless space"
      V_RISING_SERVER_GAME_PORT: 9876
      V_RISING_SERVER_QUERY_PORT: 9877
      V_RISING_SERVER_RCON_PORT: 9878
      V_RISING_SERVER_RCON_ENABLED: true
      V_RISING_SERVER_RCON_PASSWORD: "r00mc0nr00k"
      V_RISING_SERVER_MAX_CONNECTED_USERS: 20
      V_RISING_SERVER_MAX_CONNECTED_ADMINS: 6
      V_RISING_SERVER_SAVE_NAME: "xdying"
      V_RISING_SERVER_PASSWORD: "xxxdddxxx"
      #V_RISING_SERVER_LIST_ON_MASTER_SERVER: false
      V_RISING_SERVER_LIST_ON_MASTER_SERVER: true
      V_RISING_SERVER_LIST_ON_STEAM: true
      V_RISING_SERVER_LIST_ON_EOS: false
      V_RISING_SERVER_AUTO_SAVE_COUNT: 20
      V_RISING_SERVER_AUTO_SAVE_INTERVAL: 5
      V_RISING_SERVER_GAME_SETTINGS_PRESET: "StandardPvE"

    ports:
      - "9876:9876/udp"
      - "9877:9877/udp"
      - "9878:9878/tcp"

    volumes:
      - /opt/vrising/saves:/app/vrising
      - /opt/vrising/data:/steamcmd/vrising
      #- ./vrising_saves:/app/vrising
      #- ./vrising_data:/steamcmd/vrising
      # - vrising_saves:/app/vrising_test
      # - vrising_data:/steamcmd/vrising

# volumes:
#   vrising_saves:
#     driver: local
#   vrising_data:
#     driver: local
