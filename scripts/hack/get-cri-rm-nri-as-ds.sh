#!/bin/bash -e

# This script fetches relevant containerd sources and prepares cri-resmgr NRI
# supported container image and related DaemonSet deployment yaml file that
# can be installed in the node.
#
# This script is expected to be run in the node itself so it is only meant
# as a quick tool to try the CRI-RM DaemonSet feature and should not be used
# in a production system.

# First build and prepare CRI-RM image that can be imported into containerd.
# Note that Docker is used for building so it must be installed in this system.

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJECT_DIR="$(dirname "$(dirname "$(realpath "$SCRIPT_DIR")")")"
OUTPUT_DIR=${outdir-"$SCRIPT_DIR"/output}
CONTAINERD_SRC=${containerd_src-"$PROJECT_DIR"/../containerd}

error() {
    (echo ""; echo "error: $1" ) >&2
    exit ${1:-1}
}

if [ ! -d "$CONTAINERD_SRC" ]; then
    echo "Fetch containerd sources like this:"
    echo "    cd $PROJECT_DIR/.."
    echo "    git clone https://github.com/klihub/containerd.git"
    echo "    git checkout -b pr/proto/nri origin/pr/proto/nri"
    echo
    echo "Install also Python toml tool:"
    echo "    pip3 install toml tomli_w"
    echo
    error "Containerd source directory not found. Set \"containerd_src\" env variable to point to it and re-run this script."
fi

(cd $CONTAINERD_SRC; make)
if [ $? -ne 0 ]; then
    error "Please fix containerd compilation issues."
fi

if [ ! -f /etc/nri/nri.conf ]; then
    mkdir -p /etc/nri
    if [ $? -ne 0 ]; then
	error "Cannot create /etc/nri"
    fi

    echo "disableConnections: false" > /etc/nri/nri.conf

    mkdir -p /opt/nri/plugins
fi

if [ ! -x "$CONTAINERD_SRC/bin/containerd" ]; then
    error "$CONTAINERD_SRC/bin/containerd does not exists"
fi

echo "Trying to start containerd. Earlier version is being stopped. If stopping fails, then please make sure other containerd version is not running."
sleep 2
systemctl stop containerd
if [ ! -f /usr/bin/containerd.orig ]; then
    cp /usr/bin/containerd /usr/bin/containerd.orig
fi
cp "$CONTAINERD_SRC/bin/containerd" /usr/bin/containerd
containerd config dump > /etc/containerd/config.toml
systemctl start containerd

$PROJECT_DIR/test/e2e/containerd-nri-enable

mkdir -p $OUTPUT_DIR
if [ $? -ne 0 ]; then
    error "Cannot create $OUTPUT_DIR"
fi

SAVE_FILE=/tmp/cri-rm-nri-ds-deployment.$$
save_cmds=$SAVE_FILE outdir=$OUTPUT_DIR $PROJECT_DIR/scripts/build/prepare-crirm-nri-ds.sh
if [ $? -ne 0 ]; then
    rm -f $SAVE_FILE
    error "Cannot prepare CRI-RM NRI image for DaemonSet."
fi

bash $SAVE_FILE
rm -f $SAVE_FILE
