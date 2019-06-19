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
    if grep $USERNAME users.temp &> /dev/null
    then
        echo -n "$USERNAME: User exists - checking key..."
        if ! grep -Fx "$KEY" keys.temp/$USERNAME &> /dev/null
        then
            echo -n "adding key...";
            gcloud compute ssh $VMID $VMZONE --command \
            "echo | sudo tee -a /home/$USERNAME/.ssh/authorized_keys &> /dev/null;
             echo \"# $USERNAME\" | sudo tee -a /home/$USERNAME/.ssh/authorized_keys &> /dev/null;
             echo \"$KEY\" | sudo tee -a /home/$USERNAME/.ssh/authorized_keys &> /dev/null;"
            echo > keys.temp/$USERNAME &> /dev/null;
            echo "# $USERNAME" > keys.temp/$USERNAME &> /dev/null;
            echo \"$KEY\" > keys.temp/$USERNAME &> /dev/null;
        fi
        echo "done"
    else
        echo -n "$USERNAME: Creating new user..."
        gcloud compute ssh $VMID $VMZONE --command \
        "sudo useradd -m -s /bin/bash \"$USERNAME\";
         echo | sudo tee -a /home/$USERNAME/.ssh/authorized_keys &> /dev/null;
         echo \"# $USERNAME\" | sudo tee -a /home/$USERNAME/.ssh/authorized_keys &> /dev/null;
         echo \"$KEY\" | sudo tee -a /home/$USERNAME/.ssh/authorized_keys &> /dev/null;"
        echo $USERNAME >> users.temp
        echo "done"
    fi
}

ask_project() {
    if [[ $PSET == 0 ]]
    then
        echo -n "Project Name (leave blank to use current project $OLD_PROJECT): "
        read project

        if [[ $project != "" ]]
        then
            PROJECT=$project
            set_project $PROJECT
        fi
    fi

    touch vms.temp
    echo -n "Getting VMs..."
    gcloud compute instances list > vms.temp
    echo "done"
}

get_vm() {
    VM=`sed "$(($1 + 1))q;d" vms.temp | grep "RUNNING" | sed 's/  \+/ /g' | cut -d ' ' -f 1,2`

    if ! echo $VM | grep "$NAME" &> /dev/null
    then
        VM=
    fi
}

find_vm() {
    NUMVM=`wc -l vms.temp | cut -d ' ' -f 1`
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
    sed -i 's/"//g' $FILENAME

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
        USERNAME=`csvtool col $USERCOL $FILENAME | sed "${i}q;d" | sed 's/"//g'`
        KEY=`csvtool col $KEYCOL $FILENAME | sed "${i}q;d" | sed 's/"//g'`

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

    while true 
    do
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
    # Check if csvtool is installed
    if ! apt list csvtool | grep "installed" &> /dev/null
    then
        if [ "$EUID" -ne 0 ]
        then 
            echo "Please install csvtool using:"
            echo "  sudo apt install csvtool"
            echo "to use automatic entry"
            exit 1
        fi
    fi
fi

ask_project
find_vm

touch users.temp
echo -n "Finding users..."
gcloud compute ssh $VMID $VMZONE --command "getent passwd | grep '/home' | cut -d ':' -f 1" > users.temp
USERS=`cat users.temp | tr '\n' ' '`
echo -n "keys..."
gcloud compute ssh $MASTERID $MZONE --command "mkdir keys.temp; for user in $USERS; do sudo cat /home/\$user/.ssh/authorized_keys > keys.temp/\$user; done;" &> /dev/null
gcloud compute scp $MZONE --recurse $MASTERID:keys.temp . &> /dev/null
echo "done"


if [[ $AUTO == 1 ]]
then
    echo "Using Automatic Entry"
    auto_entry
else
    echo "Using Manual Entry"
    manual_entry
fi

echo -n "VM IP..."
if [ -e vms.temp ]; then cat vms.temp | sed 's/  \+/ /g' | grep $VMID | cut -d ' ' -f 5;
else gcloud compute instances list | sed 's/  \+/ /g' | grep $VMID | cut -d ' ' -f 5; fi;

if [[ $PROJECT != $OLD_PROJECT ]]
then
    set_project $OLD_PROJECT
fi

if [ -e users.temp ]; then rm users.temp; fi;
if [ -e vms.temp ]; then rm vms.temp; fi;
if [ -e keys.temp ]; then rm -r keys.temp; fi;
