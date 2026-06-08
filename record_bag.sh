#!/bin/bash
# record_bag.sh
#
# Ambiente TB4 (discovery server obrigatório para ver tópicos)
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export FASTRTPS_DEFAULT_PROFILES_FILE=/etc/turtlebot4/fastdds_rpi.xml
export ROS_DOMAIN_ID=0
export ROS_DISCOVERY_SERVER=";;;;127.0.0.1:11811;"
export ROS_SUPER_CLIENT=True
source /opt/ros/humble/setup.bash
#
#
# Grava um rosbag com todos os tópicos necessários para o experimento.
# Inclui os tópicos que existem agora (câmera, LiDAR, TF) e os que
# existirão quando a Jetson estiver integrada (ia/depth_map, stereo/depth).
# Tópicos ausentes são ignorados silenciosamente pelo rosbag2.
#
# Uso:
#   chmod +x record_bag.sh
#   ./record_bag.sh                        # grava indefinidamente
#   ./record_bag.sh --duration 120         # grava por 120 segundos
#   ./record_bag.sh --max-bag-size 1073741824  # máx 1GB por arquivo
#
# Pressione SPACE para pausar/retomar, Ctrl+C para encerrar.

set -e

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BAG_NAME="experimento_tb4_${TIMESTAMP}"

echo "=================================================="
echo "  TurtleBot4 — Gravação de Rosbag"
echo "  Arquivo: ${BAG_NAME}"
echo "  Pressione SPACE para pausar | Ctrl+C para encerrar"
echo "=================================================="
echo ""

ros2 bag record \
  --output "${BAG_NAME}" \
  --max-bag-size 1073741824 \
  "$@" \
  \
  /robot4/oakd/rgb/preview/image_raw \
  /robot4/oakd/rgb/preview/camera_info \
  \
  /robot4/stereo/depth \
  \
  /robot4/ia/depth_map \
  /robot4/ia/depth_map/colorized \
  \
  /robot4/scan \
  \
  /robot4/odom \
  /robot4/imu \
  /robot4/wheel_status \
  /robot4/joint_states \
  \
  /robot4/tf \
  /robot4/tf_static \
  \
  /robot4/battery_state \
  /robot4/dock_status

echo ""
echo "Gravação encerrada. Bag salvo em: ${BAG_NAME}/"
echo ""
echo "Para inspecionar:"
echo "  ros2 bag info ${BAG_NAME}/"
