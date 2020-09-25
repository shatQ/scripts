#!/bin/bash

set -e

pkg_manager=""

show_help() {
    cat <<EOF
Usage: $(basename $0) [OPTION...] PACKAGES...

Options:
  -h | --help				show this help
  -l | --lock-pkg <packages>		lock packages (space-separated list or url)		
  -u | --unlock-pkg <packages>		unlock packages (space-separated list or url) 
  -U | --unlock-all-pkg			clear all locks 

Examples:
  $(basename $0) -l 'package1 package2'
  $(basename $0) -l http://example.com/packages.txt   

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
    # Check http header to see if url gives 200 response.
    http_response=$(curl --silent --head --request GET $1 | head -1)
    if ! echo $http_response | grep -qi 200; then
        echo "error: $http_response" >&2
        exit 1
    else
        echo $(curl $1)
    fi
}

run_cmd() {
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

check_distro() {
    distro=$( (lsb_release -ds || cat /etc/*release) 2>/dev/null | head -n1)
    if echo $distro | grep -qi ubuntu || echo $distro | grep -qi debian; then
        pkg_manager="apt"
    elif echo $distro | grep -qi 'red hat' || echo $distro | grep -qi centos || echo $distro | grep -qi amazon; then
        pkg_manager="yum"
    elif echo $distro | grep -qi suse; then
        pkg_manager="zypper"
    else
        echo "error: unknown distro"
    fi
}

lock_pkg() {
    for package in $1; do
        if [[ "$pkg_manager" == "apt" ]]; then
            run_cmd apt-mark hold $package
        elif [[ "$pkg_manager" == "yum" ]]; then
            run_cmd yum versionlock add $package
        elif [[ "$pkg_manager" == "zypper" ]]; then
            run_cmd zypper addlock $package
        else
            echo "error: non-matching condition"
        fi
    done
}

unlock_pkg() {
    for package in $1; do
        if [[ "$pkg_manager" == "apt" ]]; then
            run_cmd apt-mark unhold $package
        elif [[ "$pkg_manager" == "yum" ]]; then
            run_cmd yum versionlock delete $package
        elif [[ "$pkg_manager" == "zypper" ]]; then
            run_cmd zypper removelock $package
        else
            echo "error: non-matching condition"
        fi
    done
}

unlock_all_pkg() {
    if [[ "$pkg_manager" == "apt" ]]; then
        run_cmd apt-mark unhold $(apt-mark showhold)
    elif [[ "$pkg_manager" == "yum" ]]; then
        run_cmd yum versionlock clear
    elif [[ "$pkg_manager" == "zypper" ]]; then
        # zypper removelock $(zypper locks | grep '^[[:digit:]]' | awk '{print $3}')
        run_cmd zypper removelock $(zypper --xmlout locks | grep -o '<name>.*</name>' | sed -e 's/<name>\(.*\)<\/name>/\1/g')
    else
        echo "error: non-matching condition"
    fi
}

while :; do
    case $1 in
    -h | --help)
        show_help
        exit
        ;;

    -l | --lock-pkg)
        check_distro
        echo "locking package(s)"
        if [[ -n $2 ]]; then
            if is_url $2; then
                echo "fetching package's list from $2"
                packages=$(curl_url $2)
                lock_pkg "$packages"
            else
                packages=""
                # while [[ $2 ]] && ! [[ "$2" =~ ^-.*$ ]]; do packages="$packages $2"; shift; done
                while [[ $2 ]] && echo $2 | grep --quiet --ignore-case --invert-match '^-.*$'; do
                    packages="$packages $2"
                    shift
                done
                lock_pkg "$packages"
            fi
        else
            echo 'error: "--lock-pkg" requires a non-empty option argument'
        fi
        break
        ;;

    -u | --unlock-pkg)
        check_distro
        echo "unlocking package(s)"
        if [[ -n $2 ]]; then
            if is_url $2; then
                echo "fetching package's list from $2"
                packages=$(curl_url $2)
                unlock_pkg "$packages"
            else
                packages=""
                # while [[ $2 ]] && ! [[ "$2" =~ ^-.*$ ]]; do packages="$packages $2"; shift; done
                while [[ $2 ]] && echo $2 | grep --quiet --ignore-case --invert-match '^-.*$'; do
                    packages="$packages $2"
                    shift
                done
                unlock_pkg "$packages"
            fi
        else
            echo 'error: "--unlock-pkg" requires a non-empty option argument'
        fi
        break
        ;;
    
    -U | --unlock-all-pkg)
        check_distro
        echo "unlocking all packages"
        unlock_all_pkg
        shift
        break
        ;;

    *)
        echo "error: unknow option"
        show_help
        exit
        ;;
    esac
    shift
done
