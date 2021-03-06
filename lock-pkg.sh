#!/bin/bash

set -e

PKG_MGR=""
DISTRO=""

show_help() {
    cat <<EOF
Usage: $(basename $0) [-h] [-U] [-f [-l | -u]] [packages...]

Options:
  -h | --help				show this help
  -f | --from-file			read packages from file (local or remote)
  -l | --lock-pkg <packages>		lock packages		
  -u | --unlock-pkg <packages>		unlock packages
  -U | --unlock-all-pkg			clear all locks 

Examples:
  $(basename $0) -l package1 package2
  $(basename $0) -f -l http://example.com/packages.txt   

EOF
}

is_url() {
    if echo $1 | grep -qi '^http://' || echo $1 | grep -qi '^https://'; then
        return 0
    else
        return 1
    fi

}

curl_url() {
    # check http header to see if url gives 200 response.
    http_response=$(curl --silent --head --request GET $1 | head -1)
    if ! echo $http_response | grep -qi 200; then
        echo "error: $http_response" >&2
        exit 1
    else
        echo $(curl $1)
    fi
}

wrapp_cmd() {
    # this function wrapps command execution by providing formatted output
    # and it exits with error if command returns status code different than 0
    cmd=$1
    args=${@:2}

    rc=0
    result=$(eval "$cmd" "$args" 2>&1) || rc=$?
    while read line; do echo "$cmd: '${line}'"; done <<<"$result"
    if [[ $rc -ne 0 ]]; then
        echo "error: $cmd non-zero exit code [$rc]"
        exit 1
    fi
}

id_distro() {
    DISTRO=$( (lsb_release -ds || cat /etc/*release) 2>/dev/null | head -n1)
    if echo $DISTRO | grep -qi ubuntu || echo $DISTRO | grep -qi debian; then
        PKG_MGR="apt"
    elif echo $DISTRO | grep -qi 'red hat' || echo $DISTRO | grep -qi centos || echo $DISTRO | grep -qi amazon; then
        PKG_MGR="yum"
    elif echo $DISTRO | grep -qi suse; then
        PKG_MGR="zypper"
    else
        echo "error: unknown distribution"
        exit 1
    fi
}

lock_pkg() {
    for package in $1; do
        if [[ "$PKG_MGR" == "apt" ]]; then
            wrapp_cmd apt-mark hold $package
        elif [[ "$PKG_MGR" == "yum" ]]; then
            wrapp_cmd yum versionlock add $package
        elif [[ "$PKG_MGR" == "zypper" ]]; then
            wrapp_cmd zypper addlock $package
        else
            echo "error: non-matching condition"
            exit 1
        fi
    done
}

unlock_pkg() {
    for package in $1; do
        if [[ "$PKG_MGR" == "apt" ]]; then
            wrapp_cmd apt-mark unhold $package
        elif [[ "$PKG_MGR" == "yum" ]]; then
            wrapp_cmd yum versionlock delete $package
        elif [[ "$PKG_MGR" == "zypper" ]]; then
            wrapp_cmd zypper removelock $package
        else
            echo "error: non-matching condition"
            exit 1
        fi
    done
}

unlock_all_pkg() {
    if [[ "$PKG_MGR" == "apt" ]]; then
        wrapp_cmd apt-mark unhold $(apt-mark showhold)
    elif [[ "$PKG_MGR" == "yum" ]]; then
        wrapp_cmd yum versionlock clear
    elif [[ "$PKG_MGR" == "zypper" ]]; then
        # zypper removelock $(zypper locks | grep '^[[:digit:]]' | awk '{print $3}')
        wrapp_cmd zypper removelock $(zypper --xmlout locks | grep -o '<name>.*</name>' | sed -e 's/<name>\(.*\)<\/name>/\1/g')
    else
        echo "error: non-matching condition"
        exit 1
    fi
}

opt_from_file=false
while :; do
    case $1 in
    -h | --help)
        show_help
        exit
        ;;

    -f | --from-file)
        opt_from_file=true
        ;;

    -l | --lock-pkg)
        id_distro
        echo "identifying distribution: $DISTRO"
        echo "locking package(s) using: '$PKG_MGR'"
        if [[ -n $2 ]]; then
            if $opt_from_file && is_url $2; then
                echo "fetching package's list from remote file '$2'"
                packages=$(curl_url $2)
                lock_pkg "$packages"
            elif $opt_from_file; then
                echo "fetching package's list from local file '$2'"
                packages=$(cat $2)
                lock_pkg "$packages"
            else
                packages=""
                # using grep as it's more portable than regex
                # while [[ $2 ]] && ! [[ "$2" =~ ^-.*$ ]]; do packages="$packages $2"; shift; done
                while [[ $2 ]] && echo $2 | grep --quiet --ignore-case --invert-match '^-.*$'; do
                    packages="$packages $2"
                    shift
                done
                lock_pkg "$packages"
            fi
        else
            echo 'error: "--lock-pkg" requires a non-empty option argument'
            exit 1
        fi
        break
        ;;

    -u | --unlock-pkg)
        id_distro
        echo "identifying distribution: $DISTRO"
        echo "unlocking package(s) using: '$PKG_MGR'"
        if [[ -n $2 ]]; then
            if $opt_from_file && is_url $2; then
                echo "fetching package's list from remote file '$2'"
                packages=$(curl_url $2)
                unlock_pkg "$packages"
            elif $opt_from_file; then
                echo "fetching package's list from local file '$2'"
                packages=$(cat $2)
                lock_pkg "$packages"
            else
                packages=""
                # using grep as it's more portable than regex
                # while [[ $2 ]] && ! [[ "$2" =~ ^-.*$ ]]; do packages="$packages $2"; shift; done
                while [[ $2 ]] && echo $2 | grep --quiet --ignore-case --invert-match '^-.*$'; do
                    packages="$packages $2"
                    shift
                done
                unlock_pkg "$packages"
            fi
        else
            echo 'error: "--unlock-pkg" requires a non-empty option argument'
            exit 1
        fi
        break
        ;;

    -U | --unlock-all-pkg)
        id_distro
        echo "identifying distribution: $DISTRO"
        echo "unlocking all packages using: '$PKG_MGR'"
        unlock_all_pkg
        break
        ;;

    *)
        echo "error: unknow option"
        show_help
        exit 1
        ;;
    esac
    shift
done
