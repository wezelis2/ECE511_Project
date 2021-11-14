#!/bin/bash

if [ "$#" -ne 3 ]; then
    echo "Illegal number of parameters"
    echo "Usage: ./champsim_full_run.sh [l1d_pref] [l2c_pref] [llc_pref]"
    exit 1
fi

# ChampSim configuration
L1D_PREFETCHER=$1
L2C_PREFETCHER=$2
LLC_PREFETCHER=$3

############## Some useful macros ###############
BOLD=$(tput bold)
NORMAL=$(tput sgr0)
#################################################

./build_champsim.sh bimodal next_line ${L1D_PREFETCHER} ${L2C_PREFETCHER} ${LLC_PREFETCHER} lru 1

retVal=$?
if [ $retVal -ne 0 ]; then
    echo "[ERROR] encountered error while running build"
    exit 1
fi

BINARY_NAME="bimodal-next_line-${L1D_PREFETCHER}-${L2C_PREFETCHER}-${LLC_PREFETCHER}-lru-1core"

WARMUP="1"
SIM="10"

TRACE=("403.gcc-16B.champsimtrace.xz" \
        "649.fotonik3d_s-1B.champsimtrace.xz")

for i in "${TRACE[@]}"
do
    echo -n "Running trace $i ... "

    ./run_champsim.sh ${BINARY_NAME} ${WARMUP} ${SIM} $i

    retVal=$?
    if [ $retVal -ne 0 ]; then
        echo "[ERROR] encountered error while running trace $i"
        exit 1
    fi

    echo "Done "
done




