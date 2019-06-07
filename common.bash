#/bin/bash

invalid_argument() {
    if [ -z "$2" ]
    then
        echo "Invalid argument $1"
    else
        echo "Invalid argument $1 for flag '$2'"
    fi
    exit 1
}
export -f invalid_argument

missing_argument() {
    echo "Missing argument for $1"
    exit 1
}
export -f missing_argument

# Set the project being set up
set_project() {
    gcloud projects list | sed 's/  \+/ /g' | grep "$1 " &> /dev/null
    if [[ $? == 1 ]]
    then
        echo "Invalid project id $1"
        exit 1
    fi

    gcloud config set project $1 &> /dev/null
    PROJECT=$1
}
export -f set_project
