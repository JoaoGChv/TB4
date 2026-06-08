#!/bin/bash
# dock.sh — Retorna o robô para a doca.
# Uso: ./dock.sh

export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export FASTRTPS_DEFAULT_PROFILES_FILE=/etc/turtlebot4/fastdds_rpi.xml
export ROS_DOMAIN_ID=0
export ROS_DISCOVERY_SERVER=";;;;127.0.0.1:11811;"
export ROS_SUPER_CLIENT=True
source /opt/ros/humble/setup.bash

IS_DOCKED=$(ros2 topic echo /robot4/dock_status --once 2>/dev/null | grep "is_docked" | awk '{print $2}')

if [[ "$IS_DOCKED" == "true" ]]; then
    echo "Robô já está na doca."
    exit 0
fi

echo "Enviando comando de dock..."
ros2 action send_goal /robot4/dock irobot_create_msgs/action/Dock "{}" 2>&1
