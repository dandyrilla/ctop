#!/bin/bash


SCRIPT=$(readlink -f $0)
SCRIPTPATH=$(dirname $SCRIPT)
CONFIGPATH=${SCRIPTPATH}/nodes


function max() {
    max=
    while (( "$#" )); do
        if [ -z "$max" ]; then
            max=$1
        else
            [ "$1" -gt "$max" ] && max=$1
        fi
        shift
    done
    return ${max}
}

function min() {
    min=
    while (( "$#" )); do
        if [ -z "$min" ]; then
            min=$1
        else
            [ "$1" -lt "$min" ] && min=$1
        fi
        shift
    done
    return ${min}
}

function repeatchr() {
    chr=$1
    len=$2
    rept=
    while [ ${#rept} -lt $len ]; do
        rept=${rept}${chr}
    done
    echo ${rept}
}

function fixrows() {
    clear
    COLS=$( tput cols )
    LINES=$( tput lines )
    echo -ne "$header"
    echo -ne "$footer"
}


while read line; do

    [ "$line" == "" ] && continue
    [[ $line == \#* ]] && continue

    [ -z "${i}" ] && i=0

    col=($line)
    name[${i}]=${col[0]}
    ip[${i}]=${col[1]}

    n=$(( ${#col[@]}-2 ))

    for j in `seq 2 $[ $n + 1 ]`; do
        if [[ ${col[$j]} == np\=* ]]; then
            np[$i]=${col[$j]:3}
        elif [[ ${col[$j]} == c\=* ]]; then
            c[$i]=$(( ${col[$j]:2} + 2 ))
        elif [[ ${col[$j]} == r\=* ]]; then
            r[$i]=$(( ${col[$j]:2} + 3 ))
        elif [[ ${col[$j]} == size\=* ]]; then
            size[${i}]=${col[$j]:5}
        fi
    done

    d[${i}]=$(( ${c[${i}]} + ${size[${i}]} - 1 ))

    (( i++ ))

done < ${CONFIGPATH}


## {{{ strings

min ${r[@]}; min_r=$?
max ${r[@]}; max_r=$?
min ${c[@]}; min_c=$?
max ${d[@]}; max_c=$?


# restore cursor place
cur_r=$((${max_r}+4))
cur_c=1
rc="\033[${cur_r};${cur_c}H"

## escape characters
es="\033[47;30m"    # emphasis starts
ee="\033[0m"        # emphasis ends


gray="\033[1;30m"   # gray
red="\033[1;31m"    # red
green="\033[1;32m"  # green
yellow="\033[1;33m" # yellow
sky="\033[1;36m"    # sky
blue="\033[1;34m"   # blue
default="\033[0m"   # default


hr=2
hc=3
hspan=$(($max_c - $min_c + 1))

esc1="\033[${hr};${hc}H${es}"
esc2="${ee}${rc}"
text1=$( printf "%-$(( ${hspan} - 10 ))s" "   ctop" )
text2=$( printf "%10s" "$HOSTNAME   " )
header="${esc1}${text1}${text2}${esc2}"

mode="cpu"


fr=$((${max_r}+2))
fc=3

## }}}


function loop_ctop() {
    
    for i in `seq 0 $(( ${#name[@]} - 1 ))`; do

        width=$(( ${size[$i]} - ${#name[$i]} - 3 ))

        bar=$(repeatchr "#" ${width})
        grid=$(repeatchr "-" ${width})

        #echo -ne "\033[${r[$i]};${c[$i]}H${name[$i]} [${gray}${grid}${default}]${rc}"

        # CPU USAGE MODE
        if [ "$mode" == "cpu" ]; then
            ssh ${name[$i]} "top -b -d 1 | awk ' /Cpu/ {
                bar=\"${bar}\"
                grid=\"${grid}\"
                
                split(\$0, cpu_status, \":\")
                gsub(/ /, \"\", cpu_status[2])
                gsub(/%[a-z][a-z]/, \"\", cpu_status[2])
                split(cpu_status[2], cpu_each, \",\")

                cpu_us=int(${width}*cpu_each[1]/100)
                cpu_sy=int(${width}*cpu_each[2]/100)
                cpu_ni=int(${width}*cpu_each[3]/100)
                cpu_id=int(${width}*cpu_each[4]/100)
                cpu_wa=int(${width}*cpu_each[5]/100)
                cpu_sum=(cpu_us+cpu_sy+cpu_ni+cpu_wa)

                graph=sprintf(\"${green}%s\",           substr(bar, 1, cpu_us))
                graph=sprintf(\"%s${sky}%s\",    graph, substr(bar, 1, cpu_sy))
                graph=sprintf(\"%s${yellow}%s\", graph, substr(bar, 1, cpu_ni))
                graph=sprintf(\"%s${blue}%s\",   graph, substr(bar, 1, cpu_wa))
                graph=sprintf(\"%s${gray}%s\",   graph, substr(grid, cpu_sum+1))
                graph=sprintf(\"%s${default}\",  graph)

                printf(\"\033[${r[$i]};${c[$i]}H\")
                printf(\"${name[$i]} \")
                printf(\"[%s]\", graph)
                printf(\"${rc}\")
                fflush()
            }

            '" &

        # MEMORY USAGE MODE
        elif [ "$mode" == "mem" ]; then

            ssh ${name[$i]} "free -s 1 | awk '/Mem:/ {
                bar=\"${bar}\"
                grid=\"${grid}\"

                mem_used=\$3
                mem_free=\$7
                mem_sum=(mem_used+mem_free)
                mem_used_block=${width}*mem_used/mem_sum
                graph=sprintf(\"${red}%s\",            substr(bar, 1, mem_used_block))
                graph=sprintf(\"%s${gray}%s\",  graph, substr(grid, mem_used_block+1))
                graph=sprintf(\"%s${default}\", graph)

                printf(\"\033[${r[$i]};${c[$i]}H\")
                printf(\"${name[$i]} \")
                printf(\"[%s]\", graph)
                printf(\"${rc}\")
                fflush()
            }

            '" &
        fi
        pid[${i}]=$!
    done
        

    while true; do

        esc1="\033[${fr};${fc}H${es}"
        esc2="${ee}${rc}"
        date="$(date +"%F %T")"
        text1=$( printf "%-10s" "   ${mode}" )
        text2=$( printf "%$(( $hspan - 10 ))s" "${date}   " )
        footer="${esc1}${text1}${text2}${esc2}"

        echo -ne "${header}${footer}"
        sleep 1
    done &

    (( i++ ))

    pid[${i}]=$!
}


exec 2> /dev/null  # For supressing a "Killed" message
trap fixrows SIGWINCH
trap '' SIGINT
fixrows
loop_ctop


while true; do

    read -n 1 key_press

    if [ "$key_press" == "q" ] || [ "$key_press" == "Q" ]; then
        echo -ne "\b \b"
        kill -9 ${pid[@]}
        break
    elif [ "$key_press" == "m" ] || [ "$key_press" == "M" ]; then
        echo -ne "\b \b"
        kill -9 ${pid[@]}
        pid=
        if [ "$mode" == "cpu" ]; then mode="mem"
        elif [ "$mode" == "mem" ]; then mode="cpu"
        fi
        loop_ctop
    else
        echo -ne "\b \b"
    fi

done


## }}}


