#!/bin/sh
# set -x
DOCKER_PUBLISH_DATE="20200903"

UBUNTU_RELEASE_NAME="bionic"

UBUNTU_DOCKER_TAG="ubuntu:${UBUNTU_RELEASE_NAME}-${DOCKER_PUBLISH_DATE}"

DOCKER_INSTANCE_NAME="ub18-instance"

HOST_KEY_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

VM_REDIRECT_SSH_PORT="2222"

SSH_OPTIONS="${HOST_KEY_OPTIONS} -t -p ${VM_REDIRECT_SSH_PORT}"

TIMEOUT_VAL="5m"

IMAGE_FILE_NAME="bionic-server-cloudimg-arm64.img"

CLOUD_IMAGE_CURRENT_LINK="http://cloud-images.ubuntu.com/${UBUNTU_RELEASE_NAME}/current/${IMAGE_FILE_NAME}"

QEMU_EFI_IMAGE_LINK="https://releases.linaro.org/components/kernel/uefi-linaro/latest/release/qemu64/QEMU_EFI.fd"

SHA1_SUMS_LINK="http://cloud-images.ubuntu.com/${UBUNTU_RELEASE_NAME}/current/SHA1SUMS"

SSH_PUB_KEY_PATH=`readlink -f ~/.ssh/id_rsa.pub`

CLOUD_CONFIG_FILE_NAME="gen-cloud.txt"

create_cloud_config_file()
{

test -f  ${SSH_PUB_KEY_PATH} || { echo "ssh key not found,please generate one"; exit 1; }

key_content=`cat ${SSH_PUB_KEY_PATH}`

cat > "${CLOUD_CONFIG_FILE_NAME}" <<_EOF_
#cloud-config
users:
  - name: ${USER}
    ssh-authorized-keys:
      - ${key_content}
    sudo: ['ALL=(ALL) NOPASSWD:ALL']
    groups: sudo
    shell: /bin/bash
_EOF_

echo "${CLOUD_CONFIG_FILE_NAME} generated."

}

create_cloud_config_file

cleanup_vm()
{
	ssh ${SSH_OPTIONS} localhost "sudo init 0" || true
	
	echo "waiting for qemu to exit"

	sleep 120

	qemu_pid=`pgrep -lfa qemu | grep working.img | cut -d" " -f1`

	if [ -n "$qemu_pid" ]
	then
		kill -9 $qemu_pid || {  echo "could not kill running qemu"; exit 1;  }
	fi
}

if [ ! -f "${IMAGE_FILE_NAME}" ]
then
	echo "downloading ${CLOUD_IMAGE_CURRENT_LINK}"
	curl -O ${CLOUD_IMAGE_CURRENT_LINK} || { echo "could not download image : ${CLOUD_IMAGE_CURRENT_LINK}"; exit 1; }
fi

echo "downloading ${SHA1_SUMS_LINK}"
curl -O "${SHA1_SUMS_LINK}" || { echo "could not download : SHA1SUMS"; exit 1; }


echo "verifying sha1sum of ${IMAGE_FILE_NAME}"

publised_sum=`grep "${IMAGE_FILE_NAME}" SHA1SUMS | cut -d" " -f 1`
actual_sum=`sha1sum ${IMAGE_FILE_NAME} | cut -d" " -f1`


if [ "${publised_sum}" != "${actual_sum}" ]
then
	rm -f ${IMAGE_FILE_NAME}
	echo "${CLOUD_IMAGE_CURRENT_LINK} sum mismatch, restart the script again"
	exit 1
fi

echo "downloading ${QEMU_EFI_IMAGE_LINK}"
curl -O ${QEMU_EFI_IMAGE_LINK} || { echo "could not download : ${QEMU_EFI_IMAGE_LINK}"; exit 1; }


rm -f flash0.img flash1.img working.img cloud.img

test -f QEMU_EFI.fd || { echo "QEMU_EFI.fd file not found"; exit 1; }

test -f ${IMAGE_FILE_NAME} || { echo "${IMAGE_FILE_NAME} file not found"; exit 1; }


dd if=/dev/zero of=flash0.img bs=1M count=64 || { echo "could not create flash files for qemu"; exit 1; }
dd if=QEMU_EFI.fd of=flash0.img conv=notrunc || { echo "could not create flash files for qemu"; exit 1; }
dd if=/dev/zero of=flash1.img bs=1M count=64 || { echo "could not create flash files for qemu"; exit 1; }

cp ${IMAGE_FILE_NAME} working.img || { echo "could not duplicate to working working.img"; exit 1; }

