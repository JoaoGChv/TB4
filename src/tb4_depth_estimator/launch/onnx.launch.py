"""
launch/onnx.launch.py

Sobe o nó de inferência com backend ONNX Runtime em CPU.
Usado para desenvolvimento e validação do modelo no PC,
antes da Jetson estar disponível.

Pré-requisito:
    pip install onnxruntime
    # Modelo ONNX em: tb4_depth_estimator/depth_anything_vits14.onnx

Uso:
    DEPTH_BACKEND=onnx ros2 launch tb4_depth_estimator onnx.launch.py
"""

from launch import LaunchDescription
from launch_ros.actions import Node
from launch.actions import SetEnvironmentVariable


def generate_launch_description():
    return LaunchDescription([

        SetEnvironmentVariable("DEPTH_BACKEND", "onnx"),

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
