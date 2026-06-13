# tb4_ws — Workspace de Estimação de Profundidade Monocular

Workspace ROS 2 para estimação de profundidade monocular em tempo real no **TurtleBot4 Standard**, usando a câmera **Realsense D415** e os modelos **Depth Anything (ViT-S) & Monodepth2**. O nó de inferência roda na **Jetson Orin Nano** (TensorRT).

---

## Hardware

| Componente | Detalhes |
|---|---|
| Robô | TurtleBot4 Standard (namespace `/robot4`) |
| Câmera | Intel Realsense D415 (driver depthai_ros) |
| Compute IA | Jetson Orin Nano (produção) |

---

## Pré-requisitos de Software

- **ROS 2 Humble** instalado no PC (`ros-humble-desktop`)
- **colcon** para build (`python3-colcon-common-extensions`)
- PC e TB4 na mesma rede Wi-Fi com `ROS_DOMAIN_ID=0`
- `tmux` instalado (usado pelo script de sessão de mapeamento)

## Estrutura do Repositório

```
tb4_ws/
├── src/
│   └── tb4_depth_estimator/          # Pacote ROS 2 principal
│       ├── package.xml
│       ├── setup.py / setup.cfg
│       ├── launch/
│       │   ├── dummy.launch.py       # Pipeline sem modelo (teste)
│       │   ├── onnx.launch.py        # Inferência CPU/ONNX (dev)
│       │   └── tensorrt.launch.py    # Inferência GPU/TensorRT (Jetson)
│       ├── tb4_depth_estimator/
│       │   └── depth_node.py         # Nó ROS 2 principal
│       └── README.md                 # Documentação detalhada do pacote
│
├── config/
│   └── oakd_pro_enabled.yaml         # Config OAK-D com i_publish_topic: true
│
├── activate_camera.sh    # Ativa publicação RGB da OAK-D (sem reiniciar driver)
├── check_system.sh       # Verifica se todos os tópicos estão publicando
├── dock.sh               # Retorna o robô para a doca
├── undock.sh             # Desacopla o robô da doca
├── launch_oakd.sh        # Lança o driver OAK-D com config local
├── start_depth_pipeline.sh  # Sobe câmera + depth_node de uma vez
├── mapping_session.sh    # Sessão tmux completa: SLAM + câmera + depth + bag
├── record_bag.sh         # Grava rosbag com todos os tópicos do experimento
├── save_map.sh           # Salva o mapa gerado pelo SLAM em maps/
│
├── build/                # Gerado por colcon build (git-ignorado)
├── install/              # Gerado por colcon build (git-ignorado)
└── log/                  # Logs de build (git-ignorado)
```

---

## Build

```bash
cd ~/tb4_ws

# Instalar dependências ROS
rosdep install --from-paths src --ignore-src -r -y

# Compilar
colcon build --symlink-install

# Sourcear o workspace
source install/setup.bash
```

---

## Fluxo de Trabalho

### 1. Verificar o sistema

Antes de qualquer experimento, confirme que câmera, LiDAR e odometria estão publicando:

```bash
./check_system.sh
```

Saída esperada:
```
✓ ROS 2 ativo — N nós rodando
✓ Container Realsense está rodando
✓ /robot4/realsense/rgb/preview/image_raw
✓ /robot4/scan
✓ /robot4/odom
✓ Câmera: 30.0 Hz
✓ QoS: BEST_EFFORT
```

---

### 2. Desacoplar o robô (obrigatório para câmera funcionar)

```bash
./undock.sh
```

---

### 3. Ativar a câmera Realsense-D415

O driver librealsense da câmera D415 vem com `i_publish_topic: false` por padrão. Este script ativa a publicação sem reiniciar o driver:

```bash
./activate_camera.sh
```

Se o script indicar que é necessário relançar o driver, use:

```bash
./launch_oakd.sh &
sleep 10
./activate_camera.sh
```

---

### 4. Testar o pipeline de profundidade

**Modo dummy** — valida o pipeline ROS sem nenhum modelo de IA:

```bash
source install/setup.bash
ros2 launch tb4_depth_estimator dummy.launch.py
```

Verificar output em outro terminal:

```bash
ros2 topic hz /robot4/ia/depth_map          # esperado: ~30 Hz
ros2 topic hz /robot4/ia/depth_map/colorized
```

