#!/bin/bash

OLD_PROJECT=`gcloud config list project 2> /dev/null | grep "project = " | cut -d ' ' -f 3`
PROJECT=$OLD_PROJECT
PSET=0
FILENAME=
AUTO=0
USERNAME=
KEY=
USERCOL=
KEYCOL=
re_num='^[0-9]+$'
NAME="openmp-"
NAMED=0
VMID=
VMIP=
VMZONE=
INVALID=0


add_user() {
    RET=`gcloud compute ssh $VMID $VMZONE --command \
        "sudo useradd -m -s /bin/bash \"$USERNAME\";" 2>&1`

    echo $RET | grep "already exists" &> /dev/null
    RET=$?
    RET2=1

    if [[ $RET == 0 ]]
    then
        echo "$USERNAME: User exists - checking key"

        gcloud compute ssh $VMID $VMZONE --command "sudo cat /home/$USERNAME/.ssh/authorized_keys" | \
        grep -Fx "$KEY" &> /dev/null
        if [[ $? == 0 ]]; then RET2=0; fi;
    else
        echo "$USERNAME: Creating new user"
    fi

    if [[ $RET2 == 1 ]]
    then
        echo "Adding new SSH key"
        gcloud compute ssh $VMID $VMZONE --command \
        "echo | sudo tee -a /home/$USERNAME/.ssh/authorized_keys &> /dev/null; \
         echo \"# $USERNAME\" | sudo tee -a /home/$USERNAME/.ssh/authorized_keys &> /dev/null; \
         echo \"$KEY\" | sudo tee -a /home/$USERNAME/.ssh/authorized_keys &> /dev/null;"
    fi
}

ask_project() {
    if [[ $PSET == 0 ]]
    then
        echo -n "Project Name (leave blank to use default project $OLD_PROJECT): "
        read project

        if [[ $project != "" ]]
        then
            PROJECT=$project
            set_project $PROJECT
        fi
    fi

    touch vms.temp
    gcloud compute instances list > vms.temp
}

get_vm() {
    VM=`sed "$(($1 + 1))q;d" vms.temp | grep "RUNNING" | sed 's/  \+/ /g' | cut -d ' ' -f 1,2`

    echo $VM | grep "$NAME" &> /dev/null
    if [[ $? != 0 ]]
    then
        VM=
    fi
}

find_vm() {
    NUMVM=`gcloud compute instances list | wc -l | cut -d ' ' -f 1`
    let "NUMVM -= 1"

    for ((i=1;i<=NUMVM;i++))
    do
        get_vm $i
        if ! [[ -z $VM ]]
        then
            if [[ $NAMED == 1 ]]; then echo "Using VM $NAME"; break; fi;
            echo -n "Use VM $(echo $VM | cut -d ' ' -f 1)? (Y/n): "
            read con
            con=`echo $con | head -c1`
            if [[ $con == 'n' || $con == 'N' ]]
            then
                VM=
                continue
            fi
            break
        fi
    done
    rm vms.temp
    if [[ -z $VM ]]; then echo "Could not find VM"; exit 1; fi;
    VMID=`echo $VM | cut -d ' ' -f 1`
    VMZONE=`echo $VM | cut -d ' ' -f 2`
    VMZONE="--zone $VMZONE"
}

# Validate username format
validate_username() {
    echo $USERNAME | grep " " &> /dev/null
    if [[ $? == 0 || $USERNAME == "" ]]
    then
        echo "$USERNAME: Skipping: Invalid Username"
        let "INVALID++"
    fi
}

# Validate key format
validate_key() {
    keywc=`echo $KEY | wc -w | cut -d ' ' -f 1`

    if [[ $KEY == "" || $keywc != 3 ]]
    then
        echo "$USERNAME: Skipping: Invalid SSH key"
        let "INVALID++"
    fi
}