cloud-localds --disk-format qcow2 cloud.img ${CLOUD_CONFIG_FILE_NAME} || { echo "could not create cloud-init image"; exit 1; }

qemu-img resize working.img +3G || { echo "could not resize the working image"; exit 1; }

echo "starting qemu"

qemu-system-aarch64 -m 2048 -smp 2 -cpu cortex-a57 -M virt -vnc :10 \
  -pflash flash0.img \
  -pflash flash1.img \
  -drive if=none,file=working.img,id=hd0 \
  -device virtio-blk-device,drive=hd0 \
  -drive if=none,id=cloud,file=cloud.img \
  -device virtio-blk-device,drive=cloud \
  -netdev user,id=user0 -device virtio-net-device,netdev=user0 \
  -redir tcp:${VM_REDIRECT_SSH_PORT}::22 -daemonize || { echo "starting qemu failed"; exit 1; }

exit 1
echo "qemu started, waiting for ssh"

while true
do
	ssh ${SSH_OPTIONS} localhost "uname -a" || { echo "waiting for ssh to start"; sleep 5 ;continue; }
	if [ $? -eq 0 ]
	then
		break
	fi
done

cleanup_vm;exit 1

ssh ${SSH_OPTIONS} localhost "sudo apt update && sudo apt install -y docker.io" || { echo "could not run apt commands on VM"; cleanup_vm;exit 1; }

ssh ${SSH_OPTIONS} localhost "sudo docker pull ${UBUNTU_DOCKER_TAG}" || { echo "could not run docke pull on VM"; cleanup_vm;exit 1; }

ssh ${SSH_OPTIONS} localhost "sudo docker stop ub18-instance" || { echo "no instances to stop"; }

ssh ${SSH_OPTIONS} localhost "sudo docker rm ub18-instance" || { echo "no instances to remove"; }

ssh ${SSH_OPTIONS} localhost "sudo docker run --rm -it --name ub18-instance -d ${UBUNTU_DOCKER_TAG}" || { echo "could not start docker image on VM"; cleanup_vm;exit 1; }

ssh ${SSH_OPTIONS} localhost 'sudo docker exec -it ub18-instance dpkg --add-architecture armhf' || { echo "could not add foreign arch in container"; cleanup_vm;exit 1; }

ssh ${SSH_OPTIONS} localhost 'sudo docker exec -it ub18-instance apt update' || { echo "could not run apt commands in docker contaner"; cleanup_vm;exit 1; }

ssh ${SSH_OPTIONS} localhost 'sudo docker exec -it ub18-instance apt install -y symlinks libc6-dev libc6-dev:armhf libcurl4-openssl-dev libcurl4-openssl-dev:armhf zlib1g-dev zlib1g-dev:armhf libmd-dev libmd-dev:armhf libexpat1-dev libexpat1-dev:armhf libncurses5-dev libncurses5-dev:armhf libpython2.7-dev libpython2.7-dev:armhf libdb5.3-dev libpython3.7-dev libpython3.7-dev:armhf libssl-dev libpam0g-dev libssl-dev:armhf libpam0g-dev:armhf libstdc++6:armhf libz1 libz1:armhf libbz2-1.0:armhf' || { echo "could not install packages inside docker"; cleanup_vm;exit 1; }

ssh ${SSH_OPTIONS} localhost 'sudo docker exec -it ub18-instance symlinks -cr /usr /lib' || { echo "could not run symlinks command in docker contaner"; cleanup_vm;exit 1; }

ssh ${SSH_OPTIONS} localhost 'sudo mkdir -p /sysroot' || { echo "could not create sysroot dir"; cleanup_vm;exit 1; }

ssh ${SSH_OPTIONS} localhost 'sudo docker cp ub18-instance:/usr /sysroot' || { echo "could not copy files from docker contaner"; cleanup_vm;exit 1; }
ssh ${SSH_OPTIONS} localhost 'sudo docker cp ub18-instance:/lib /sysroot' || { echo "could not copy files from docker contaner"; cleanup_vm;exit 1; }

SYSROOT_PUBLISH_DATE=`date +'%Y%m%d'`

OUTPUT_DIR_NAME="aarch64-ubuntu-${UBUNTU_RELEASE_NAME}-${DOCKER_PUBLISH_DATE}/${SYSROOT_PUBLISH_DATE}"

rm -rf ${OUTPUT_DIR_NAME}

mkdir -p ${OUTPUT_DIR_NAME}

scp ${HOST_KEY_OPTIONS} -P ${VM_REDIRECT_SSH_PORT} -r localhost:/sysroot/ ${OUTPUT_DIR_NAME}

cleanup_vm