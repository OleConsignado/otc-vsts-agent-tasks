#------------------------------------------------
# Depends on filesystem.sh; assert.sh; console.sh
#------------------------------------------------

# docker-build
# Usage: docker-build image_contents_dir image_full_name_and_tag

DOCKER_BUILD_IMAGE_CONTENTS_DIR_NOT_FOUND=77

# Param image_contents_dir
# Param image_full_name_and_tag
function docker-build
{
	local image_contents_dir=$1
	local image_full_name_and_tag=$2

	directory-exists "$image_contents_dir" || return $DOCKER_BUILD_IMAGE_CONTENTS_DIR_NOT_FOUND
	assert-not-empty image_full_name_and_tag

	echo "Building docker image $image_full_name_and_tag ..."
	docker build "$image_contents_dir/." -t $image_full_name_and_tag
}

# docker-push
# Usage: docker-push image_full_name_and_tag

# Param image_full_name_and_tag
function docker-push
{
	local image_full_name_and_tag=$1
	assert-not-empty image_full_name_and_tag
	echo "Pushing docker image $image_full_name_and_tag ..."
	docker push $image_full_name_and_tag	
}