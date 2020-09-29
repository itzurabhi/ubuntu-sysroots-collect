#!/bin/sh
	set -x

DOCKER_PUBLISH_DATE="20200903"

UBUNTU_RELEASE_NAME="bionic"

ALL_ARCHS="arm64v8:armhf x86_64:i386"

for arch in ${ALL_ARCHS};do

	main_arch=`echo $arch | cut -d":" -f 1`
	compat_arch=`echo $arch | cut -d":" -f 2`

	echo "Collecting $main_arch ($compat_arch) files"

	UBUNTU_DOCKER_TAG="$main_arch/ubuntu:${UBUNTU_RELEASE_NAME}-${DOCKER_PUBLISH_DATE}"

	if [ "$main_arch" = "x86_64" ]
	then
		UBUNTU_DOCKER_TAG="ubuntu:${UBUNTU_RELEASE_NAME}-${DOCKER_PUBLISH_DATE}"		
	fi
	

	DOCKER_INSTANCE_NAME="ub18-sysroot-image"

	cleanup()
	{
		docker stop ${DOCKER_INSTANCE_NAME} || { echo "no instances to stop"; }
		sleep 5
		docker rm ${DOCKER_INSTANCE_NAME} || { echo "no instances to remove"; }
	}

	docker run --rm --privileged multiarch/qemu-user-static --reset -p yes

	docker pull ${UBUNTU_DOCKER_TAG} || { echo "could not run docke pull on VM"; cleanup;exit 1; }

	cleanup

	docker run --rm -it --name ${DOCKER_INSTANCE_NAME} -d ${UBUNTU_DOCKER_TAG} || { echo "could not start docker image on VM"; cleanup;exit 1; }

	docker exec -it ${DOCKER_INSTANCE_NAME} dpkg --add-architecture ${compat_arch} || { echo "could not add foreign arch in container"; cleanup;exit 1; }

	docker exec -it ${DOCKER_INSTANCE_NAME} apt update || { echo "could not run apt commands in docker contaner"; cleanup;exit 1; }

	docker exec -it ${DOCKER_INSTANCE_NAME} apt install -y symlinks libc6-dev libc6-dev:${compat_arch} libcurl4-openssl-dev libcurl4-openssl-dev:${compat_arch} zlib1g-dev zlib1g-dev:${compat_arch} libmd-dev libmd-dev:${compat_arch} libexpat1-dev libexpat1-dev:${compat_arch} libncurses5-dev libncurses5-dev:${compat_arch} libpython2.7-dev libpython2.7-dev:${compat_arch} libdb5.3-dev libpython3.7-dev libpython3.7-dev:${compat_arch} libssl-dev libpam0g-dev libssl-dev:${compat_arch} libpam0g-dev:${compat_arch} libstdc++6:${compat_arch} libz1 libz1:${compat_arch} libbz2-1.0:${compat_arch} || { echo "could not install packages inside docker"; cleanup;exit 1; }

	docker exec -it ${DOCKER_INSTANCE_NAME} symlinks -cr /usr /lib || { echo "could not run symlinks command in docker contaner"; cleanup;exit 1; }

	SYSROOT_PUBLISH_DATE=`date +'%Y%m%d'`

	OUTPUT_DIR_NAME="${UBUNTU_RELEASE_NAME}-${DOCKER_PUBLISH_DATE}/${SYSROOT_PUBLISH_DATE}/${main_arch}"

	rm -rf ${OUTPUT_DIR_NAME}

	mkdir -p ${OUTPUT_DIR_NAME} || { echo "could not create sysroot dir ${OUTPUT_DIR_NAME}"; cleanup;exit 1; }

	docker cp ${DOCKER_INSTANCE_NAME}:/usr ${OUTPUT_DIR_NAME} || { echo "could not copy files from docker contaner"; cleanup;exit 1; }

	docker cp ${DOCKER_INSTANCE_NAME}:/lib ${OUTPUT_DIR_NAME} || { echo "could not copy files from docker contaner"; cleanup;exit 1; }

	cleanup

	rm -rf ${OUTPUT_DIR_NAME}/usr/bin ${OUTPUT_DIR_NAME}/usr/sbin || { echo "removing bin and sbin directories"; }

done