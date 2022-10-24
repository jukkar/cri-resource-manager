#!/bin/bash -e

# This script prepares cri-resmgr NRI supported container image
# and related DaemonSet deployment yaml file that can be installed
# in the node.

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
PROJECT_DIR="$(dirname "$(dirname "$(realpath "$SCRIPT_DIR")")")"
OUTPUT_DIR=${outdir-"$SCRIPT_DIR"/output}

error() {
    (echo ""; echo "error: $1" ) >&2
    exit ${1:-1}
}

mkdir -p $OUTPUT_DIR
if [ $? -ne 0 ]; then
    error "Cannot create $OUTPUT_DIR"
fi

(cd $PROJECT_DIR; make image-cri-resmgr)

crirm_image_info="$(docker images --filter=reference=cri-resmgr --format '{{.ID}} {{.Repository}}:{{.Tag}} (created {{.CreatedSince}}, {{.CreatedAt}})' | head -n 1)"
if [ -z "$crirm_image_info" ]; then
    error "cannot find cri-resmgr image on host, run \"make images\" and check \"docker images --filter=reference=cri-resmgr\""
fi

echo "Preparing cri-resmgr image: $crirm_image_info"

crirm_image_id="$(awk '{print $1}' <<< "$crirm_image_info")"
crirm_image_repotag="$(awk '{print $2}' <<< "$crirm_image_info")"
crirm_image_tar="$(realpath "$OUTPUT_DIR/cri-resmgr-image-$crirm_image_id.tar")"

docker image save "$crirm_image_repotag" > "$crirm_image_tar"

# We also create cri-resmgr-agent image so that it can be placed in the same pod as the cri-rm
(cd $PROJECT_DIR; make image-cri-resmgr-agent)

crirm_agent_image_info="$(docker images --filter=reference=cri-resmgr-agent --format '{{.ID}} {{.Repository}}:{{.Tag}} (created {{.CreatedSince}}, {{.CreatedAt}})' | head -n 1)"
if [ -z "$crirm_agent_image_info" ]; then
    error "cannot find cri-resmgr-agent image on host, run \"make images\" and check \"docker images --filter=reference=cri-resmgr-agent\""
fi

echo "Preparing cri-resmgr-agent image: $crirm_agent_image_info"

crirm_agent_image_id="$(awk '{print $1}' <<< "$crirm_agent_image_info")"
crirm_agent_image_repotag="$(awk '{print $2}' <<< "$crirm_agent_image_info")"
crirm_agent_image_tar="$(realpath "$OUTPUT_DIR/cri-resmgr-agent_image-$crirm_image_id.tar")"

docker image save "$crirm_agent_image_repotag" > "$crirm_agent_image_tar"

sed -e "s|CRIRM_IMAGE_PLACEHOLDER|$crirm_image_repotag|" \
    -e 's|^\(\s*\)tolerations:$|\1tolerations:\n\1  - {"key": "cmk", "operator": "Equal", "value": "true", "effect": "NoSchedule"}|g' \
    -e 's/imagePullPolicy: Always/imagePullPolicy: Never/g' \
    -e "s|AGENT_IMAGE_PLACEHOLDER|$crirm_agent_image_repotag|" \
    < "${PROJECT_DIR}/cmd/cri-resmgr/cri-resmgr-deployment.yaml" \
            > $OUTPUT_DIR/cri-resmgr-deployment.yaml
if [ $? -ne 0 ]; then
    error "Cannot create DaemonSet yaml deployment file."
fi

image_tar=`basename "$crirm_image_tar"`
image_agent_tar=`basename "$crirm_agent_image_tar"`

echo
echo "Copy $image_tar, $image_agent_tar and cri-resmgr-deployment.yaml file from $OUTPUT_DIR to the node and exec following commands there:"
echo
echo "    ctr -n k8s.io images import $image_tar"
echo "    ctr -n k8s.io images import $image_agent_tar"
echo "    kubectl apply -f cri-resmgr-deployment.yaml"
echo

# If save_cmds is set, then save the deployment commands into a file
# so that caller script can run them.
if [ ! -z "$save_cmds" ]; then
    echo "ctr -n k8s.io images import $OUTPUT_DIR/$image_tar" > "$save_cmds"
    echo "ctr -n k8s.io images import $OUTPUT_DIR/$image_agent_tar"  >> "$save_cmds"
    echo "kubectl apply -f $OUTPUT_DIR/cri-resmgr-deployment.yaml" >> "$save_cmds"
fi
