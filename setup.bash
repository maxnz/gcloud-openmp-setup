#/bin/bash

USED_ZONES=
NUMUSEDZONES=0
OLD_PROJECT=`gcloud config list project 2> /dev/null | grep "project = " | cut -d ' ' -f 3`
PROJECT=
PREFIX='openmp-'
VMCORES=8
re_num='^[0-9]+$'
QUIET=0

# Ask user for the project they want to use
ask_project() {
    echo -n "Project Name (leave blank to use current project $OLD_PROJECT): "
    read project

    if [[ $project != "" ]]
    then
        set_project $project
    else
        set_project $OLD_PROJECT
    fi
}

# Get a random zone from zones.txt
get_rand_zone() {
    if [[ $NUMUSEDZONES == 20 ]]
    then
        echo "No remaining zones"
        exit 1
    fi
    z=$RANDOM
    numzones=`wc zones.txt -l | cut -d ' ' -f 1`
    let "z %= $numzones"
    let "z++"
    ZONE=`sed "${z}q;d" zones.txt`
    zonec=`echo $ZONE | cut -d '-' -f 1`
    zonel=`echo $ZONE | cut -d '-' -f 2`
    zone="${zonec}-${zonel}"
    echo $USED_ZONES | grep $zone &> /dev/null
    if [[ $? == 0 ]]
    then
        get_rand_zone
    else
        USED_ZONES="$USED_ZONES $ZONE"
        let "NUMUSEDZONES++"

        touch quotas.temp
        gcloud compute regions describe $zone > quotas.temp

        LINES=`wc quotas.temp -l | cut -d ' ' -f 1`
        for ((i=1;i<=LINES;i++))
        do
            LINE=`sed "${i}q;d" quotas.temp`
            echo $LINE | grep "limit:" &> /dev/null
            if [[ $? == 0 ]]
            then
                sed "$(($i+1))q;d" quotas.temp | grep "CPUS" &> /dev/null
                if [[ $? == 0 ]]
                then
                    REGCPUUSAGE=`sed "$(($i+2))q;d" quotas.temp | sed 's/  \+/ /g' | cut -d ' ' -f 3 | cut -d '.' -f 1`
                    REGCPUQUOTA=`sed "${i}q;d" quotas.temp | sed 's/  \+/ /g' | cut -d ' ' -f 3 | cut -d '.' -f 1`
                    let "REGREMCPUS = $REGCPUQUOTA - $REGCPUUSAGE"
                    if [ $REGREMCPUS -lt $VMCORES ]
                    then
                        echo "Not enough CPUs remaining in region quota: $REGREMCPUS remaining in $zone"
                        get_rand_zone
                    fi
                    break
                fi
            fi
        done
        rm quotas.temp
    fi
}

get_quota() {
    touch quotas.temp
    gcloud compute project-info describe --project $PROJECT > quotas.temp

    LINES=`wc quotas.temp -l | cut -d ' ' -f 1`
    for ((i=1;i<=LINES;i++))
    do
        LINE=`sed "${i}q;d" quotas.temp`

        echo $LINE | grep "limit:" &> /dev/null
        if [[ $? == 0 ]]
        then
            sed "$(($i+1))q;d" quotas.temp | grep "CPUS_ALL_REGIONS" &> /dev/null
            if [[ $? == 0 ]]
            then
                CPUUSAGE=`sed "$(($i+2))q;d" quotas.temp | sed 's/  \+/ /g' | cut -d ' ' -f 3 | cut -d '.' -f 1`
                CPUQUOTA=`sed "${i}q;d" quotas.temp | sed 's/  \+/ /g' | cut -d ' ' -f 3 | cut -d '.' -f 1`
                let "REMCPUS = $CPUQUOTA - $CPUUSAGE"
                if [ $REMCPUS -lt $VMCORES ]
                then
                    echo "Not enough CPUs remaining in quota: $REMCPUS remaining"
                    exit 1
                fi
                break
            fi
        fi
    done
    rm quotas.temp
}

confirm_opts() {
    INSTANCES=`gcloud compute instances list &> /dev/null`

    for ((i=0;;i++))
    do
        echo $INSTANCES | grep "$PREFIX$i " &> /dev/null
        if [[ $? != 0 ]]
        then
            NAME="$PREFIX$i"
            break
        fi
    done

    echo
    echo "Configuration:"
    echo "Project:           $PROJECT"
    echo "VM Size:           $VMCORES Cores"
    echo "VM Name:           $NAME"
    if [[ $QUIET == 1 ]]; then return; fi;
    echo -n "Continue? (Y/n): "
    read con
    con=`echo $con | head -c1`
    if [[ $con == 'n' || $con == 'N' ]]
    then
        echo "Abort"
        exit -1
    fi
}

# Set up VM
create_vm() {
    echo "Creating VM"

    while true
    do
        get_rand_zone
        gcloud compute instances create \
        --machine-type=n1-standard-$VMCORES --image-family=debian-9 \
        --image-project=debian-cloud --zone $ZONE $NAME > /dev/null

        RET=$?
        if [[ $RET != 0 ]]
        then
            echo "Exception while creating VM. Retrying."
            continue
        fi
        break
    done
}

# Configure the VM
config_vm() {
    gcloud compute ssh $NAME --zone $ZONE --command \
    "sudo apt install g++ make -y; \
     cd /etc/skel; \
     sudo wget http://csinparallel.cs.stolaf.edu/CSinParallel.tar.gz; \
     sudo tar -xf CSinParallel.tar.gz && sudo rm CSinParallel.tar.gz; \
     sudo cp -r /etc/skel/CSinParallel ~"
}


source "./common.bash"

while test $# -gt 0
do
    case "$1" in
        -h|--help)
            echo "GCloud OpenMP VM Setup Script"
            echo
            echo "Options:"
            echo "-h,   --help          show this help message"
            echo "-p,   --project ID    set the project to use (ID = full project id)"
            echo
            echo "-q,   --quiet         run the script with default options (unless specified otherwise):"
            echo "                          8 cores"
            echo "-c [1|2|4|8|16|32|64|96]  set the number of cores in the VM"
            exit -1
            ;;
        -q|--quiet)
            shift
            if [[ $PROJECT == "" ]]; then PROJECT=$OLD_PROJECT; fi;
            QUIET=1
            ;;
        -c)
            shift
            if test $# -gt 0
            then
                VMCORES=$1
                if ! [[ $VMCORES =~ $re_num ]]
                then
                    invalid_argument $VMCORES "-c"
                fi
                if ! [[ $VMCORES == 1 || $VMCORES == 2 || $VMCORES == 4 || $VMCORES == 8 || \
                        $VMCORES == 16 || $VMCORES == 32 || $VMCORES == 64 || $VMCORES == 96 ]]
                then
                    invalid_argument $VMCORES "-c"
                fi
                shift
            else
                missing_argument "-c"
            fi
            ;;
        -p|--project)
            shift
            if test $# -gt 0
            then
                set_project $1
                shift
            else
                missing_argument "-p|--project"
            fi
            ;;
        *)
            echo "Unrecognized flag $1"
            exit 1
            ;;
    esac
done

if [[ $PROJECT == "" ]]
then
    ask_project
fi

get_quota
confirm_opts
create_vm
gcloud compute config-ssh &> /dev/null
config_vm

if [[ $PROJECT != $OLD_PROJECT ]]
then
    set_project $OLD_PROJECT
fi
