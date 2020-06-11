#!/usr/bin/env bash

# Micro/user-case benchmark script

# /os-disk
# /dev/sdf1        32895856 13632448   17569356  44% /32gb
# /dev/sde1       131979748    60984  125191548   1% /128gb
# /dev/sdd1      1056762036 13656352  989402260   2% /1024gb
# /dev/sdc1      2113655728 13655060 1992610156   1% /2048gb

DEBUG=${DEBUG:=0}
MAXRUNS=${MAXRUNS:=6}
BCCENABLED=${BCCON:=1}
WARMCACHE=${WARMCACHE:=1}

timestamp=$(date +%T)
resultsdir_base="$PWD/test_results"
resultsdir="${resultsdir_base}-${timestamp}"
diagdir="${resultsdir}/diagnostics"
testsdir="$PWD/user-tests"
targets=("/ephemeral" "/os-disk")
PROCESS_FORKS=()
halttoken="/tmp/halt"

interrogate () {
    fn="${resultsdir}/system-info"
    echo "$(uname -a)" >>$fn
    sudo -i echo "$(echo "cpu:    ")" "$(cat /proc/cpuinfo  | grep "model name" | head -1 | cut -d":" -f2)" >>$fn
    sudo -i echo "$(echo "cores:    ")" "$(cat /proc/cpuinfo  | grep processor | wc -l)" >>$fn
    echo "===========================================================" >> $fn
    for device in /sys/block/sd*;
    do
        echo "Device:     ${device}"

        sudo -i echo "$(echo "scheduler:    ")" "$(cat $device/queue/scheduler)" >>$fn
        sudo -i echo "$(echo "read_ahead_kb:    ")" "$(cat $device/queue/read_ahead_kb)" >>$fn
        sudo -i echo "$(echo "max_sectors_kb:    ")" "$(cat $device/queue/max_sectors_kb)" >>$fn
    done
    sudo -i echo "$(echo "transparent_hugepage:    ")" "$(cat /sys/kernel/mm/transparent_hugepage/enabled)" >>$fn
    sudo -i echo "$(echo "panic_on_oom:    ")" "$(cat /proc/sys/vm/panic_on_oom )">>$fn
    sudo -i echo "$(echo "swappiness:    ")" "$(cat /proc/sys/vm/swappiness)" >>$fn
    sudo -i echo "$(echo "kernel panic:    ")" "$(cat /proc/sys/kernel/panic)" >>$fn
    sudo echo "\n\n" >> $fn
    sudo -i echo "$(df -h)" >>$fn
    chmod a+rw ${fn}
}

spawn_watchers () {
    target=$1
    echo "diagnostics dir: ${target}"
    mkdir -p ${target}

    bcc_cmds=( "nohup /usr/share/bcc/tools/ext4slower 1 -j > ${target}/ext4slower.log 2>&1 &"
            "nohup /usr/share/bcc/tools/biosnoop -Q > ${target}/biosnoop.log 2>&1 &"
            "nohup /usr/share/bcc/tools/gethostlatency > ${target}/hostlatency.log 2>&1 &"
            "nohup /usr/share/bcc/tools/runqlat -m 5 > ${target}/queuelatency.log 2>&1 &" )
    base_cmds=( "/usr/sbin/iotop -b --only > ${target}/iotop.log 2>&1 &" )
    # add top cpu mem

    if [ "${BCCENABLED}" -eq 1 ]; then

        for comm in "${bcc_cmds[@]}"; do
            eval "${comm}"
            new_pid=$!
            PROCESS_FORKS+=( "${new_pid}" )
        done
    fi
    # for comm in "${base_cmds[@]}"; do
    #     eval "${comm}"
    #     new_pid=$!
    #     PROCESS_FORKS+=( "${new_pid}" )
    # done

}

kill_watch () {
    for x in "${PROCESS_FORKS[@]}"; do
        kill "${x}" >/dev/null 2>&1
    done
    PROCESS_FORKS=()
}

function onexit() {
    for x in "${PROCESS_FORKS[@]}"; do
        kill "${x}" >/dev/null 2>&1
    done
    PROCESS_FORKS=()
}

drive_directories () {
    disks=$(sudo fdisk -l | grep Disk | grep "/dev" | awk '{print $2}' | cut -d ":" -f1)
    for i in ${disks};
    do
        if [ "${i}" != "/dev/sda" ] && [ "${i}" != "/dev/sdb" ]; then
            sizen=$(sudo fdisk "${i}" -l | grep Disk | grep "/dev" | awk '{print $3$4}' | cut -d "," -f1)
            targets+=("/${sizen}")
        fi
    done
}

main () {
    trap onexit INT TERM ERR
    trap onexit EXIT

    if [ -e ${halttoken} ]; then
        echo -n "Detected ${halttoken} - remove (y/n)? "
        read -r answer
        if [ "$answer" != "${answer#[Yy]}" ]; then
            rm -f ${halttoken}
        else
            exit 1
        fi
    fi

    echo "checking ${resultsdir}"

    mkdir -p "${resultsdir}"

    interrogate
    drive_directories

    for directory in "${targets[@]}"; do
        if [ -e "${halttoken}" ]; then
            exit 1
        fi
        dname=$(basename "${directory}")
        mkdir -p "${resultsdir}/${dname}"
        echo "moving to ${directory}"
        cd "${directory}" || exit 1
        rm -rf "${directory:?}/*"
        globber="${testsdir}/*.sh"
        for f in $globber; do
            if [ -e "${halttoken}" ]; then
                exit 1
            fi
            echo -e "setting up for ${f}:\n"
            scr="${directory}/scratch-temp"
            cache="${directory}/cache"
            # Setup scratch directory for tests
            rm -rf "${scr}" && mkdir -p "${scr}"
            script=$(realpath "${f}")
            scriptpath=$(dirname "${script}")
            if [ "${DEBUG}" -eq 1 ]; then
                echo "  file: ${f}"
                echo "  scratch: ${scr}"
                echo "  script: ${script}"
                echo "  scriptpath: ${scriptpath}"
            fi
            if [ "${WARMCACHE}" -eq 1 ]; then
                # Execute the command without timing to warm the cache
                echo "warming the cache with initial ${f} execution"
                ${script} ${scr} ${cache} >${scr}/cmd.out.log
            fi
            base=$(basename "${script}")
            diagdir="${resultsdir}${directory}/diagnostics"
            mkdir -p "${diagdir}"
            spawn_watchers "${diagdir}"
            sleep 5
            # Run a loop of $MAXRUNS iterations
            for (( c=1; c<=MAXRUNS; c++ )); do

                result="${resultsdir}${directory}.${base}.results"
                echo "[TEST] disk: ${directory} test: ${script} run: $c stamp: $(date)"
                /usr/bin/time -o "${result}" --append -f "%E real,%U user,%S sys" "${script}" "${scr}" "${cache}"
                # Check test status; if it fails, we drop a halt token vs performing a hard stop
                status=$?
                if [[ ! ${status} -eq 0 ]]; then
                    echo "${script} execution failed, exiting"
                    touch /tmp/halt
                fi
                echo "[RESULT] disk: ${directory} test: ${script}  run: ${c}: $(tail -n 1 ${result})"
                # Note: each test is responsible for the rm -rf of it's output directory
            done
            kill_watch
            rm -rf "${cache}" && mkdir -p "${cache}"
        done
        echo -e "  \n"
    done
}

main
