#!/bin/bash
# check_system.sh
#
# Verifica se todos os tópicos necessários estão publicando
# antes de iniciar uma sessão de gravação ou experimento.
#
# Uso:
#   chmod +x check_system.sh
#   ./check_system.sh

set -e

# ── Ambiente ROS 2 (TB4 usa discovery server na porta 11811) ──────────────────
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
export FASTRTPS_DEFAULT_PROFILES_FILE=/etc/turtlebot4/fastdds_rpi.xml
export ROS_DOMAIN_ID=0
export ROS_DISCOVERY_SERVER=";;;;127.0.0.1:11811;"
export ROS_SUPER_CLIENT=True
source /opt/ros/humble/setup.bash

# ── Configuração ──────────────────────────────────────────────────────────────

NAMESPACE="/robot4"
REQUIRED_TOPICS=(
    "${NAMESPACE}/oakd/rgb/preview/image_raw"
    "${NAMESPACE}/scan"
    "${NAMESPACE}/odom"
    "${NAMESPACE}/imu"
    "${NAMESPACE}/tf"
    "${NAMESPACE}/tf_static"
)

OPTIONAL_TOPICS=(
    "${NAMESPACE}/stereo/depth"
    "${NAMESPACE}/ia/depth_map"
    "${NAMESPACE}/oakd/rgb/preview/camera_info"
)

HZ_TIMEOUT=3  # segundos para medir frequência

# ── Cores ─────────────────────────────────────────────────────────────────────

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
warn() { echo -e "  ${YELLOW}⚠${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }

# ── Funções ───────────────────────────────────────────────────────────────────

check_topic_exists() {
    local topic=$1
    ros2 topic list 2>/dev/null | grep -q "^${topic}$"
}

check_topic_hz() {
    local topic=$1
    # Tenta medir a frequência por HZ_TIMEOUT segundos
    local hz
    hz=$(timeout ${HZ_TIMEOUT} ros2 topic hz "${topic}" 2>/dev/null \
        | grep "average rate" | tail -1 | awk '{print $3}' | tr -d '\r')
    echo "${hz:-0}"
}

# ── Main ──────────────────────────────────────────────────────────────────────

echo ""
echo "=================================================="
echo "  TurtleBot4 — Verificação de Sistema"
echo "  Namespace: ${NAMESPACE}"
echo "=================================================="
echo ""

# Verifica ROS 2 ativo
echo "[ ROS 2 ]"
if ros2 node list &>/dev/null; then
    NODE_COUNT=$(ros2 node list 2>/dev/null | wc -l)
    ok "ROS 2 ativo — ${NODE_COUNT} nós rodando"
else
    fail "ROS 2 não responde. Verifique a conexão com o TB4."
    exit 1
fi
echo ""

# Verifica container oakd
echo "[ Container OAK-D ]"
if ps aux | grep -q "[c]omponent_container.*oakd"; then
    ok "Container oakd está rodando"
else
    fail "Container oakd NÃO está rodando"
    warn "Para iniciar: ./launch_oakd.sh &   (fora da doca)"
    ALL_OK=false
fi
echo ""

# Verifica tópicos obrigatórios
echo "[ Tópicos Obrigatórios ]"
ALL_OK=true
for topic in "${REQUIRED_TOPICS[@]}"; do
    if check_topic_exists "${topic}"; then
        ok "${topic}"
    else
        fail "${topic} — NÃO ENCONTRADO"
        ALL_OK=false
    fi
done
echo ""

# Verifica tópicos opcionais
echo "[ Tópicos Opcionais ]"
for topic in "${OPTIONAL_TOPICS[@]}"; do
    if check_topic_exists "${topic}"; then
        ok "${topic}"
    else
        warn "${topic} — não publicando (OK por agora)"
    fi
done
echo ""

# Verifica frequência da câmera
echo "[ Frequência da Câmera ]"
CAM_TOPIC="${NAMESPACE}/oakd/rgb/preview/image_raw"
echo "  Medindo por ${HZ_TIMEOUT}s..."
HZ=$(check_topic_hz "${CAM_TOPIC}")

if [ -z "${HZ}" ] || [ "${HZ}" = "0" ]; then
    fail "Câmera não está publicando"
    warn "Robô está dockado? Desacople e tente novamente."
    ALL_OK=false
else
    # Verifica se está próximo de 30 Hz
    HZ_INT=${HZ%.*}
    if [ "${HZ_INT}" -ge 25 ] && [ "${HZ_INT}" -le 35 ]; then
        ok "Câmera: ${HZ} Hz (esperado ~30 Hz)"
    else
        warn "Câmera: ${HZ} Hz (esperado ~30 Hz — verifique carga da RPi4)"
    fi
fi
echo ""

# Verifica QoS da câmera
echo "[ QoS da Câmera ]"
QOS_INFO=$(ros2 topic info "${CAM_TOPIC}" --verbose 2>/dev/null | grep "Reliability" | head -1)
if echo "${QOS_INFO}" | grep -q "BEST_EFFORT"; then
    ok "QoS: BEST_EFFORT (correto — subscriber deve usar BEST_EFFORT)"
elif echo "${QOS_INFO}" | grep -q "RELIABLE"; then
    warn "QoS: RELIABLE (subscriber pode usar RELIABLE ou BEST_EFFORT)"
else
    warn "QoS: não determinado"
fi
echo ""

# Resultado final
echo "=================================================="
if [ "${ALL_OK}" = true ]; then
    echo -e "  ${GREEN}SISTEMA OK — pronto para gravar${NC}"
    echo ""
    echo "  Próximo passo:"
    echo "    ./record_bag.sh"
else
    echo -e "  ${RED}ATENÇÃO — verifique os itens marcados com ✗${NC}"
fi
echo "=================================================="
echo ""
