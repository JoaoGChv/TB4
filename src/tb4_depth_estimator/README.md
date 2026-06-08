# tb4_depth_estimator

Nó ROS 2 de estimação de profundidade monocular para **TurtleBot4 Standard + Jetson Orin Nano**.

Subscreve a imagem RGB da OAK-D e publica um mapa de profundidade estimado por deep learning.

---

## Estrutura do workspace

```
tb4_ws/
├── check_system.sh                  ← verifica se o TB4 está ok antes de gravar
├── record_bag.sh                    ← grava rosbag de experimento
└── src/
    └── tb4_depth_estimator/
        ├── package.xml
        ├── setup.py
        ├── setup.cfg
        ├── resource/
        │   └── tb4_depth_estimator
        ├── config/                  ← (reservado para parâmetros futuros)
        ├── launch/
        │   ├── dummy.launch.py      ← teste de pipeline sem modelo (usar agora)
        │   ├── onnx.launch.py       ← inferência CPU com ONNX (desenvolvimento)
        │   └── tensorrt.launch.py   ← inferência GPU com TensorRT (produção Jetson)
        └── tb4_depth_estimator/
            ├── __init__.py
            └── depth_node.py        ← nó principal
```

---

## Backends disponíveis

| Backend | Onde roda | Quando usar |
|---|---|---|
| `dummy` | Qualquer máquina | Agora — valida o pipeline ROS sem modelo |
| `onnx` | PC com CPU | Desenvolvimento — valida o modelo antes da Jetson |
| `tensorrt` | Jetson Orin | Produção — inferência otimizada com GPU |

Seleção via variável de ambiente `DEPTH_BACKEND` (padrão: `dummy`).

---

## Tópicos

| Direção | Tópico | Tipo | QoS |
|---|---|---|---|
| Input | `/robot4/oakd/rgb/preview/image_raw` | `sensor_msgs/Image` | BEST_EFFORT |
| Output | `/robot4/ia/depth_map` | `sensor_msgs/Image` (float32) | BEST_EFFORT |
| Output | `/robot4/ia/depth_map/colorized` | `sensor_msgs/Image` (bgr8) | BEST_EFFORT |

---

## Passo 1 — Configurar o PC

```bash
# Instalar ROS 2 Humble (se ainda não tiver)
sudo apt install -y ros-humble-desktop python3-colcon-common-extensions

# Configurar domínio igual ao TB4
echo "export ROS_DOMAIN_ID=0" >> ~/.bashrc
echo "source /opt/ros/humble/setup.bash" >> ~/.bashrc
source ~/.bashrc

# Verificar que o PC vê os tópicos do TB4 (precisa estar na mesma rede WiFi)
ros2 topic list | grep robot4
```

---

## Passo 2 — Compilar o pacote

```bash
cd ~/tb4_ws

# Instalar dependências
rosdep install --from-paths src --ignore-src -r -y

# Compilar
colcon build --symlink-install

# Sourcear
source install/setup.bash
```

---

## Passo 3 — Verificar o sistema

```bash
cd ~/tb4_ws
chmod +x check_system.sh
./check_system.sh
```

Saída esperada:
```
✓ ROS 2 ativo — N nós rodando
✓ /robot4/oakd/rgb/preview/image_raw
✓ /robot4/scan
✓ /robot4/odom
✓ /robot4/imu
✓ Câmera: 30.0 Hz
✓ QoS: BEST_EFFORT
```

---

## Passo 4 — Testar o pipeline (modo dummy)

Sem modelo, sem Jetson. Valida que o nó sobe, subscreve e publica corretamente.

```bash
# Terminal 1 — subir o nó
cd ~/tb4_ws
source install/setup.bash
ros2 launch tb4_depth_estimator dummy.launch.py

# Terminal 2 — verificar output
ros2 topic hz /robot4/ia/depth_map
# Esperado: ~30 Hz (acompanha a câmera)

ros2 topic hz /robot4/ia/depth_map/colorized
# Esperado: ~30 Hz

# Visualizar no RViz2
rviz2
# Adicionar display: Image → /robot4/ia/depth_map/colorized
```

---

## Passo 5 — Gravar rosbag baseline

Com o robô desacoplado e se movendo pelo ambiente de experimento:

```bash
cd ~/tb4_ws
chmod +x record_bag.sh
./record_bag.sh
```

Mova o robô por 2–3 minutos. Pressione Ctrl+C para encerrar.

```bash
# Inspecionar o bag gravado
ros2 bag info experimento_tb4_YYYYMMDD_HHMMSS/
```

---

## Passo 6 — Testar com modelo ONNX (desenvolvimento, sem Jetson)

```bash
# Instalar ONNX Runtime
pip install onnxruntime

# Exportar modelo (na máquina com o repositório IRCVLab)
cd ~/Depth-Anything-for-Jetson-Orin
python3 export.py --weights LiheYoung/depth_anything_vits14 --format onnx

# Copiar modelo para o pacote
cp depth_anything_vits14.onnx ~/tb4_ws/src/tb4_depth_estimator/tb4_depth_estimator/

# Subir o nó com ONNX
cd ~/tb4_ws
source install/setup.bash
ros2 launch tb4_depth_estimator onnx.launch.py
```

---

## Passo 7 — Deploy na Jetson (quando chegar)

```bash
# Dentro do container Docker na Jetson:
cd /ros2_ws
git clone https://github.com/IRCVLab/Depth-Anything-for-Jetson-Orin.git

# Compilar o pacote
cd /ros2_ws/tb4_ws
colcon build --symlink-install
source install/setup.bash

# Subir com TensorRT
DEPTH_BACKEND=tensorrt ros2 launch tb4_depth_estimator tensorrt.launch.py
```

---

## Parâmetros do nó

| Parâmetro | Padrão | Descrição |
|---|---|---|
| `input_topic` | `/robot4/oakd/rgb/preview/image_raw` | Tópico de entrada |
| `output_topic` | `/robot4/ia/depth_map` | Tópico de saída |
| `input_size` | `308` | Resolução de entrada do modelo (px) |
| `publish_viz` | `true` | Publica versão colorida para RViz2 |
| `drop_policy` | `newest` | `newest`: descarta frame antigo se ocupado; `queue`: descarta frame novo |

---

## Problemas conhecidos

| Problema | Causa | Solução |
|---|---|---|
| Subscriber não recebe nada | QoS incompatível | Câmera usa BEST_EFFORT — subscriber deve usar o mesmo |
| Câmera para de publicar | Robô está dockado | Desacople o robô da estação de carregamento |
| `ros2 topic list` vazio | ROS_DOMAIN_ID errado | Garantir `ROS_DOMAIN_ID=0` no PC e no TB4 |
| Latência alta no modo ONNX | CPU sem aceleração | Normal em CPU — esperado 1–5 FPS; use Jetson para produção |
