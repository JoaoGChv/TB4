#!/bin/bash
# save_map.sh — Salva o mapa gerado pelo SLAM.
# Uso: ./save_map.sh [nome_do_mapa]
#
# Gera dois arquivos:
#   <nome>.pgm  — imagem do mapa (preto/branco)
#   <nome>.yaml — metadados (resolução, origem, etc.)

export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export FASTRTPS_DEFAULT_PROFILES_FILE=/etc/turtlebot4/fastdds_rpi.xml
export ROS_DOMAIN_ID=0
export ROS_DISCOVERY_SERVER=";;;;127.0.0.1:11811;"
export ROS_SUPER_CLIENT=True
source /opt/ros/humble/setup.bash

MAP_NAME="${1:-mapa_$(date +%Y%m%d_%H%M%S)}"
SAVE_DIR="$(cd "$(dirname "$0")" && pwd)/maps"
mkdir -p "$SAVE_DIR"
MAP_PATH="$SAVE_DIR/$MAP_NAME"

echo "Salvando mapa em: $MAP_PATH"

# Salvar via nav2_map_server
ros2 run nav2_map_server map_saver_cli \
    -f "$MAP_PATH" \
    --ros-args \
    -r /map:=/robot4/map \
    2>&1

echo ""
echo "Arquivos gerados:"
ls -lh "${MAP_PATH}.pgm" "${MAP_PATH}.yaml" 2>/dev/null
