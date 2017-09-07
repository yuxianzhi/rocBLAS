#!/usr/bin/env bash
# Author: Kent Knox

# #################################################
# Pre-requisites check
# #################################################
# Exit code 0: alls well
# Exit code 1: problems with getopt
# Exit code 2: problems with supported platforms

# check if getopt command is installed
type getopt > /dev/null
if [[ $? -ne 0 ]]; then
  echo "This script uses getopt to parse arguments; try installing the util-linux package";
  exit 1
fi

# lsb-release file describes the system
if [[ ! -e "/etc/lsb-release" ]]; then
  echo "This script depends on the /etc/lsb-release file"
  exit 2
fi
source /etc/lsb-release

if [[ ${DISTRIB_ID} != Ubuntu ]]; then
  echo "This script only validated with Ubuntu"
  exit 2
fi

# #################################################
# helper functions
# #################################################
function display_help()
{
  echo "rocBLAS build & installation helper script"
  echo "./install [-h|--help] "
  echo "    [-h|--help] prints this help message"
  echo "    [-i|--install] install after build"
  echo "    [-d|--dependencies] install build dependencies"
  echo "    [-c|--clients] build library clients too (combines with -i & -d)"
}

# #################################################
# global variables
# #################################################
install_package=false
install_dependencies=false
build_clients=false

# #################################################
# Parameter parsing
# #################################################

# check if we have a modern version of getopt that can handle whitespace and long parameters
getopt -T
if [[ $? -eq 4 ]]; then
  GETOPT_PARSE=$(getopt --name "${0}" --longoptions help,install,clients,dependencies: --options hicd -- "$@")
else
  echo "Need a new version of getopt"
  exit 1
fi

if [[ $? -ne 0 ]]; then
  echo "getopt invocation failed; could not parse the command line";
  exit 1
fi

eval set -- "${GETOPT_PARSE}"

while true; do
  case "${1}" in
    -h|--help)
        display_help
        exit 0
        ;;
    -i|--install)
        install_package=true
        shift ;;
    -d|--dependencies)
        install_dependencies=true
        shift ;;
    -c|--clients)
        build_clients=true
        shift ;;
    --) shift ; break ;;
    *)  echo "Unexpected command line parameter received; aborting";
        exit 1
        ;;
  esac
done

build_dir=build
printf "\033[32mCreating project build directory in: \033[33m./${build_dir}\033[0m\n"

# #################################################
# prep
# #################################################
# ensure a clean build environment
rm -rf ${build_dir}

# #################################################
# install build dependencies on request
# #################################################
if [[ "${install_dependencies}" == true ]]; then
  # dependencies needed for rocblas and clients to build
  library_dependencies_ubuntu=( "make" "cmake-curses-gui" "python2.7" "python-yaml" "hip_hcc" "hcc" "pkg-config" )
  client_dependencies_ubuntu=( "gfortran" "libboost-program-options-dev" )

  sudo apt update

  # Dependencies required by main library
  for package in "${library_dependencies_ubuntu[@]}"; do
    if [[ $(dpkg-query --show --showformat='${db:Status-Abbrev}\n' ${package} 2> /dev/null | grep -q "ii"; echo $?) -ne 0 ]]; then
      printf "\033[32mInstalling \033[33m${package}\033[32m from distro package manager\033[0m\n"
      sudo apt install -y --no-install-recommends ${package}
    fi
  done

  # Dependencies required by library client apps
  if [[ "${build_clients}" == true ]]; then
    for package in "${client_dependencies_ubuntu[@]}"; do
    if [[ $(dpkg-query --show --showformat='${db:Status-Abbrev}\n' ${package} 2> /dev/null | grep -q "ii"; echo $?) -ne 0 ]]; then
        printf "\033[32mInstalling \033[33m${package}\033[32m from distro package manager\033[0m\n"
        sudo apt install -y --no-install-recommends ${package}
      fi
    done

    # The following builds googletest & lapack from source, installs into cmake default /usr/local
    pushd .
      printf "\033[32mBuilding \033[33mgoogletest & lapack\033[32m from source; installing into \033[33m/usr/local\033[0m\n"
      mkdir -p ${build_dir}/deps && cd ${build_dir}/deps
      cmake -DBUILD_BOOST=OFF ../../deps
      make -j$(nproc)
      sudo make install
    popd
  fi

fi

pushd .
# #################################################
# configure
# #################################################
  mkdir -p ${build_dir}/release && cd ${build_dir}/release
  export CXX=/opt/rocm/bin/hcc
  if [[ "${build_clients}" == true ]]; then
    cmake -DBUILD_CLIENTS_SAMPLES=ON -DBUILD_CLIENTS_TESTS=ON -DBUILD_CLIENTS_BENCHMARKS=ON ../..
  else
    cmake ../..
  fi

# #################################################
# build
# #################################################
  make -j$(nproc)

# #################################################
# install
# #################################################
# installing through package manager, which makes uninstalling easy
  if [[ "${install_package}" == true ]]; then
    make package
    sudo dpkg -i rocblas-*.deb
  fi
popd