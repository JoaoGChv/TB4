#!/bin/bash
# mapping_session.sh
#
# Abre uma sessão tmux com todos os processos necessários para
# mapeamento + gravação de rosbag + pipeline de profundidade.
#
# Layout:
#  ┌──────────────────┬──────────────────┐
#  │  SLAM toolbox    │  OAK-D driver    │
#  │  (mapa 2D)       │  (câmera RGB)    │
#  ├──────────────────┼──────────────────┤
#  │  depth_node      │  rosbag record   │
#  │  (IA depth map)  │  (grava tudo)    │
#  ├──────────────────┴──────────────────┤
#  │  Monitor (hz dos tópicos chave)     │
#  └─────────────────────────────────────┘
#
# Uso:
#   ./mapping_session.sh             # inicia a sessão
#   tmux attach -t tb4_mapping       # reconectar se desconectado
#
# Para parar tudo: Ctrl+C em cada pane, depois: tmux kill-session -t tb4_mapping

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SESSION="tb4_mapping"

# Ambiente TB4 (exportado para todos os panes)
TB4_ENV="
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export FASTRTPS_DEFAULT_PROFILES_FILE=/etc/turtlebot4/fastdds_rpi.xml
export ROS_DOMAIN_ID=0
export ROS_DISCOVERY_SERVER=';;;;127.0.0.1:11811;'
export ROS_SUPER_CLIENT=True
source /opt/ros/humble/setup.bash
source $SCRIPT_DIR/install/setup.bash
cd $SCRIPT_DIR
"

# ── Pré-checks ───────────────────────────────────────────────────────────────
echo ""
echo "=================================================="
echo "  TB4 — Sessão de Mapeamento"
echo "=================================================="

# ROS 2 ativo?
source /etc/turtlebot4/setup.bash
source /opt/ros/humble/setup.bash
if ! ros2 node list &>/dev/null; then
    echo "ERRO: ROS 2 não responde. Verifique o TB4."
    exit 1
fi

# Dockado?
IS_DOCKED=$(ros2 topic echo /robot4/dock_status --once 2>/dev/null \
    | grep "is_docked" | awk '{print $2}')
if [[ "$IS_DOCKED" == "true" ]]; then
    echo ""
    echo "  AVISO: Robô está dockado."
    echo "  Execute ./undock.sh antes de iniciar o mapeamento."
    echo ""
    read -p "  Continuar mesmo assim? (s/N): " RESP
    [[ "$RESP" =~ ^[sS]$ ]] || exit 0
fi

# Sessão já existe?
if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo ""
    echo "  Sessão '$SESSION' já existe."
    echo "  Para reconectar: tmux attach -t $SESSION"
    echo "  Para reiniciar:  tmux kill-session -t $SESSION && ./mapping_session.sh"
    exit 0
fi

echo "  Criando sessão tmux '$SESSION'..."

# ── Criar sessão tmux ────────────────────────────────────────────────────────
tmux new-session -d -s "$SESSION" -x 220 -y 50

# Pane 0 — SLAM toolbox (pane inicial)
tmux send-keys -t "$SESSION:0" "$TB4_ENV" ENTER
tmux send-keys -t "$SESSION:0" "clear && echo '[ SLAM toolbox ]'" ENTER
tmux send-keys -t "$SESSION:0" \
    "ros2 launch turtlebot4_navigation slam.launch.py namespace:=robot4 sync:=false" ENTER

# Pane 1 — OAK-D driver (split vertical direita)
tmux split-window -t "$SESSION:0" -h
tmux send-keys -t "$SESSION:0.1" "$TB4_ENV" ENTER
tmux send-keys -t "$SESSION:0.1" "clear && echo '[ OAK-D Driver ]'" ENTER
tmux send-keys -t "$SESSION:0.1" \
    "ros2 launch turtlebot4_bringup oakd.launch.py camera:=oakd_pro params_file:=$SCRIPT_DIR/config/oakd_pro_enabled.yaml namespace:=robot4" ENTER

# Pane 2 — depth_node (split horizontal esquerda baixo)
tmux select-pane -t "$SESSION:0.0"
tmux split-window -t "$SESSION:0.0" -v
tmux send-keys -t "$SESSION:0.2" "$TB4_ENV" ENTER
tmux send-keys -t "$SESSION:0.2" "clear && echo '[ depth_node — backend DUMMY ]'" ENTER
tmux send-keys -t "$SESSION:0.2" \
    "export DEPTH_BACKEND=dummy && ros2 launch tb4_depth_estimator dummy.launch.py" ENTER

# Pane 3 — rosbag record (split horizontal direita baixo)
tmux select-pane -t "$SESSION:0.1"
tmux split-window -t "$SESSION:0.1" -v
tmux send-keys -t "$SESSION:0.3" "$TB4_ENV" ENTER
tmux send-keys -t "$SESSION:0.3" "clear && echo '[ rosbag record ]'" ENTER
tmux send-keys -t "$SESSION:0.3" \
    "sleep 5 && ./record_bag.sh" ENTER

# Pane 4 — monitor (janela nova)
tmux new-window -t "$SESSION" -n monitor
tmux send-keys -t "$SESSION:monitor" "$TB4_ENV" ENTER
tmux send-keys -t "$SESSION:monitor" "clear" ENTER
tmux send-keys -t "$SESSION:monitor" "
watch -n 2 '
echo \"=== Frequências (Hz) ===\"
echo \"\"
for t in \
  /robot4/scan \
  /robot4/oakd/rgb/preview/image_raw \
  /robot4/ia/depth_map \
  /robot4/map; do
    PUB=\$(ros2 topic info \$t 2>/dev/null | grep Publisher | awk \"{print \\\$3}\")
    printf \"  pub=%-2s  %s\n\" \"\${PUB:-?}\" \"\$t\"
done
echo \"\"
echo \"=== Dock status ===\"
ros2 topic echo /robot4/dock_status --once 2>/dev/null | grep is_docked
'
" ENTER

# Voltar para janela principal
tmux select-window -t "$SESSION:0"
tmux select-pane -t "$SESSION:0.0"

echo ""
echo "  Sessão criada. Conectando..."
echo ""
echo "  Atalhos tmux:"
echo "    Ctrl+B → setas    navegar entre panes"
echo "    Ctrl+B → w        listar janelas"
echo "    Ctrl+B → d        desconectar (processos continuam)"
echo "    tmux attach -t $SESSION    reconectar"
echo ""

tmux attach -t "$SESSION"
