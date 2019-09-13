#--------------------------
# Depends on filesystem.sh
#--------------------------

# docker-build
# Usage: docker-build image_contents_dir image_full_name_and_tag

DOCKER_BUILD_MISSING_IMAGE_TAG=76
DOCKER_BUILD_IMAGE_CONTENTS_DIR_NOT_FOUND=77

# Param image_contents_dir
# Param image_full_name_and_tag
function docker-build
{
	local image_contents_dir=$1
	local image_full_name_and_tag=$2

	directory-exists "$image_contents_dir" || return $DOCKER_BUILD_IMAGE_CONTENTS_DIR_NOT_FOUND

	if [ -z "$image_full_name_and_tag" ]
	then
		echo "Missing image_full_name_and_tag." >&2
		return $DOCKER_BUILD_MISSING_IMAGE_TAG
	fi

	echo "Building docker image $image_full_name_and_tag ..."
	docker build "$image_contents_dir/." -t $image_full_name_and_tag
}

# docker-push
# Usage: docker-push image_full_name_and_tag

DOCKER_PUSH_MISSING_IMAGE_TAG=79

# Param image_full_name_and_tag
function docker-push
{
	local image_full_name_and_tag=$1

	if [ -z "$image_full_name_and_tag" ]
	then
		echo "Missing image_full_name_and_tag." >&2
		return $DOCKER_PUSH_MISSING_IMAGE_TAG
	fi	

	echo "Pushing docker image $image_full_name_and_tag ..."
	docker push $image_full_name_and_tag	
}