Visualizar no RViz2:
```bash
rviz2
# Adicionar: Image → /robot4/ia/depth_map/colorized
```

---

### 5. Pipeline completo (câmera + depth em um comando)

```bash
./start_depth_pipeline.sh                    # backend dummy (padrão)
DEPTH_BACKEND=onnx ./start_depth_pipeline.sh # backend ONNX (requer modelo)
```

---

### 6. Sessão de mapeamento completa (tmux)

Abre automaticamente SLAM + driver OAK-D + depth_node + rosbag em panes separados:

```bash
./mapping_session.sh
```

Layout dos panes:
```
┌──────────────────┬──────────────────┐
│  SLAM toolbox    │  OAK-D driver    │
│  (mapa 2D)       │  (câmera RGB)    │
├──────────────────┼──────────────────┤
│  depth_node      │  rosbag record   │
│  (IA depth map)  │  (grava tudo)    │
├──────────────────┴──────────────────┤
│  Monitor (hz dos tópicos chave)     │
└─────────────────────────────────────┘
```

Atalhos tmux:
- `Ctrl+B → setas` — navegar entre panes
- `Ctrl+B → d` — desconectar (processos continuam rodando)
- `tmux attach -t tb4_mapping` — reconectar

---

### 7. Gravar rosbag

```bash
./record_bag.sh                        # grava indefinidamente
./record_bag.sh --duration 120         # grava por 120 segundos
```

Tópicos gravados: imagem RGB, depth map, LiDAR, odometria, IMU, TF, bateria, dock status.

---

### 8. Salvar mapa SLAM

```bash
./save_map.sh                          # nome automático com timestamp
./save_map.sh mapa_sala_a              # nome customizado
```

Gera `maps/<nome>.pgm` e `maps/<nome>.yaml`.

---

### 9. Retornar para a doca

```bash
./dock.sh
```

---

## Backends de Inferência

Selecionado via variável de ambiente `DEPTH_BACKEND` (padrão: `dummy`):

| Backend | Onde roda | Quando usar |
|---|---|---|
| `dummy` | Qualquer máquina | Validar pipeline ROS sem modelo |
| `onnx` | PC com CPU | Desenvolvimento — validar modelo antes da Jetson |
| `tensorrt` | Jetson Orin | Produção — inferência otimizada na GPU |

```bash
# Exemplos
DEPTH_BACKEND=dummy    ros2 launch tb4_depth_estimator dummy.launch.py
DEPTH_BACKEND=onnx     ros2 launch tb4_depth_estimator onnx.launch.py
DEPTH_BACKEND=tensorrt ros2 launch tb4_depth_estimator tensorrt.launch.py
```

---

## Tópicos ROS

| Direção | Tópico | Tipo | QoS |
|---|---|---|---|
| Input | `/robot4/oakd/rgb/preview/image_raw` | `sensor_msgs/Image` | BEST_EFFORT |
| Output | `/robot4/ia/depth_map` | `sensor_msgs/Image` (float32) | RELIABLE |
| Output | `/robot4/ia/depth_map/colorized` | `sensor_msgs/Image` (bgr8) | RELIABLE |

> **Atenção QoS**: o driver depthai_ros publica com `BEST_EFFORT`. Um subscriber `RELIABLE` nunca recebe nada — o depth_node já usa `BEST_EFFORT` no subscriber para evitar esse problema silencioso.

---

## Parâmetros do Nó

| Parâmetro | Padrão | Descrição |
|---|---|---|
| `input_topic` | `/robot4/oakd/rgb/preview/image_raw` | Tópico de entrada |
| `output_topic` | `/robot4/ia/depth_map` | Tópico de saída |
| `input_size` | `308` | Resolução de entrada do modelo (px) |
| `publish_viz` | `true` | Publica versão colorida para RViz2 |
| `drop_policy` | `newest` | `newest`: descarta frame antigo se ocupado; `queue`: descarta frame novo |

---

## Deploy na Jetson Orin

```bash
# Dentro do container Docker na Jetson:
cd /ros2_ws
git clone https://github.com/IRCVLab/Depth-Anything-for-Jetson-Orin.git

cd /ros2_ws/tb4_ws
colcon build --symlink-install
source install/setup.bash

DEPTH_BACKEND=tensorrt ros2 launch tb4_depth_estimator tensorrt.launch.py
```
