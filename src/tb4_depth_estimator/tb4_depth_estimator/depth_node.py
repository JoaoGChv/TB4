#!/usr/bin/env python3
"""
tensorrt_depth_estimator — Nó ROS 2 de estimação de profundidade monocular.

Roda na Jetson Orin (TensorRT) ou no PC de desenvolvimento (CPU/ONNX).
Subscreve a imagem RGB da OAK-D e publica o mapa de profundidade estimado.

Namespace do TB4: /robot4
  Input:  /robot4/oakd/rgb/preview/image_raw  (sensor_msgs/Image, 30 Hz, BEST_EFFORT)
  Output: /robot4/ia/depth_map                (sensor_msgs/Image, float32)
  Output: /robot4/ia/depth_map/colorized      (sensor_msgs/Image, bgr8, para RViz2)
"""

import rclpy
from rclpy.node import Node
from rclpy.qos import (
    QoSProfile,
    ReliabilityPolicy,
    HistoryPolicy,
    DurabilityPolicy,
)
from sensor_msgs.msg import Image
from cv_bridge import CvBridge

import numpy as np
import cv2
import time
import threading
import os
import sys


# ─────────────────────────────────────────────────────────────────────────────
# Backend de inferência — selecionado via variável de ambiente DEPTH_BACKEND
# DEPTH_BACKEND=tensorrt  → usa TensorRT na Jetson  (padrão em produção)
# DEPTH_BACKEND=onnx      → usa ONNX Runtime em CPU (padrão em desenvolvimento)
# DEPTH_BACKEND=dummy     → retorna mapa zerado     (para testar só o pipeline ROS)
# ─────────────────────────────────────────────────────────────────────────────

BACKEND = os.environ.get("DEPTH_BACKEND", "dummy").lower()


def load_backend(input_size: int):
    """Carrega o backend de inferência conforme DEPTH_BACKEND."""

    if BACKEND == "tensorrt":
        # Requer: repositório IRCVLab/Depth-Anything-for-Jetson-Orin clonado
        # em /ros2_ws/Depth-Anything-for-Jetson-Orin
        trt_path = "/ros2_ws/Depth-Anything-for-Jetson-Orin"
        if trt_path not in sys.path:
            sys.path.insert(0, trt_path)
        from depth import DepthAnything  # noqa: E402

        engine = DepthAnything(input_size=input_size)

        def infer(frame: np.ndarray) -> np.ndarray:
            return engine.infer(frame)

        return infer

    elif BACKEND == "onnx":
        # Requer: pip install onnxruntime
        # Modelo: depth_anything_vits14.onnx no mesmo diretório
        import onnxruntime as ort

        model_path = os.path.join(
            os.path.dirname(__file__), "depth_anything_vits14.onnx"
        )
        if not os.path.exists(model_path):
            raise FileNotFoundError(
                f"Modelo ONNX não encontrado: {model_path}\n"
                "Exporte o modelo com: python3 export.py --format onnx"
            )

        sess = ort.InferenceSession(
            model_path, providers=["CPUExecutionProvider"]
        )
        input_name = sess.get_inputs()[0].name

        def infer(frame: np.ndarray) -> np.ndarray:
            img = cv2.resize(frame, (input_size, input_size))
            img = img.astype(np.float32) / 255.0
            img = img.transpose(2, 0, 1)[np.newaxis]  # (1, 3, H, W)
            depth = sess.run(None, {input_name: img})[0].squeeze()
            return depth.astype(np.float32)

        return infer

    else:  # dummy — para testar o pipeline ROS sem modelo
        def infer(frame: np.ndarray) -> np.ndarray:
            h, w = frame.shape[:2]
            # Gradiente sintético para visualização no RViz2
            depth = np.tile(
                np.linspace(0.0, 1.0, w, dtype=np.float32), (h, 1)
            )
            return depth

        return infer


# ─────────────────────────────────────────────────────────────────────────────
# Nó principal
# ─────────────────────────────────────────────────────────────────────────────

