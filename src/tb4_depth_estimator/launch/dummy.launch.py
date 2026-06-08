"""
launch/dummy.launch.py

Sobe o nó de inferência em modo DUMMY — sem modelo real.
Publica um gradiente sintético como depth map para validar
o pipeline ROS end-to-end antes da Jetson chegar.

Uso:
    DEPTH_BACKEND=dummy ros2 launch tb4_depth_estimator dummy.launch.py

Ou simplesmente:
    ros2 launch tb4_depth_estimator dummy.launch.py
(DEPTH_BACKEND=dummy é o padrão)
"""

from launch import LaunchDescription
from launch_ros.actions import Node
from launch.actions import SetEnvironmentVariable


def generate_launch_description():
    return LaunchDescription([

        # Força o backend dummy (gradiente sintético, sem modelo)
        SetEnvironmentVariable("DEPTH_BACKEND", "dummy"),

        Node(
            package="tb4_depth_estimator",
            executable="depth_node",
            name="tensorrt_depth_estimator",
            namespace="",          # nó roda fora do namespace /robot4
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