# Automated entry from a .csv file
auto_entry() {
    # Install csvtool if necessary
    apt list csvtool | grep "installed" &> /dev/null
    if [[ $? != 0 ]]
    then
        if [ "$EUID" -ne 0 ]
        then 
            echo "sudo required"
            echo "Try running the script again with sudo"
            exit 1
        else
            sudo apt install csvtool
        fi
    fi

    ask_project
    find_vm

    # Get username column if necessary
    if [[ -z $USERCOL ]]
    then
        echo -n "Specify username column number: "
        read USERCOL
        if ! [[ $USERCOL =~ $re_num ]]
        then
            invalid_argument $USERCOL
        fi
    fi

    # Get key column if necessary
    if [[ -z $KEYCOL ]]
    then
        echo -n "Specify ssh key column number: "
        read KEYCOL
        if ! [[ $KEYCOL =~ $re_num ]]
        then
            invalid_argument $KEYCOL
        fi
    fi

    NUMKEY=`csvtool height $FILENAME`
    
    # Add all users
    for ((i=2;i<=NUMKEY;i++))
    do
        USERNAME=`csvtool col $USERCOL $FILENAME | sed "${i}q;d"`
        KEY=`csvtool col $KEYCOL $FILENAME | sed "${i}q;d"`

        INVALID=0
        validate_username
        validate_key
        if [ $INVALID -gt 0 ]; then continue; fi;
        add_user
    done

    echo
}

# Manual entry by user
manual_entry() {
    ask_project
    find_vm

    while true 
    do
        echo
        echo -n "Enter new username (leave blank to quit): "
        read USERNAME

        if [[ $USERNAME == "" ]]
        then
            break
        fi

        echo -n "Enter SSH key for $USERNAME: "
        read KEY

        if [[ $KEY == "" ]]
        then
            break
        fi

        INVALID=0
        validate_username
        validate_key
        if [ $INVALID -gt 0 ]; then continue; fi;
        add_user
    done
}


source "./common.bash"

while test $# -gt 0
do
    case "$1" in
        -h|--help)
            echo "GCloud OpenMP VM User Setup Script"
            echo
            echo "Options:"
            echo "-h,   --help          show this help message"
            echo "-p,   --project ID    set the project to use (ID = full project id)"
            echo "-n,   --name NAME     specify the name of the VM to be configured"
            echo "                          if not specified, will look for VMs"
            echo "                          starting with 'openmp-'"
            echo
            echo "-f FILE               specify the .csv file (FILE) to use"
            echo "-k N                  specify the column number (N) with the ssh keys"
            echo "-u N                  specify the column number (N) with the usernames"
            exit -1
            ;;
        -f)
            shift
            if test $# -gt 0
            then
                FILENAME=$1
                AUTO=1
                shift
            else
                missing_argument "-f"
            fi
            ;;
        -n|--name)
            shift
            if test $# -gt 0
            then
                NAME=$1
                NAMED=1
                shift
            else
                missing_argument "-n|--name"
            fi
            ;;
        -p|--project)
            shift
            PSET=1
            if test $# -gt 0
            then
                set_project $1
                shift
            else
                missing_argument "-p|--project"
            fi
            ;;
        -u)
            shift
            if test $# -gt 0
            then
                USERCOL=$1
                if ! [[ $USERCOL =~ $re_num ]]
                then
                    invalid_argument $USERCOL "-u"
                fi
                shift
            else
                missing_argument "-u"
            fi
            ;;
        -k)
            shift
            if test $# -gt 0
            then
                KEYCOL=$1
                if ! [[ $KEYCOL =~ $re_num ]]
                then
                    invalid_argument $KEYCOL "-k"
                fi
                shift
            else
                missing_argument "-k"
            fi
            ;;
        *)
            echo "Unrecognized flag $1"
            exit 1
            ;;
    esac
done

if [[ $AUTO == 1 ]]
then
    echo "Automatic Entry"
    auto_entry
else
    echo "Manual Entry"
    manual_entry
fi

echo -n "VM IP..."
gcloud compute instances list | sed 's/  \+/ /g' | grep $VMID | cut -d ' ' -f 5

if [[ $PROJECT != $OLD_PROJECT ]]
then
    set_project $OLD_PROJECT
fi