class DepthEstimatorNode(Node):

    def __init__(self):
        super().__init__("tensorrt_depth_estimator")

        # ── Parâmetros ────────────────────────────────────────────────────
        self.declare_parameter("input_topic",  "/robot4/oakd/rgb/preview/image_raw")
        self.declare_parameter("output_topic", "/robot4/ia/depth_map")
        self.declare_parameter("input_size",   308)
        self.declare_parameter("publish_viz",  True)
        self.declare_parameter("drop_policy",  "newest")  # newest | queue

        input_topic   = self.get_parameter("input_topic").value
        output_topic  = self.get_parameter("output_topic").value
        input_size    = self.get_parameter("input_size").value
        self.pub_viz  = self.get_parameter("publish_viz").value
        drop_policy   = self.get_parameter("drop_policy").value

        # ── QoS ───────────────────────────────────────────────────────────
        # O driver depthai_ros publica com BEST_EFFORT.
        # Subscriber com RELIABLE nunca receberia nada — erro silencioso comum.
        sub_qos = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=1,
            durability=DurabilityPolicy.VOLATILE,
        )
        pub_qos = QoSProfile(
            reliability=ReliabilityPolicy.RELIABLE,
            history=HistoryPolicy.KEEP_LAST,
            depth=1,
            durability=DurabilityPolicy.VOLATILE,
        )

        # ── CV Bridge ─────────────────────────────────────────────────────
        self.bridge = CvBridge()

        # ── Backend de inferência ─────────────────────────────────────────
        self.get_logger().info(f"Carregando backend: {BACKEND.upper()}")
        try:
            self._infer = load_backend(input_size)
            self.get_logger().info("Backend carregado com sucesso.")
        except Exception as e:
            self.get_logger().fatal(f"Falha ao carregar backend: {e}")
            raise

        # ── Estado interno ────────────────────────────────────────────────
        self._lock        = threading.Lock()
        self._processing  = False
        self._drop_policy = drop_policy
        self._pending_msg = None  # usado com drop_policy=newest

        # ── Publishers ────────────────────────────────────────────────────
        self._pub_depth = self.create_publisher(Image, output_topic, pub_qos)

        if self.pub_viz:
            self._pub_colorized = self.create_publisher(
                Image, output_topic + "/colorized", pub_qos
            )

        # ── Subscriber ────────────────────────────────────────────────────
        self._sub = self.create_subscription(
            Image, input_topic, self._on_image, sub_qos
        )

        # ── Métricas ──────────────────────────────────────────────────────
        self._frames_processed = 0
        self._frames_dropped   = 0
        self._t_start          = time.monotonic()
        self._t_last_log       = time.monotonic()

        # Timer de log a cada 5 s
        self.create_timer(5.0, self._log_metrics)

        self.get_logger().info(
            f"\n{'─'*50}\n"
            f"  Backend    : {BACKEND.upper()}\n"
            f"  Input      : {input_topic}\n"
            f"  Output     : {output_topic}\n"
            f"  Input size : {input_size}px\n"
            f"  Drop policy: {drop_policy}\n"
            f"{'─'*50}"
        )

    # ── Callback de imagem ────────────────────────────────────────────────

    def _on_image(self, msg: Image):
        """
        Recebe frame da câmera.
        Drop policy 'newest': descarta o frame anterior se ainda processando.
        Drop policy 'queue' : ignora frame novo se ainda processando.
        """
        if self._drop_policy == "newest":
            self._pending_msg = msg
            if not self._processing:
                self._process(msg)
        else:  # queue
            if self._processing:
                self._frames_dropped += 1
                return
            self._process(msg)

    def _process(self, msg: Image):
        if not self._lock.acquire(blocking=False):
            self._frames_dropped += 1
            return

        self._processing = True
        t0 = time.monotonic()

        try:
            # ROS Image → numpy BGR
            frame = self.bridge.imgmsg_to_cv2(msg, desired_encoding="bgr8")

            # Inferência
            depth = self._infer(frame)  # np.float32, shape (H, W)

            # Normaliza para 0–1 se necessário
            d_min, d_max = depth.min(), depth.max()
            if d_max > d_min:
                depth_norm = (depth - d_min) / (d_max - d_min)
            else:
                depth_norm = depth

            # Publica depth map (float32, 0–1)
            depth_msg = self.bridge.cv2_to_imgmsg(
                depth_norm.astype(np.float32), encoding="32FC1"
            )
            depth_msg.header = msg.header  # preserva timestamp original
            self._pub_depth.publish(depth_msg)

            # Publica versão colorida para debug/RViz2
            if self.pub_viz:
                depth_u8    = (depth_norm * 255).astype(np.uint8)
                depth_color = cv2.applyColorMap(depth_u8, cv2.COLORMAP_INFERNO)
                viz_msg     = self.bridge.cv2_to_imgmsg(depth_color, encoding="bgr8")
                viz_msg.header = msg.header
                self._pub_colorized.publish(viz_msg)

            self._frames_processed += 1
            latency_ms = (time.monotonic() - t0) * 1000
            self.get_logger().debug(f"Inferência: {latency_ms:.1f} ms")

        except Exception as e:
            self.get_logger().error(f"Erro na inferência: {e}", throttle_duration_sec=5)

        finally:
            self._processing = False
            self._lock.release()

    # ── Log de métricas ───────────────────────────────────────────────────

    def _log_metrics(self):
        elapsed = time.monotonic() - self._t_start
        fps     = self._frames_processed / elapsed if elapsed > 0 else 0.0
        self.get_logger().info(
            f"Frames processados: {self._frames_processed} | "
            f"Dropados: {self._frames_dropped} | "
            f"FPS médio: {fps:.1f}"
        )


# ─────────────────────────────────────────────────────────────────────────────

def main(args=None):
    rclpy.init(args=args)
    node = DepthEstimatorNode()
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        pass
    finally:
        node.get_logger().info("Encerrando nó.")
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
