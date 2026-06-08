"""
launch/tensorrt.launch.py

Sobe o nó de inferência com backend TensorRT.
Usado em produção na Jetson Orin.

Pré-requisito:
    Repositório IRCVLab/Depth-Anything-for-Jetson-Orin clonado em
    /ros2_ws/Depth-Anything-for-Jetson-Orin com modelo exportado.

Uso (dentro do container Docker na Jetson):
    DEPTH_BACKEND=tensorrt ros2 launch tb4_depth_estimator tensorrt.launch.py
"""

from launch import LaunchDescription
from launch_ros.actions import Node
from launch.actions import SetEnvironmentVariable


def generate_launch_description():
    return LaunchDescription([

        SetEnvironmentVariable("DEPTH_BACKEND", "tensorrt"),

        Node(
            package="tb4_depth_estimator",
            executable="depth_node",
            name="tensorrt_depth_estimator",
            namespace="",
            output="screen",
            emulate_tty=True,
            parameters=[{
                "input_topic":  "/robot4/oakd/rgb/preview/image_raw",
                "output_topic": "/robot4/ia/depth_map",
                "input_size":   308,
                "publish_viz":  True,
                "drop_policy":  "newest",
            }],
        ),
    ])
