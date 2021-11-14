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

TRACE=("400.perlbench-41B.champsimtrace.xz     " \
        "400.perlbench-50B.champsimtrace.xz     " \
        "401.bzip2-226B.champsimtrace.xz        " \
        "401.bzip2-277B.champsimtrace.xz        " \
        "401.bzip2-38B.champsimtrace.xz         " \
        "401.bzip2-7B.champsimtrace.xz          " \
        "403.gcc-16B.champsimtrace.xz           " \
        "403.gcc-17B.champsimtrace.xz           " \
        "403.gcc-48B.champsimtrace.xz           " \
        "410.bwaves-1963B.champsimtrace.xz      " \
        "410.bwaves-2097B.champsimtrace.xz      " \
        "410.bwaves-945B.champsimtrace.xz       " \
        "416.gamess-875B.champsimtrace.xz       " \
        "429.mcf-184B.champsimtrace.xz          " \
        "429.mcf-192B.champsimtrace.xz          " \
        "429.mcf-217B.champsimtrace.xz          " \
        "429.mcf-22B.champsimtrace.xz           " \
        "429.mcf-51B.champsimtrace.xz           " \
        "433.milc-127B.champsimtrace.xz         " \
        "433.milc-274B.champsimtrace.xz         " \
        "433.milc-337B.champsimtrace.xz         " \
        "434.zeusmp-10B.champsimtrace.xz        " \
        "435.gromacs-111B.champsimtrace.xz      " \
        "435.gromacs-134B.champsimtrace.xz      " \
        "435.gromacs-226B.champsimtrace.xz      " \
        "435.gromacs-228B.champsimtrace.xz      " \
        "436.cactusADM-1804B.champsimtrace.xz   " \
        "437.leslie3d-134B.champsimtrace.xz     " \
        "437.leslie3d-149B.champsimtrace.xz     " \
        "437.leslie3d-232B.champsimtrace.xz     " \
        "437.leslie3d-265B.champsimtrace.xz     " \
        "437.leslie3d-271B.champsimtrace.xz     " \
        "437.leslie3d-273B.champsimtrace.xz     " \
        "444.namd-120B.champsimtrace.xz         " \
        "444.namd-166B.champsimtrace.xz         " \
        "444.namd-23B.champsimtrace.xz          " \
        "444.namd-321B.champsimtrace.xz         " \
        "444.namd-33B.champsimtrace.xz          " \
        "444.namd-426B.champsimtrace.xz         " \
        "444.namd-44B.champsimtrace.xz          " \
        "445.gobmk-17B.champsimtrace.xz         " \
        "445.gobmk-2B.champsimtrace.xz          " \
        "445.gobmk-30B.champsimtrace.xz         " \
        "445.gobmk-36B.champsimtrace.xz         " \
        "447.dealII-3B.champsimtrace.xz         " \
        "450.soplex-247B.champsimtrace.xz       " \
        "450.soplex-92B.champsimtrace.xz        " \
        "453.povray-252B.champsimtrace.xz       " \
        "453.povray-576B.champsimtrace.xz       " \
        "453.povray-800B.champsimtrace.xz       " \
        "453.povray-887B.champsimtrace.xz       " \
        "454.calculix-104B.champsimtrace.xz     " \
        "454.calculix-460B.champsimtrace.xz     " \
        "456.hmmer-191B.champsimtrace.xz        " \
        "456.hmmer-327B.champsimtrace.xz        " \
        "456.hmmer-88B.champsimtrace.xz         " \
        "458.sjeng-1088B.champsimtrace.xz       " \
        "458.sjeng-283B.champsimtrace.xz        " \
        "458.sjeng-31B.champsimtrace.xz         " \
        "458.sjeng-767B.champsimtrace.xz        " \
        "459.GemsFDTD-1169B.champsimtrace.xz    " \
        "459.GemsFDTD-1211B.champsimtrace.xz    " \
        "459.GemsFDTD-1320B.champsimtrace.xz    " \
        "459.GemsFDTD-1418B.champsimtrace.xz    " \
        "459.GemsFDTD-1491B.champsimtrace.xz    " \
        "459.GemsFDTD-765B.champsimtrace.xz     " \
        "462.libquantum-1343B.champsimtrace.xz  " \
        "462.libquantum-714B.champsimtrace.xz   " \
        "464.h264ref-30B.champsimtrace.xz       " \
        "464.h264ref-57B.champsimtrace.xz       " \
        "464.h264ref-64B.champsimtrace.xz       " \
        "464.h264ref-97B.champsimtrace.xz       " \
        "465.tonto-1914B.champsimtrace.xz       " \
        "465.tonto-44B.champsimtrace.xz         " \
        "470.lbm-1274B.champsimtrace.xz         " \
        "471.omnetpp-188B.champsimtrace.xz      " \
        "473.astar-153B.champsimtrace.xz        " \
        "473.astar-359B.champsimtrace.xz        " \
        "473.astar-42B.champsimtrace.xz         " \
        "481.wrf-1170B.champsimtrace.xz         " \
        "481.wrf-1254B.champsimtrace.xz         " \
        "481.wrf-1281B.champsimtrace.xz         " \
        "481.wrf-196B.champsimtrace.xz          " \
        "481.wrf-455B.champsimtrace.xz          " \
        "481.wrf-816B.champsimtrace.xz          " \
        "482.sphinx3-1100B.champsimtrace.xz     " \
        "482.sphinx3-1297B.champsimtrace.xz     " \
        "482.sphinx3-1395B.champsimtrace.xz     " \
        "482.sphinx3-1522B.champsimtrace.xz     " \
        "482.sphinx3-234B.champsimtrace.xz      " \
        "482.sphinx3-417B.champsimtrace.xz      " \
        "483.xalancbmk-127B.champsimtrace.xz    " \
        "483.xalancbmk-716B.champsimtrace.xz    " \
        "483.xalancbmk-736B.champsimtrace.xz    " \
        "600.perlbench_s-1273B.champsimtrace.xz " \
        "600.perlbench_s-210B.champsimtrace.xz  " \
        "600.perlbench_s-570B.champsimtrace.xz  " \
        "602.gcc_s-1850B.champsimtrace.xz       " \
        "602.gcc_s-2226B.champsimtrace.xz       " \
        "602.gcc_s-2375B.champsimtrace.xz       " \
        "602.gcc_s-734B.champsimtrace.xz        " \
        "603.bwaves_s-1080B.champsimtrace.xz    " \
        "603.bwaves_s-1740B.champsimtrace.xz    " \
        "603.bwaves_s-2609B.champsimtrace.xz    " \
        "603.bwaves_s-2931B.champsimtrace.xz    " \
        "603.bwaves_s-3699B.champsimtrace.xz    " \
        "603.bwaves_s-5359B.champsimtrace.xz    " \
        "603.bwaves_s-891B.champsimtrace.xz     " \
        "605.mcf_s-1152B.champsimtrace.xz       " \
        "605.mcf_s-1536B.champsimtrace.xz       " \
        "605.mcf_s-1554B.champsimtrace.xz       " \
        "605.mcf_s-1644B.champsimtrace.xz       " \
        "605.mcf_s-472B.champsimtrace.xz        " \
        "605.mcf_s-484B.champsimtrace.xz        " \
        "605.mcf_s-665B.champsimtrace.xz        " \
        "605.mcf_s-782B.champsimtrace.xz        " \
        "605.mcf_s-994B.champsimtrace.xz        " \
        "607.cactuBSSN_s-2421B.champsimtrace.xz " \
        "607.cactuBSSN_s-3477B.champsimtrace.xz " \
        "607.cactuBSSN_s-4004B.champsimtrace.xz " \
        "607.cactuBSSN_s-4248B.champsimtrace.xz " \
        "619.lbm_s-2676B.champsimtrace.xz       " \
        "619.lbm_s-2677B.champsimtrace.xz       " \
        "619.lbm_s-3766B.champsimtrace.xz       " \
        "619.lbm_s-4268B.champsimtrace.xz       " \
        "620.omnetpp_s-141B.champsimtrace.xz    " \
        "620.omnetpp_s-874B.champsimtrace.xz    " \
        "621.wrf_s-575B.champsimtrace.xz        " \
        "621.wrf_s-6673B.champsimtrace.xz       " \
        "621.wrf_s-8065B.champsimtrace.xz       " \
        "621.wrf_s-8100B.champsimtrace.xz       " \
        "623.xalancbmk_s-10B.champsimtrace.xz   " \
        "623.xalancbmk_s-165B.champsimtrace.xz  " \
        "623.xalancbmk_s-202B.champsimtrace.xz  " \
        "623.xalancbmk_s-325B.champsimtrace.xz  " \
        "623.xalancbmk_s-592B.champsimtrace.xz  " \
        "623.xalancbmk_s-700B.champsimtrace.xz  " \
        "625.x264_s-12B.champsimtrace.xz        " \
        "625.x264_s-18B.champsimtrace.xz        " \
        "625.x264_s-20B.champsimtrace.xz        " \
        "625.x264_s-33B.champsimtrace.xz        " \
        "625.x264_s-39B.champsimtrace.xz        " \
        "627.cam4_s-490B.champsimtrace.xz       " \
        "627.cam4_s-573B.champsimtrace.xz       " \
        "628.pop2_s-17B.champsimtrace.xz        " \
        "631.deepsjeng_s-928B.champsimtrace.xz  " \
        "638.imagick_s-10316B.champsimtrace.xz  " \
        "638.imagick_s-4128B.champsimtrace.xz   " \
        "638.imagick_s-824B.champsimtrace.xz    " \
        "641.leela_s-1052B.champsimtrace.xz     " \
        "641.leela_s-1083B.champsimtrace.xz     " \
        "641.leela_s-149B.champsimtrace.xz      " \
        "641.leela_s-334B.champsimtrace.xz      " \
        "641.leela_s-602B.champsimtrace.xz      " \
        "641.leela_s-800B.champsimtrace.xz      " \
        "641.leela_s-862B.champsimtrace.xz      " \
        "644.nab_s-12459B.champsimtrace.xz      " \
        "644.nab_s-12521B.champsimtrace.xz      " \
        "644.nab_s-5853B.champsimtrace.xz       " \
        "644.nab_s-7928B.champsimtrace.xz       " \
        "644.nab_s-9322B.champsimtrace.xz       " \
        "648.exchange2_s-1227B.champsimtrace.xz " \
        "648.exchange2_s-1247B.champsimtrace.xz " \
        "648.exchange2_s-1511B.champsimtrace.xz " \
        "648.exchange2_s-1699B.champsimtrace.xz " \
        "648.exchange2_s-1712B.champsimtrace.xz " \
        "648.exchange2_s-210B.champsimtrace.xz  " \
        "648.exchange2_s-353B.champsimtrace.xz  " \
        "648.exchange2_s-387B.champsimtrace.xz  " \
        "648.exchange2_s-584B.champsimtrace.xz  " \
        "648.exchange2_s-72B.champsimtrace.xz   " \
        "649.fotonik3d_s-10881B.champsimtrace.xz" \
        "649.fotonik3d_s-1176B.champsimtrace.xz " \
        "649.fotonik3d_s-1B.champsimtrace.xz    " \
        "649.fotonik3d_s-7084B.champsimtrace.xz " \
        "649.fotonik3d_s-8225B.champsimtrace.xz " \
        "654.roms_s-1007B.champsimtrace.xz      " \
        "654.roms_s-1021B.champsimtrace.xz      " \
        "654.roms_s-1070B.champsimtrace.xz      " \
        "654.roms_s-1390B.champsimtrace.xz      " \
        "654.roms_s-1613B.champsimtrace.xz      " \
        "654.roms_s-293B.champsimtrace.xz       " \
        "654.roms_s-294B.champsimtrace.xz       " \
        "654.roms_s-523B.champsimtrace.xz       " \
        "654.roms_s-842B.champsimtrace.xz       " \
        "657.xz_s-2302B.champsimtrace.xz        " \
        "657.xz_s-3167B.champsimtrace.xz        " \
        "657.xz_s-4994B.champsimtrace.xz        " \
        "657.xz_s-56B.champsimtrace.xz          ")

echo "${BOLD}Running All Traces in dpc_traces folder (filenames must not be changed)"

for i in "${TRACE[@]}"
do
    FILENAME="$(echo -e "${i}" | tr -d '[:space:]')"
    FILE=./dpc3_traces/$FILENAME
    if test -f "$FILE"; then
       
       echo -n -e "\033[0mRunning trace $i ... \t"

        ./run_champsim.sh ${BINARY_NAME} ${WARMUP} ${SIM} ${FILENAME}

        retVal=$?
        if [ $retVal -ne 0 ]; then
            if [ $retVal -ne 130 ]; then
                echo "Failed"
            else
                echo "Terminated"
                exit 1
            fi
        else
            echo "Done"
        fi
    fi
done

echo "${BOLD}Full Run Finished!"

