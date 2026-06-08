#!/bin/bash
# launch_oakd.sh
#
# Lança o container do driver OAK-D com i_publish_topic: true.
# Usar quando o container oakd não está rodando (ex: após undock).
#
# Este script substitui o container que o turtlebot4_bringup normalmente
# lançaria — usa nossa config local em vez da do sistema.
# NÃO modifica nenhum arquivo do sistema.
#
# Uso:
#   ./launch_oakd.sh          # roda em foreground (Ctrl+C para parar)
#   ./launch_oakd.sh &        # roda em background
#
# Verificar se está funcionando:
#   ros2 topic hz /robot4/oakd/rgb/preview/image_raw   # esperado: ~30 Hz

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARAMS_FILE="$SCRIPT_DIR/config/oakd_pro_enabled.yaml"

# Ambiente correto para falar com o TB4
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export FASTRTPS_DEFAULT_PROFILES_FILE=/etc/turtlebot4/fastdds_rpi.xml
export ROS_DOMAIN_ID=0
export ROS_DISCOVERY_SERVER=";;;;127.0.0.1:11811;"
export ROS_SUPER_CLIENT=True
export ROBOT_NAMESPACE=/robot4

source /opt/ros/humble/setup.bash

if [[ ! -f "$PARAMS_FILE" ]]; then
    echo "ERRO: $PARAMS_FILE não encontrado"
    exit 1
fi

echo "=================================================="
echo "  Lançando OAK-D com i_publish_topic: true"
echo "  Config: $PARAMS_FILE"
echo "  Ctrl+C para parar"
echo "=================================================="
echo ""

# Verificar se já existe um container rodando
if ps aux | grep -q "[c]omponent_container.*oakd"; then
    echo "AVISO: container oakd já está rodando. Para relaçar, pare o existente primeiro."
    exit 1
fi

exec ros2 launch turtlebot4_bringup oakd.launch.py \
    camera:=oakd_pro \
    params_file:="$PARAMS_FILE" \
    namespace:=robot4
