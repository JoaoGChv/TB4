#!/bin/bash
# start_depth_pipeline.sh
#
# Inicia todo o pipeline de estimação de profundidade no TB4.
# Executa em ordem:
#   1. Verifica que o robô está fora da doca
#   2. Garante que o container OAK-D está rodando com i_publish_topic: true
#   3. Aguarda a câmera começar a publicar
#   4. Inicia o depth_node (backend selecionado por DEPTH_BACKEND)
#
# Uso:
#   ./start_depth_pipeline.sh                    # backend dummy (padrão)
#   DEPTH_BACKEND=onnx ./start_depth_pipeline.sh # backend ONNX
#
# Atalho para só iniciar a câmera sem o depth_node:
#   ./launch_oakd.sh &

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CAMERA_TOPIC="/robot4/oakd/rgb/preview/image_raw"
DEPTH_TOPIC="/robot4/ia/depth_map"
BACKEND="${DEPTH_BACKEND:-dummy}"

# Ambiente TB4 correto
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export FASTRTPS_DEFAULT_PROFILES_FILE=/etc/turtlebot4/fastdds_rpi.xml
export ROS_DOMAIN_ID=0
export ROS_DISCOVERY_SERVER=";;;;127.0.0.1:11811;"
export ROS_SUPER_CLIENT=True
source /opt/ros/humble/setup.bash
source "$SCRIPT_DIR/install/setup.bash"
export DEPTH_BACKEND="$BACKEND"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
info() { echo -e "  ${CYAN}→${NC} $1"; }

echo ""
echo "=================================================="
echo "  TB4 — Pipeline de Profundidade Monocular"
echo "  Backend: ${BACKEND^^}"
echo "=================================================="
echo ""

# ── Passo 1: Container OAK-D ─────────────────────────────────────────────────
echo "[ 1/3 ] Container OAK-D"

if ps aux | grep -q "[c]omponent_container.*oakd"; then
    ok "Container já está rodando"
    # Verificar se i_publish_topic está True
    PARAM_VAL=$(ros2 param get /robot4/oakd rgb.i_publish_topic 2>/dev/null || echo "")
    if echo "$PARAM_VAL" | grep -q "True"; then
        ok "i_publish_topic: True"
    else
        warn "i_publish_topic: False — setando para True..."
        if ros2 param set /robot4/oakd rgb.i_publish_topic true 2>/dev/null; then
            ok "Parâmetro atualizado (só tem efeito em novos streams)"
        fi
    fi
else
    warn "Container oakd não está rodando. Iniciando..."
    # Lança em background
    bash "$SCRIPT_DIR/launch_oakd.sh" &
    OAKD_PID=$!
    echo "  PID do container: $OAKD_PID"
    echo "  Aguardando inicialização (~10s)..."
    sleep 10
    if ps -p $OAKD_PID &>/dev/null; then
        ok "Container iniciado (PID $OAKD_PID)"
    else
        fail "Container falhou ao iniciar. Verifique se o robô está fora da doca."
        exit 1
    fi
fi
echo ""

# ── Passo 2: Aguardar câmera publicar ────────────────────────────────────────
echo "[ 2/3 ] Aguardando câmera publicar frames..."
MAX_WAIT=30
ELAPSED=0
CAMERA_OK=false

while [[ $ELAPSED -lt $MAX_WAIT ]]; do
    PUB=$(ros2 topic info "$CAMERA_TOPIC" 2>/dev/null | grep "Publisher count" | awk '{print $3}')
    if [[ "${PUB:-0}" -gt 0 ]]; then
        HZ=$(timeout 4 ros2 topic hz "$CAMERA_TOPIC" 2>/dev/null \
             | grep "average rate" | tail -1 | awk '{print $3}' | tr -d '\r')
        if [[ -n "$HZ" && "${HZ%.*}" -gt 0 ]] 2>/dev/null; then
            ok "Câmera publicando a ${HZ} Hz"
            CAMERA_OK=true
            break
        fi
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    info "Aguardando... ${ELAPSED}s / ${MAX_WAIT}s"
done

if [[ "$CAMERA_OK" == false ]]; then
    fail "Câmera não publicou em ${MAX_WAIT}s."
    warn "Verifique: robô fora da doca? Hardware OAK-D conectado?"
    warn "Para debug: ros2 topic info $CAMERA_TOPIC"
    exit 1
fi
echo ""

# ── Passo 3: Depth node ───────────────────────────────────────────────────────
echo "[ 3/3 ] Iniciando depth_node (backend: ${BACKEND^^})"
echo "  Output: $DEPTH_TOPIC"
echo "  Ctrl+C para parar"
echo ""

exec ros2 launch tb4_depth_estimator dummy.launch.py
