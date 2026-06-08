#!/bin/bash
# activate_camera.sh
#
# Ativa a publicação RGB da câmera OAK-D no TurtleBot4.
# Root cause: i_publish_topic: false no oakd_pro.yaml do sistema.
#
# REQUER: robô fora da doca (camera precisa estar disponível).
# NÃO modifica arquivos do sistema.
#
# Uso:
#   chmod +x activate_camera.sh
#   ./activate_camera.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CAMERA_TOPIC="/robot4/oakd/rgb/preview/image_raw"
PARAMS_FILE="$SCRIPT_DIR/config/oakd_pro_enabled.yaml"
CHECK_TIMEOUT=4

# Ambiente correto para falar com o TB4 via discovery server
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export FASTRTPS_DEFAULT_PROFILES_FILE=/etc/turtlebot4/fastdds_rpi.xml
export ROS_DOMAIN_ID=0
export ROS_DISCOVERY_SERVER=";;;;127.0.0.1:11811;"
export ROS_SUPER_CLIENT=True
source /opt/ros/humble/setup.bash

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()    { echo -e "  ${GREEN}✓${NC} $1"; }
warn()  { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail()  { echo -e "  ${RED}✗${NC} $1"; }
info()  { echo -e "  ${CYAN}→${NC} $1"; }
header(){ echo -e "\n${CYAN}[ $1 ]${NC}"; }

check_publishing() {
    local hz
    hz=$(timeout "$CHECK_TIMEOUT" ros2 topic hz "$CAMERA_TOPIC" 2>/dev/null \
        | grep "average rate" | tail -1 | awk '{print $3}' | tr -d '\r')
    [[ -n "$hz" && "${hz%.*}" -gt 0 ]] 2>/dev/null && echo "$hz" || return 1
}

echo ""
echo "=================================================="
echo "  TurtleBot4 — Ativação da Câmera OAK-D RGB"
echo "  Tópico alvo: $CAMERA_TOPIC"
echo "=================================================="

# Verifica ROS 2
if ! ros2 node list &>/dev/null; then
    fail "ROS 2 não responde."; exit 1
fi

# ── Pré-check ────────────────────────────────────────────────────────────────
header "Verificação Inicial"
if hz=$(check_publishing); then
    ok "Câmera já está publicando a ${hz} Hz — nada a fazer."; exit 0
fi

# Verificar se o container oakd está rodando
if ! ps aux | grep -q "[c]omponent_container.*oakd"; then
    fail "Container oakd NÃO está rodando."
    warn "Robô pode estar dockado ou o container crashou."
    echo ""
    echo "  Para relançar o container com i_publish_topic: true:"
    echo "    ./launch_oakd.sh &"
    echo "  Aguardar ~10s e então rodar este script novamente."
    exit 1
fi

warn "Container rodando mas câmera não publica. Tentando ativar via param set..."

# ── Estratégia A: ros2 param set direto ─────────────────────────────────────
header "Estratégia A — ros2 param set /robot4/oakd rgb.i_publish_topic true"

CURRENT=$(ros2 param get /robot4/oakd rgb.i_publish_topic 2>&1)
info "Valor atual: $CURRENT"

if echo "$CURRENT" | grep -q "True"; then
    ok "Parâmetro já está True"
else
    if ros2 param set /robot4/oakd rgb.i_publish_topic true 2>&1; then
        ok "Parâmetro definido para True"
    else
        fail "ros2 param set falhou"
        echo ""
        echo "  Diagnóstico: verificar ambiente correto:"
        echo "    export ROS_DOMAIN_ID=0"
        echo "    export ROS_DISCOVERY_SERVER=';;;;127.0.0.1:11811;'"
        echo "    export ROS_SUPER_CLIENT=True"
        exit 1
    fi
fi

# Aguarda o driver processar a mudança de parâmetro
info "Aguardando o driver processar..."
sleep 2

if hz=$(check_publishing); then
    ok "Câmera publicando a ${hz} Hz!  [Estratégia A]"; exit 0
fi

warn "Parâmetro True mas câmera ainda não publica."
warn "i_publish_topic é um parâmetro estático — requer restart do nó para ter efeito."

# ── Estratégia B: Relançar o container com config correta ────────────────────
header "Estratégia B — Relançar container com config local"
echo ""
echo "  O parâmetro i_publish_topic SÓ tem efeito na inicialização do driver."
echo "  Precisa relançar o container oakd com nossa config:"
echo ""
echo "    ./launch_oakd.sh &"
echo "    sleep 10"
echo "    ./activate_camera.sh   # verificar se funcionou"
echo ""
echo "  OU, para verificar frequência:"
echo "    ros2 topic hz /robot4/oakd/rgb/preview/image_raw"
echo ""
echo "=================================================="
echo -e "  ${YELLOW}Ação manual necessária — veja acima.${NC}"
echo "=================================================="
exit 1
