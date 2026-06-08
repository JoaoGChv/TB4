from setuptools import setup
import os
from glob import glob

package_name = "tb4_depth_estimator"

setup(
    name=package_name,
    version="0.1.0",
    packages=[package_name],
    data_files=[
        ("share/ament_index/resource_index/packages", [f"resource/{package_name}"]),
        (f"share/{package_name}", ["package.xml"]),
        (f"share/{package_name}/launch", glob("launch/*.launch.py")),
        (f"share/{package_name}/config", glob("config/*.yaml")),
    ],
    install_requires=["setuptools"],
    zip_safe=True,
    maintainer="CPQD",
    maintainer_email="viniciusc@cpqd.com.br",
    description="Nó de estimação de profundidade para TurtleBot4 + Jetson Orin",
    license="MIT",
    entry_points={
        "console_scripts": [
            "depth_node = tb4_depth_estimator.depth_node:main",
        ],
    },
)
